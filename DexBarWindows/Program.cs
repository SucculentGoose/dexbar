using DexBarWindows;

Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
Application.EnableVisualStyles();
Application.SetCompatibleTextRenderingDefault(false);
Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);

// Install the WinForms sync context now so GlucoseMonitor can capture it
// in its constructor, which runs before Application.Run() does it internally.
SynchronizationContext.SetSynchronizationContext(new WindowsFormsSynchronizationContext());

// Show a message box for any unhandled UI-thread exception instead of silently dying.
Application.ThreadException += (_, e) => ShowFatalError(e.Exception);

// Catch exceptions on background threads too.
AppDomain.CurrentDomain.UnhandledException += (_, e) =>
    ShowFatalError(e.ExceptionObject as Exception);

Application.Run(new TrayApplicationContext());

static void ShowFatalError(Exception? ex)
{
    var msg = ex?.ToString() ?? "Unknown error";
    // Write to a log file next to the exe so it's readable even without a console.
    var log = Path.Combine(
        AppContext.BaseDirectory,
        "dexbar-crash.log");
    try { File.WriteAllText(log, $"{DateTime.Now}\n{msg}\n"); } catch { }
    MessageBox.Show(msg, "DexBar – Fatal Error",
        MessageBoxButtons.OK, MessageBoxIcon.Error);
}
