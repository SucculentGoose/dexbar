using System.Windows.Forms;

namespace DexBarWindows;

// TODO: Wire up GlucoseMonitor, TrayIcon, PopupForm, and SettingsForm in a later phase.
public class TrayApplicationContext : ApplicationContext
{
    private readonly NotifyIcon _notifyIcon;

    public TrayApplicationContext()
    {
        var quitItem = new ToolStripMenuItem("Quit");
        quitItem.Click += (_, _) => Application.Exit();

        var contextMenu = new ContextMenuStrip();
        contextMenu.Items.Add(quitItem);

        _notifyIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "DexBar - Loading...",
            ContextMenuStrip = contextMenu,
            Visible = true,
        };
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _notifyIcon.Dispose();
        }
        base.Dispose(disposing);
    }
}
