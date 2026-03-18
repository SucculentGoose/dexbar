using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;

namespace DexBarWindows;

public static class Program
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    private static void ShowError(string msg)
    {
        var log = Path.Combine(AppContext.BaseDirectory, "dexbar-crash.log");
        try { File.WriteAllText(log, $"{DateTime.Now}\n{msg}\n"); } catch { }
        MessageBoxW(IntPtr.Zero, msg, "DexBar – Fatal Error", 0x10);
    }

    [STAThread]
    public static void Main(string[] args)
    {
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            ShowError("AppDomain.UnhandledException:\n" + e.ExceptionObject);
            Environment.Exit(1);
        };

        try
        {
            var app = new App();
            app.InitializeComponent();
            app.Run();
        }
        catch (Exception ex)
        {
            ShowError(ex.ToString());
        }
    }
}
