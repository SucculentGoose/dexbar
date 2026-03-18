using System.Diagnostics;
using System.Reflection;
using System.Windows;

namespace DexBarWindows.Pages;

public partial class AboutPage : System.Windows.Controls.Page
{
    public AboutPage()
    {
        InitializeComponent();

        var version = Assembly.GetExecutingAssembly()
            .GetName().Version?.ToString(3) ?? "—";

        LblVersion.Text = $"Version {version}";
    }

    private void BtnGitHub_Click(object sender, RoutedEventArgs e)
    {
        Process.Start(new ProcessStartInfo("https://github.com/SucculentGoose/dexbar")
        {
            UseShellExecute = true
        });
    }
}
