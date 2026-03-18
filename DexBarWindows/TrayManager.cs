using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using DexBarWindows.Managers;
using DexBarWindows.Models;
using DexBarWindows.Services;
using DexBarWindows.Windows;

namespace DexBarWindows;

/// <summary>
/// Manages the system tray icon lifecycle and orchestrates the popup + settings windows.
/// Replaces the WinForms TrayApplicationContext using WPF dispatcher patterns.
/// </summary>
public class TrayManager : IDisposable
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    [DllImport("user32.dll")]
    private static extern IntPtr LoadIcon(IntPtr hInstance, IntPtr lpIconName);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    private readonly GlucoseMonitor  _monitor;
    private readonly NotifyIcon      _notifyIcon;
    private readonly ToolStripMenuItem _refreshItem;
    private readonly UpdateChecker   _updateChecker;

    private PopupWindow?    _popup;
    private SettingsWindow? _settingsWindow;
    private Icon?           _currentIcon;
    private bool            _disposed;
    private string?         _pendingUpdateUrl;

    public TrayManager()
    {
        _monitor = new GlucoseMonitor();
        _monitor.OnUpdate = HandleUpdate;
        _monitor.OnAlert  = HandleAlert;

        _refreshItem = new ToolStripMenuItem("Refresh Now");
        _refreshItem.Click += async (_, _) => await _monitor.RefreshNowAsync();

        var settingsItem = new ToolStripMenuItem("Settings…");
        settingsItem.Click += (_, _) => OpenSettings();

        var quitItem = new ToolStripMenuItem("Quit");
        quitItem.Click += (_, _) => System.Windows.Application.Current.Shutdown();

        var contextMenu = new ContextMenuStrip();
        contextMenu.Items.Add(_refreshItem);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add(settingsItem);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add(quitItem);

        _currentIcon = LoadAppIcon();
        _notifyIcon = new NotifyIcon
        {
            Icon             = _currentIcon ?? SystemIcons.Application,
            Text             = "DexBar",
            ContextMenuStrip = contextMenu,
            Visible          = true
        };
        _notifyIcon.MouseClick += NotifyIcon_MouseClick;
        _notifyIcon.BalloonTipClicked += NotifyIcon_BalloonTipClicked;

        // Auto-update checker
        _updateChecker = new UpdateChecker();
        _updateChecker.UpdateAvailable += OnUpdateAvailable;
        _updateChecker.Start();

        AutoStart();
    }

    // -------------------------------------------------------------------------
    // Startup
    // -------------------------------------------------------------------------

    private void AutoStart()
    {
        var settings = _monitor.Settings;
        if (!string.IsNullOrWhiteSpace(settings.DexcomUsername))
        {
            string? password = null;
            try { password = CredentialStorage.LoadPassword(); }
            catch { /* no credential stored */ }

            if (password is not null)
            {
                _ = _monitor.StartAsync(settings.DexcomUsername, password, settings.Region);
                return;
            }
        }

        // First run — show settings so user can enter credentials
        OpenSettings();
    }

    // -------------------------------------------------------------------------
    // Monitor callbacks (always on UI thread via WPF DispatcherSynchronizationContext)
    // -------------------------------------------------------------------------

    private void HandleUpdate()
    {
        var reading  = _monitor.CurrentReading;
        var settings = _monitor.Settings;

        if (reading is not null)
        {
            var label = reading.DisplayValue(settings.Unit);
            var color = settings.ColoredTrayIcon
                ? ParseGdiColor(settings.GlucoseColor(reading.Value))
                : Color.White;

            UpdateIcon(label, color);

            var tooltip = $"DexBar  {label} {reading.Trend.Arrow()}";
            if (settings.ShowDelta && _monitor.GlucoseDelta is int delta)
            {
                var sign = delta >= 0 ? "+" : "";
                tooltip += settings.Unit == GlucoseUnit.MmolL
                    ? $"  ({sign}{delta / 18.0:F1})"
                    : $"  ({sign}{delta})";
            }
            _notifyIcon.Text = tooltip.Length > 63 ? tooltip[..63] : tooltip;
        }
        else
        {
            UpdateIcon("--", Color.Gray);
            _notifyIcon.Text = $"DexBar – {_monitor.State.StatusText}";
        }

        // Popup refreshes itself via its own _monitor.OnUpdate subscription
    }

    private void HandleAlert(string title, string message)
    {
        _pendingUpdateUrl = null;
        _notifyIcon.BalloonTipTitle = title;
        _notifyIcon.BalloonTipText  = message;
        _notifyIcon.BalloonTipIcon  = ToolTipIcon.Warning;
        _notifyIcon.ShowBalloonTip(5000);
    }

    private void OnUpdateAvailable(string newVersion, string downloadUrl)
    {
        _pendingUpdateUrl = downloadUrl;
        _notifyIcon.BalloonTipTitle = "DexBar Update Available";
        _notifyIcon.BalloonTipText  = $"Version {newVersion} is available. Click to install.";
        _notifyIcon.BalloonTipIcon  = ToolTipIcon.Info;
        _notifyIcon.ShowBalloonTip(10000);
    }

    private async void NotifyIcon_BalloonTipClicked(object? sender, EventArgs e)
    {
        if (_pendingUpdateUrl is not null)
        {
            var url = _pendingUpdateUrl;
            _pendingUpdateUrl = null;
            await UpdateChecker.DownloadAndLaunchInstallerAsync(url);
        }
    }

    // -------------------------------------------------------------------------
    // Tray icon click
    // -------------------------------------------------------------------------

    private void NotifyIcon_MouseClick(object? sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
            TogglePopup();
    }

    private void TogglePopup()
    {
        if (_popup is { IsVisible: true })
        {
            _popup.Hide();
            return;
        }

        if (_popup is null || !_popup.IsLoaded)
        {
            _popup = new PopupWindow(_monitor);
            _popup.OpenSettingsRequested += OpenSettings;
        }

        PositionPopup();
        _popup.SuppressDeactivateOnce();
        _popup.Show();
        _popup.Activate();
    }

    private void PositionPopup()
    {
        if (_popup is null) return;

        // WPF Window.Left/Top use device-independent pixels (DIPs).
        // WorkArea from WinForms Screen is in physical pixels; divide by DPI scale.
        var screen   = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position);
        var workArea = screen.WorkingArea;

        // Approximate DPI scale from primary screen DPI
        double dpi   = screen.Bounds.Width > 0
            ? System.Windows.SystemParameters.PrimaryScreenWidth / screen.Bounds.Width
            : 1.0;
        if (dpi <= 0) dpi = 1.0;

        double workLeft   = workArea.Left   / dpi;
        double workRight  = workArea.Right  / dpi;
        double workBottom = workArea.Bottom / dpi;

        double cursorX = System.Windows.Forms.Cursor.Position.X / dpi;

        double x = Math.Clamp(cursorX - _popup.Width / 2, workLeft, workRight - _popup.Width);
        double y = workBottom - _popup.Height - 4;

        _popup.Left = x;
        _popup.Top  = y;
    }

    // -------------------------------------------------------------------------
    // Settings window
    // -------------------------------------------------------------------------

    private void OpenSettings()
    {
        if (_settingsWindow is { IsVisible: true })
        {
            _settingsWindow.Activate();
            return;
        }

        _settingsWindow = new SettingsWindow(_monitor);
        _settingsWindow.Show();
    }

    // -------------------------------------------------------------------------
    // Icon rendering (GDI+ — same logic as original TrayApplicationContext)
    // -------------------------------------------------------------------------

    private void UpdateIcon(string text, Color color)
    {
        const int size = 128;
        using var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode     = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.Clear(Color.Transparent);

            // Rounded background
            const int radius = 16;
            var bgRect = new Rectangle(0, 0, size, size);
            using var bgBrush = new SolidBrush(Color.FromArgb(240, 24, 24, 26));
            using var path = new System.Drawing.Drawing2D.GraphicsPath();
            path.AddArc(bgRect.X, bgRect.Y, radius * 2, radius * 2, 180, 90);
            path.AddArc(bgRect.Right - radius * 2, bgRect.Y, radius * 2, radius * 2, 270, 90);
            path.AddArc(bgRect.Right - radius * 2, bgRect.Bottom - radius * 2, radius * 2, radius * 2, 0, 90);
            path.AddArc(bgRect.X, bgRect.Bottom - radius * 2, radius * 2, radius * 2, 90, 90);
            path.CloseFigure();
            g.FillPath(bgBrush, path);

            // Auto-fit: start large and shrink until text fits
            float fontSize = 90f;
            Font font;
            SizeF measured;
            do
            {
                font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel);
                measured = g.MeasureString(text, font);
                if (measured.Width <= size - 4 && measured.Height <= size - 4)
                    break;
                font.Dispose();
                fontSize -= 4f;
            } while (fontSize > 16f);

            using (font)
            {
                // Center manually using measured size for pixel-perfect placement
                float x = (size - measured.Width) / 2f;
                float y = (size - measured.Height) / 2f;
                using var brush = new SolidBrush(color);
                g.DrawString(text, font, brush, x, y);
            }
        }

        var hIcon  = bmp.GetHicon();
        var newIcon = (Icon)Icon.FromHandle(hIcon).Clone();
        DestroyIcon(hIcon);

        var old = _currentIcon;
        _currentIcon         = newIcon;
        _notifyIcon.Icon     = newIcon;
        old?.Dispose();
    }

    private static Icon? LoadAppIcon()
    {
        var hIcon = LoadIcon(GetModuleHandle(null), (IntPtr)32512);
        if (hIcon == IntPtr.Zero) return null;
        var icon = (Icon)Icon.FromHandle(hIcon).Clone();
        DestroyIcon(hIcon);
        return icon;
    }

    private static Color ParseGdiColor(string hex)
    {
        try { return ColorTranslator.FromHtml(hex); }
        catch { return Color.White; }
    }

    // -------------------------------------------------------------------------
    // IDisposable
    // -------------------------------------------------------------------------

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _updateChecker.Dispose();
        _monitor.Dispose();
        _currentIcon?.Dispose();

        GC.SuppressFinalize(this);
    }
}
