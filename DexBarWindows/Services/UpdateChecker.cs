using System;
using System.Net.Http;
using System.Threading.Tasks;
using Timer = System.Timers.Timer;
using System.Xml.Linq;
using System.Diagnostics;
using System.IO;
using System.Reflection;

namespace DexBarWindows.Services;

public class UpdateChecker : IDisposable
{
    private const string AppcastUrl =
        "https://raw.githubusercontent.com/SucculentGoose/dexbar/main/appcast-windows.xml";

    private static readonly HttpClient Http = new();
    private readonly Timer _timer;
    private bool _disposed;

    public event Action<string, string>? UpdateAvailable; // (newVersion, downloadUrl)

    public UpdateChecker()
    {
        // Check every 4 hours
        _timer = new Timer(TimeSpan.FromHours(4).TotalMilliseconds);
        _timer.Elapsed += async (_, _) => await CheckAsync();
        _timer.AutoReset = true;
    }

    public void Start()
    {
        // Initial check after 30 seconds (let the app settle)
        Task.Delay(TimeSpan.FromSeconds(30)).ContinueWith(_ => CheckAsync());
        _timer.Start();
    }

    public async Task CheckAsync()
    {
        try
        {
            var xml = await Http.GetStringAsync(AppcastUrl);
            var doc = XDocument.Parse(xml);
            var ns = XNamespace.Get("http://www.andymatuschak.org/xml-namespaces/sparkle");

            string? latestVersion = null;
            string? downloadUrl = null;

            foreach (var item in doc.Descendants("item"))
            {
                var version = item.Element(ns + "version")?.Value
                           ?? item.Element(ns + "shortVersionString")?.Value;
                var url = item.Element("enclosure")?.Attribute("url")?.Value;

                if (version is not null && (latestVersion is null || CompareVersions(version, latestVersion) > 0))
                {
                    latestVersion = version;
                    downloadUrl = url;
                }
            }

            if (latestVersion is null || downloadUrl is null) return;

            var currentVersion = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.0.0";
            if (CompareVersions(latestVersion, currentVersion) > 0)
            {
                UpdateAvailable?.Invoke(latestVersion, downloadUrl);
            }
        }
        catch
        {
            // Silent fail — update check is best-effort
        }
    }

    public static async Task DownloadAndLaunchInstallerAsync(string downloadUrl)
    {
        var tempPath = Path.Combine(Path.GetTempPath(), "DexBarSetup.exe");
        try
        {
            using var response = await Http.GetAsync(downloadUrl);
            response.EnsureSuccessStatusCode();
            await using var fs = File.Create(tempPath);
            await response.Content.CopyToAsync(fs);
        }
        catch
        {
            // If download fails, open the URL in the browser as fallback
            Process.Start(new ProcessStartInfo(downloadUrl) { UseShellExecute = true });
            return;
        }

        // Launch installer and exit so it can replace files
        Process.Start(new ProcessStartInfo(tempPath) { UseShellExecute = true });
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
            System.Windows.Application.Current.Shutdown());
    }

    private static int CompareVersions(string a, string b)
    {
        var pa = ParseVersion(a);
        var pb = ParseVersion(b);
        for (int i = 0; i < Math.Max(pa.Length, pb.Length); i++)
        {
            int va = i < pa.Length ? pa[i] : 0;
            int vb = i < pb.Length ? pb[i] : 0;
            if (va != vb) return va.CompareTo(vb);
        }
        return 0;
    }

    private static int[] ParseVersion(string v)
    {
        return Array.ConvertAll(v.Split('.'), s => int.TryParse(s, out var n) ? n : 0);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _timer.Stop();
        _timer.Dispose();
    }
}
