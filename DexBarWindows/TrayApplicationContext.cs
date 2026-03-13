using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using DexBarWindows.Forms;
using DexBarWindows.Managers;
using DexBarWindows.Models;
using DexBarWindows.Services;

namespace DexBarWindows;

public class TrayApplicationContext : ApplicationContext
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    private readonly GlucoseMonitor  _monitor;
    private readonly NotifyIcon      _notifyIcon;
    private readonly ToolStripMenuItem _refreshItem;

    private PopupForm?    _popup;
    private SettingsForm? _settingsForm;
    private Icon?         _currentIcon;

    public TrayApplicationContext()
    {
        _monitor = new GlucoseMonitor();
        _monitor.OnUpdate = HandleUpdate;
        _monitor.OnAlert  = HandleAlert;

        _refreshItem = new ToolStripMenuItem("Refresh Now");
        _refreshItem.Click += async (_, _) => await _monitor.RefreshNowAsync();

        var settingsItem = new ToolStripMenuItem("Settings…");
        settingsItem.Click += (_, _) => OpenSettings();

        var quitItem = new ToolStripMenuItem("Quit");
        quitItem.Click += (_, _) => Application.Exit();

        var contextMenu = new ContextMenuStrip();
        contextMenu.Items.Add(_refreshItem);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add(settingsItem);
        contextMenu.Items.Add(new ToolStripSeparator());
        contextMenu.Items.Add(quitItem);

        _notifyIcon = new NotifyIcon
        {
            Icon             = SystemIcons.Application,
            Text             = "DexBar",
            ContextMenuStrip = contextMenu,
            Visible          = true
        };
        _notifyIcon.MouseClick += NotifyIcon_MouseClick;

        // Auto-start if credentials are already stored
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
    // Monitor callbacks (already on UI thread)
    // -------------------------------------------------------------------------

    private void HandleUpdate()
    {
        var reading  = _monitor.CurrentReading;
        var settings = _monitor.Settings;

        if (reading is not null)
        {
            var label = reading.DisplayValue(settings.Unit);
            var color = settings.ColoredTrayIcon
                ? ParseHex(settings.GlucoseColor(reading.Value))
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

        // Refresh popup if it is open
        _popup?.Invalidate();
    }

    private void HandleAlert(string title, string message)
    {
        _notifyIcon.BalloonTipTitle = title;
        _notifyIcon.BalloonTipText  = message;
        _notifyIcon.BalloonTipIcon  = ToolTipIcon.Warning;
        _notifyIcon.ShowBalloonTip(5000);
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
        if (_popup is { Visible: true })
        {
            _popup.Hide();
            return;
        }

        if (_popup is null || _popup.IsDisposed)
        {
            _popup = new PopupForm(_monitor);
            _popup.OpenSettingsRequested += OpenSettings;
        }

        PositionPopup();
        _popup.Show();
        _popup.Activate();
    }

    private void PositionPopup()
    {
        if (_popup is null) return;

        var screen   = Screen.FromPoint(Cursor.Position);
        var workArea = screen.WorkingArea;
        int x = Math.Clamp(Cursor.Position.X - _popup.Width / 2, workArea.Left, workArea.Right - _popup.Width);
        int y = workArea.Bottom - _popup.Height - 4;
        _popup.Location = new Point(x, y);
    }

    // -------------------------------------------------------------------------
    // Settings form
    // -------------------------------------------------------------------------

    private void OpenSettings()
    {
        if (_settingsForm is { Visible: true })
        {
            _settingsForm.Activate();
            return;
        }

        _settingsForm = new SettingsForm(_monitor);
        _settingsForm.Show();
    }

    // -------------------------------------------------------------------------
    // Icon rendering
    // -------------------------------------------------------------------------

    private void UpdateIcon(string text, Color color)
    {
        const int size = 32;
        using var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.Transparent);
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

            float fontSize = text.Length <= 3 ? 13f : 10f;
            using var font  = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel);
            using var brush = new SolidBrush(color);
            var sf = new StringFormat
            {
                Alignment     = StringAlignment.Center,
                LineAlignment = StringAlignment.Center
            };
            g.DrawString(text, font, brush, new RectangleF(0, 0, size, size), sf);
        }

        var hIcon  = bmp.GetHicon();
        var newIcon = (Icon)Icon.FromHandle(hIcon).Clone();
        DestroyIcon(hIcon);

        var old = _currentIcon;
        _currentIcon          = newIcon;
        _notifyIcon.Icon      = newIcon;
        old?.Dispose();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private static Color ParseHex(string hex)
    {
        try { return ColorTranslator.FromHtml(hex); }
        catch { return Color.White; }
    }

    // -------------------------------------------------------------------------
    // Disposal
    // -------------------------------------------------------------------------

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _monitor.Dispose();
            _popup?.Dispose();
            _settingsForm?.Dispose();
            _currentIcon?.Dispose();
        }
        base.Dispose(disposing);
    }
}
