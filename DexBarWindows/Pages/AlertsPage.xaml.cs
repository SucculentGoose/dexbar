using System.Windows;
using System.Windows.Controls;
using DexBarWindows.Managers;

namespace DexBarWindows.Pages;

public partial class AlertsPage : System.Windows.Controls.Page
{
    private readonly GlucoseMonitor _monitor;
    private bool _loading = true;

    public AlertsPage(GlucoseMonitor monitor)
    {
        _monitor = monitor;
        InitializeComponent();
        LoadInitialValues();
        _loading = false;
    }

    private void LoadInitialValues()
    {
        var s = _monitor.Settings;

        // Urgent High
        SldrUrgentHigh.Value    = Math.Clamp(s.AlertUrgentHighThresholdMgdL, 181, 400);
        TglUrgentHigh.IsChecked = s.AlertUrgentHighEnabled;
        UpdateLabel(LblUrgentHigh, SldrUrgentHigh.Value);

        // High
        SldrHigh.Value    = Math.Clamp(s.AlertHighThresholdMgdL, 120, 399);
        TglHigh.IsChecked = s.AlertHighEnabled;
        UpdateLabel(LblHigh, SldrHigh.Value);

        // Low
        SldrLow.Value    = Math.Clamp(s.AlertLowThresholdMgdL, 56, 180);
        TglLow.IsChecked = s.AlertLowEnabled;
        UpdateLabel(LblLow, SldrLow.Value);

        // Urgent Low
        SldrUrgentLow.Value    = Math.Clamp(s.AlertUrgentLowThresholdMgdL, 40, 109);
        TglUrgentLow.IsChecked = s.AlertUrgentLowEnabled;
        UpdateLabel(LblUrgentLow, SldrUrgentLow.Value);

        // Trend
        TglRisingFast.IsChecked   = s.AlertRisingFastEnabled;
        TglDroppingFast.IsChecked = s.AlertDroppingFastEnabled;

        // Stale data
        TglStaleData.IsChecked = s.AlertStaleDataEnabled;
    }

    private static void UpdateLabel(System.Windows.Controls.TextBlock? label, double value)
    {
        if (label is null) return;
        label.Text = $"{(int)value} mg/dL";
    }

    // -------------------------------------------------------------------------
    // Slider handlers
    // -------------------------------------------------------------------------

    private void SldrUrgentHigh_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!IsLoaded) return;
        UpdateLabel(LblUrgentHigh, e.NewValue);
        if (_loading) return;
        _monitor.Settings.AlertUrgentHighThresholdMgdL = (int)e.NewValue;
        _monitor.Settings.Save();
    }

    private void SldrHigh_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!IsLoaded) return;
        UpdateLabel(LblHigh, e.NewValue);
        if (_loading) return;
        _monitor.Settings.AlertHighThresholdMgdL = (int)e.NewValue;
        _monitor.Settings.Save();
    }

    private void SldrLow_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!IsLoaded) return;
        UpdateLabel(LblLow, e.NewValue);
        if (_loading) return;
        _monitor.Settings.AlertLowThresholdMgdL = (int)e.NewValue;
        _monitor.Settings.Save();
    }

    private void SldrUrgentLow_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!IsLoaded) return;
        UpdateLabel(LblUrgentLow, e.NewValue);
        if (_loading) return;
        _monitor.Settings.AlertUrgentLowThresholdMgdL = (int)e.NewValue;
        _monitor.Settings.Save();
    }

    // -------------------------------------------------------------------------
    // Toggle handlers
    // -------------------------------------------------------------------------

    private void TglUrgentHigh_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.AlertUrgentHighEnabled = TglUrgentHigh.IsChecked == true;
        _monitor.Settings.Save();
    }

    private void TglHigh_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.AlertHighEnabled = TglHigh.IsChecked == true;
        _monitor.Settings.Save();
    }

    private void TglLow_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.AlertLowEnabled = TglLow.IsChecked == true;
        _monitor.Settings.Save();
    }

    private void TglUrgentLow_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.AlertUrgentLowEnabled = TglUrgentLow.IsChecked == true;
        _monitor.Settings.Save();
    }

    private void TglRisingFast_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.AlertRisingFastEnabled = TglRisingFast.IsChecked == true;
        _monitor.Settings.Save();
    }

    private void TglDroppingFast_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.AlertDroppingFastEnabled = TglDroppingFast.IsChecked == true;
        _monitor.Settings.Save();
    }

    private void TglStaleData_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _monitor.Settings.AlertStaleDataEnabled = TglStaleData.IsChecked == true;
        _monitor.Settings.Save();
    }
}
