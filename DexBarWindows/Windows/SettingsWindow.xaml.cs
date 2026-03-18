using System.Windows;
using System.Windows.Controls;
using DexBarWindows.Managers;
using DexBarWindows.Pages;

namespace DexBarWindows.Windows;

public partial class SettingsWindow : Window
{
    private readonly GlucoseMonitor _monitor;
    private readonly Dictionary<string, System.Windows.Controls.Page> _pages;

    public SettingsWindow(GlucoseMonitor monitor)
    {
        _monitor = monitor;
        _pages = new Dictionary<string, System.Windows.Controls.Page>
        {
            ["Account"]    = new AccountPage(monitor),
            ["Display"]    = new DisplayPage(monitor),
            ["Alerts"]     = new AlertsPage(monitor),
            ["About"]      = new AboutPage(),
            ["Disclaimer"] = new DisclaimerPage()
        };

        InitializeComponent();

        // Select Account by default
        NavList.SelectedIndex = 0;
    }

    private void NavList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (NavList.SelectedItem is ListBoxItem item && item.Tag is string key)
        {
            if (_pages.TryGetValue(key, out var page))
                ContentFrame.Navigate(page);
        }
    }
}
