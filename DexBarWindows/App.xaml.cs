using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using Microsoft.Win32;
using Wpf.Ui.Appearance;
using WinFormsApp = System.Windows.Forms.Application;
using Application = System.Windows.Application;

namespace DexBarWindows;

public partial class App : Application
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    private TrayManager? _trayManager;

    protected override void OnStartup(StartupEventArgs e)
    {
        // Install global exception handlers first, before anything else,
        // so any startup failure is logged and shown instead of silently crashing.
        DispatcherUnhandledException += (_, ex) =>
        {
            ShowFatalError(ex.Exception);
            ex.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (_, ex) =>
            ShowFatalError(ex.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, ex) =>
        {
            ShowFatalError(ex.Exception);
            ex.SetObserved();
        };

        try
        {
            base.OnStartup(e);

            // Initialise WinForms subsystem (required for NotifyIcon / ContextMenuStrip)
            WinFormsApp.SetHighDpiMode(System.Windows.Forms.HighDpiMode.PerMonitorV2);
            WinFormsApp.EnableVisualStyles();
            WinFormsApp.SetCompatibleTextRenderingDefault(false);

            // Apply current Windows theme (dark or light)
            ApplicationThemeManager.ApplySystemTheme();

            // Listen for OS theme changes
            SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;

            _trayManager = new TrayManager();
        }
        catch (Exception ex)
        {
            ShowFatalError(ex);
        }
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (e.Category == UserPreferenceCategory.General)
            Dispatcher.Invoke(ApplicationThemeManager.ApplySystemTheme);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
        _trayManager?.Dispose();
        base.OnExit(e);
    }

    private static void ShowFatalError(Exception? ex)
    {
        var msg = ex?.ToString() ?? "Unknown error";
        var log = Path.Combine(AppContext.BaseDirectory, "dexbar-crash.log");
        try { File.WriteAllText(log, $"{DateTime.Now}\n{msg}\n"); } catch { }
        // Use native Win32 MessageBox — works even if WPF is in a bad state
        MessageBoxW(IntPtr.Zero, msg, "DexBar – Fatal Error", 0x10 /* MB_ICONERROR */);
    }
}
