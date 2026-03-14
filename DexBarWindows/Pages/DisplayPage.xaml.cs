using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using DexBarWindows.Managers;
using DexBarWindows.Models;
using Microsoft.Win32;
using Color = System.Windows.Media.Color;
using Colors = System.Windows.Media.Colors;
using ColorConverter = System.Windows.Media.ColorConverter;

namespace DexBarWindows.Pages;

public partial class DisplayPage : System.Windows.Controls.Page
{
    private readonly GlucoseMonitor _monitor;

    private const string StartupRegKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    private const string AppName = "DexBar";

    // Suppress change handlers while loading initial values
    private bool _loading = true;

    private static readonly (int Seconds, string Label)[] RefreshOptions =
    {
        (60,  "1 minute"),
        (120, "2 minutes"),
        (300, "5 minutes"),
        (600, "10 minutes"),
        (900, "15 minutes")
    };

    public DisplayPage(GlucoseMonitor monitor)
    {
        _monitor = monitor;
        InitializeComponent();
        LoadInitialValues();
        _loading = false;
    }

    private void LoadInitialValues()
    {
        var s = _monitor.Settings;

        // Unit
        RdMgdL.IsChecked  = s.Unit == GlucoseUnit.MgdL;
        RdMmolL.IsChecked = s.Unit == GlucoseUnit.MmolL;

        // Refresh interval
        foreach (var (_, label) in RefreshOptions)
            CmbRefresh.Items.Add(label);

        int idx = Array.FindIndex(RefreshOptions, x => x.Seconds == s.RefreshIntervalSeconds);
        CmbRefresh.SelectedIndex = idx >= 0 ? idx : 2; // default to 5 min

        // Toggles
        TglShowDelta.IsChecked    = s.ShowDelta;
        TglColoredIcon.IsChecked  = s.ColoredTrayIcon;
        TglLaunchAtLogin.IsChecked = IsRegisteredForStartup();

        // Color swatches
        ApplySwatchColor(SwatchUrgentLow,  s.ColorUrgentLow);
        ApplySwatchColor(SwatchLow,        s.ColorLow);
        ApplySwatchColor(SwatchInRange,    s.ColorInRange);
        ApplySwatchColor(SwatchHigh,       s.ColorHigh);
        ApplySwatchColor(SwatchUrgentHigh, s.ColorUrgentHigh);
    }

    // -------------------------------------------------------------------------
    // Unit
    // -------------------------------------------------------------------------

    private void RdMgdL_Checked(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.Unit = GlucoseUnit.MgdL;
        _monitor.Settings.Save();
    }

    private void RdMmolL_Checked(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.Unit = GlucoseUnit.MmolL;
        _monitor.Settings.Save();
    }

    // -------------------------------------------------------------------------
    // Refresh interval
    // -------------------------------------------------------------------------

    private void CmbRefresh_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (_loading) return;
        int idx = CmbRefresh.SelectedIndex;
        if (idx < 0 || idx >= RefreshOptions.Length) return;

        var interval = TimeSpan.FromSeconds(RefreshOptions[idx].Seconds);
        _monitor.Settings.RefreshInterval = interval;
        _monitor.Settings.Save();
        _monitor.UpdateRefreshInterval(interval);
    }

    // -------------------------------------------------------------------------
    // Toggles
    // -------------------------------------------------------------------------

    private void TglShowDelta_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.ShowDelta = TglShowDelta.IsChecked == true;
        _monitor.Settings.Save();
    }

    private void TglColoredIcon_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.ColoredTrayIcon = TglColoredIcon.IsChecked == true;
        _monitor.Settings.Save();
    }

    private void TglLaunchAtLogin_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        SetStartupRegistration(TglLaunchAtLogin.IsChecked == true);
    }

    // -------------------------------------------------------------------------
    // Color swatches
    // -------------------------------------------------------------------------

    private void SwatchUrgentLow_Click(object sender, MouseButtonEventArgs e)
        => PickColor(SwatchUrgentLow, hex => { _monitor.Settings.ColorUrgentLow = hex; _monitor.Settings.Save(); });

    private void SwatchLow_Click(object sender, MouseButtonEventArgs e)
        => PickColor(SwatchLow, hex => { _monitor.Settings.ColorLow = hex; _monitor.Settings.Save(); });

    private void SwatchInRange_Click(object sender, MouseButtonEventArgs e)
        => PickColor(SwatchInRange, hex => { _monitor.Settings.ColorInRange = hex; _monitor.Settings.Save(); });

    private void SwatchHigh_Click(object sender, MouseButtonEventArgs e)
        => PickColor(SwatchHigh, hex => { _monitor.Settings.ColorHigh = hex; _monitor.Settings.Save(); });

    private void SwatchUrgentHigh_Click(object sender, MouseButtonEventArgs e)
        => PickColor(SwatchUrgentHigh, hex => { _monitor.Settings.ColorUrgentHigh = hex; _monitor.Settings.Save(); });

    private static void PickColor(System.Windows.Controls.Border swatch, Action<string> onChanged)
    {
        // Get current color from the swatch background
        System.Drawing.Color initial = System.Drawing.Color.Gray;
        if (swatch.Background is SolidColorBrush brush)
        {
            var c = brush.Color;
            initial = System.Drawing.Color.FromArgb(c.A, c.R, c.G, c.B);
        }

        using var dlg = new System.Windows.Forms.ColorDialog
        {
            Color          = initial,
            FullOpen       = true,
            AnyColor       = true,
            SolidColorOnly = true
        };

        if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            var picked = dlg.Color;
            var hex = $"#{picked.R:X2}{picked.G:X2}{picked.B:X2}";
            ApplySwatchColor(swatch, hex);
            onChanged(hex);
        }
    }

    private static void ApplySwatchColor(System.Windows.Controls.Border swatch, string hex)
    {
        try
        {
            var color = (Color)ColorConverter.ConvertFromString(hex);
            swatch.Background = new SolidColorBrush(color);
        }
        catch
        {
            swatch.Background = new SolidColorBrush(Colors.Gray);
        }
    }

    // -------------------------------------------------------------------------
    // Launch at login
    // -------------------------------------------------------------------------

    private static bool IsRegisteredForStartup()
    {
        using var key = Registry.CurrentUser.OpenSubKey(StartupRegKey);
        return key?.GetValue(AppName) is not null;
    }

    private static void SetStartupRegistration(bool enable)
    {
        using var key = Registry.CurrentUser.OpenSubKey(StartupRegKey, writable: true);
        if (key is null) return;

        if (enable)
        {
            var exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName;
            if (exePath is not null)
                key.SetValue(AppName, $"\"{exePath}\"");
        }
        else
        {
            key.DeleteValue(AppName, throwOnMissingValue: false);
        }
    }
}
