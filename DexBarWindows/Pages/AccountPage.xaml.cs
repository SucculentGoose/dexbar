using System.Windows;
using System.Windows.Controls;
using DexBarWindows.Managers;
using DexBarWindows.Models;
using DexBarWindows.Services;
using Wpf.Ui.Controls;

namespace DexBarWindows.Pages;

public partial class AccountPage : System.Windows.Controls.Page
{
    private readonly GlucoseMonitor _monitor;

    public AccountPage(GlucoseMonitor monitor)
    {
        _monitor = monitor;
        InitializeComponent();
        LoadInitialValues();
    }

    private void LoadInitialValues()
    {
        // Populate region combo
        foreach (var region in Enum.GetValues<DexcomRegion>())
            CmbRegion.Items.Add(region);
        CmbRegion.SelectedItem = _monitor.Settings.Region;

        // Pre-fill stored username
        TxtUsername.Text = _monitor.Settings.DexcomUsername ?? string.Empty;

        // Try to load stored password
        try
        {
            var storedPassword = CredentialStorage.LoadPassword();
            if (storedPassword is not null)
                TxtPassword.Password = storedPassword;
        }
        catch
        {
            // No stored credential — leave blank
        }
    }

    private async void BtnConnect_Click(object sender, RoutedEventArgs e)
    {
        BtnConnect.IsEnabled = false;
        BtnConnect.Content = "Connecting…";
        StatusBar.IsOpen = false;

        var username = TxtUsername.Text.Trim();
        var password = TxtPassword.Password;
        var region = CmbRegion.SelectedItem is DexcomRegion r ? r : DexcomRegion.US;

        if (string.IsNullOrWhiteSpace(username))
        {
            ShowStatus(InfoBarSeverity.Error, "Username is required.", string.Empty);
            BtnConnect.IsEnabled = true;
            BtnConnect.Content = "Connect";
            return;
        }

        // Save password to credential store
        try
        {
            CredentialStorage.SavePassword(password);
        }
        catch (Exception ex)
        {
            ShowStatus(InfoBarSeverity.Error, "Credential error", ex.Message);
            BtnConnect.IsEnabled = true;
            BtnConnect.Content = "Connect";
            return;
        }

        try
        {
            await _monitor.StartAsync(username, password, region);
            _monitor.Settings.Save();
            ShowStatus(InfoBarSeverity.Success, "Connected", "Authenticated — fetching readings…");
        }
        catch (Exception ex)
        {
            ShowStatus(InfoBarSeverity.Error, "Connection failed", ex.Message);
        }

        BtnConnect.IsEnabled = true;
        BtnConnect.Content = "Connect";
    }

    private void ShowStatus(InfoBarSeverity severity, string title, string message)
    {
        StatusBar.Severity = severity;
        StatusBar.Title = title;
        StatusBar.Message = message;
        StatusBar.IsOpen = true;
    }
}
