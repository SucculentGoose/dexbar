using System.Windows;
using Microsoft.Win32;
using Wpf.Ui.Appearance;
using Application = System.Windows.Application;
using MessageBox = System.Windows.MessageBox;
using MessageBoxButton = System.Windows.MessageBoxButton;
using MessageBoxImage = System.Windows.MessageBoxImage;

namespace DexBarWindows;

public partial class App : Application
{
    private TrayManager? _trayManager;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Apply current Windows theme (dark or light)
        ApplicationThemeManager.ApplySystemTheme();

        // Listen for OS theme changes
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;

        // Install a global exception handler so crashes are logged and shown
        DispatcherUnhandledException += (_, ex) =>
        {
            ShowFatalError(ex.Exception);
            ex.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (_, ex) =>
            ShowFatalError(ex.ExceptionObject as Exception);

        _trayManager = new TrayManager();
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
        var log = System.IO.Path.Combine(AppContext.BaseDirectory, "dexbar-crash.log");
        try { System.IO.File.WriteAllText(log, $"{DateTime.Now}\n{msg}\n"); } catch { }
        MessageBox.Show(msg, "DexBar – Fatal Error", MessageBoxButton.OK, MessageBoxImage.Error);
    }
}
