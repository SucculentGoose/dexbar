using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using DexBarWindows.Controls;
using DexBarWindows.Managers;
using DexBarWindows.Models;
using Color = System.Windows.Media.Color;
using Colors = System.Windows.Media.Colors;
using Button = System.Windows.Controls.Button;
using Application = System.Windows.Application;
using FontFamily = System.Windows.Media.FontFamily;
using Cursors = System.Windows.Input.Cursors;

namespace DexBarWindows.Windows;

public partial class PopupWindow : Window
{
    public event Action? OpenSettingsRequested;

    private readonly GlucoseMonitor _monitor;
    private readonly DispatcherTimer _tickTimer;

    // Keeps a reference to the chart so we can read/set SelectedRange
    private GlucoseChartControl? _chart;

    // Tracks the selected range button panels so we can update highlight state
    private UniformGrid? _chartRangeFlow;
    private UniformGrid? _statsRangeFlow;

    // Guards against OnDeactivated firing before the window has truly gained focus
    // (common when opening from a tray-icon click)
    private bool _activationGuard;

    // ── Colors ────────────────────────────────────────────────────────────────
    private static readonly SolidColorBrush TextPrimary   = new(Color.FromRgb(240, 240, 242));
    private static readonly SolidColorBrush TextSecondary = new(Color.FromRgb(160, 160, 168));
    private static readonly SolidColorBrush TextTertiary  = new(Color.FromRgb(100, 100, 108));
    private static readonly Color SegmentActive   = Color.FromRgb(70,  70,  80);
    private static readonly Color SegmentInactive = Color.FromRgb(44,  44,  46);
    private static readonly Color SegmentFg       = Color.FromRgb(210, 210, 215);

    // ── Constructor ───────────────────────────────────────────────────────────

    public PopupWindow(GlucoseMonitor monitor)
    {
        _monitor = monitor;
        InitializeComponent();

        // Wire up action labels (MouseLeftButtonDown + Handled to prevent DragMove)
        RefreshButton.MouseLeftButtonDown  += async (_, e) => { e.Handled = true; await _monitor.RefreshNowAsync(); };
        SettingsButton.MouseLeftButtonDown += (_, e) => { e.Handled = true; Hide(); OpenSettingsRequested?.Invoke(); };
        QuitButton.MouseLeftButtonDown     += (_, e) => { e.Handled = true; Application.Current.Shutdown(); };

        // Build the chart and inject it into the Grid host
        _chart = new GlucoseChartControl(_monitor);
        ChartHost.Children.Add(_chart);

        // Build range button rows
        _chartRangeFlow = ChartRangeFlow;
        _statsRangeFlow = StatsRangeFlow;
        BuildChartRangeButtons();
        BuildStatsRangeButtons();

        // 1-second tick for countdown / "X ago" labels
        _tickTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _tickTimer.Tick += (_, _) => UpdateTimerLabels();
        _tickTimer.Start();

        // Subscribe to monitor updates and do an initial render
        _monitor.OnUpdate += UpdateDisplay;
        UpdateDisplay();
    }

    /// <summary>
    /// Prevents the next OnDeactivated from hiding the window.
    /// Call this right before Show() when opening from a tray-icon click.
    /// </summary>
    public void SuppressDeactivateOnce() => _activationGuard = true;

    // ── Drag ──────────────────────────────────────────────────────────────────

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            try { DragMove(); }
            catch (InvalidOperationException) { /* mouse was released before DragMove entered loop */ }
        }
    }

    // ── Auto-hide on deactivation ─────────────────────────────────────────────

    protected override void OnActivated(EventArgs e)
    {
        base.OnActivated(e);
        _activationGuard = false;
    }

    protected override void OnDeactivated(EventArgs e)
    {
        base.OnDeactivated(e);
        if (!_activationGuard)
            Hide();
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    protected override void OnClosed(EventArgs e)
    {
        _tickTimer.Stop();
        _monitor.OnUpdate -= UpdateDisplay;
        base.OnClosed(e);
    }

    // ── UpdateDisplay ─────────────────────────────────────────────────────────

    private void UpdateDisplay()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.Invoke(UpdateDisplay);
            return;
        }

        var settings = _monitor.Settings;
        var reading  = _monitor.CurrentReading;
        var state    = _monitor.State;

        // Stale banner
        bool isStale = _monitor.IsStale && state is MonitorState.Connected;
        StalePanel.Visibility = isStale ? Visibility.Visible : Visibility.Collapsed;

        // Glucose value + trend text
        if (reading is not null)
        {
            GlucoseValueLabel.Foreground = ParseBrush(settings.GlucoseColor(reading.Value));
            GlucoseValueLabel.Text = $"{reading.DisplayValue(settings.Unit)} {reading.Trend.Arrow()}";

            var parts = new List<string>
            {
                reading.Trend.Description(),
                settings.Unit == GlucoseUnit.MmolL ? "mmol/L" : "mg/dL"
            };
            if (settings.ShowDelta && _monitor.GlucoseDelta is int delta)
            {
                string sign = delta >= 0 ? "+" : "";
                string deltaStr = settings.Unit == GlucoseUnit.MmolL
                    ? $"{sign}{delta / 18.0:F1}"
                    : $"{sign}{delta}";
                parts.Insert(1, deltaStr);
            }
            TrendLabel.Text = string.Join(" · ", parts);
        }
        else
        {
            GlucoseValueLabel.Foreground = TextSecondary;
            GlucoseValueLabel.Text = state is MonitorState.Loading ? "…" : "--";
            TrendLabel.Text = state.StatusText;
        }

        // Status chip
        (StatusLabel.Text, StatusLabel.Foreground) = state switch
        {
            MonitorState.Connected => ("● Live",         new SolidColorBrush(Color.FromRgb(52,  199, 89))),
            MonitorState.Loading   => ("↻ Updating",     new SolidColorBrush(Color.FromRgb(10,  132, 255))),
            MonitorState.Error     => ("⚠ Error",        new SolidColorBrush(Color.FromRgb(255, 69,  58))),
            _                      => ("○ Disconnected", TextSecondary)
        };

        UpdateTimerLabels();
        UpdateTiR(settings);

        // Trigger chart redraw
        _chart?.InvalidateVisual();
    }

    // ── UpdateTimerLabels ─────────────────────────────────────────────────────

    private void UpdateTimerLabels()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.Invoke(UpdateTimerLabels);
            return;
        }

        // "X ago" label
        if (_monitor.LastUpdated is DateTime updated)
        {
            var ago = DateTime.UtcNow - updated;
            UpdatedLabel.Text = ago.TotalSeconds < 60
                ? "Just now"
                : $"{(int)ago.TotalMinutes}m ago";
        }
        else
        {
            UpdatedLabel.Text = "";
        }

        // "Next: Xm Xs" countdown
        if (_monitor.NextRefreshDate is DateTime next)
        {
            var remaining = next - DateTime.UtcNow;
            if (remaining <= TimeSpan.Zero)
                CountdownLabel.Text = "Next: now";
            else if (remaining.TotalMinutes >= 1)
                CountdownLabel.Text = $"Next: {(int)remaining.TotalMinutes}m {remaining.Seconds}s";
            else
                CountdownLabel.Text = $"Next: {remaining.Seconds}s";
        }
        else
        {
            CountdownLabel.Text = "";
        }
    }

    // ── UpdateTiR ─────────────────────────────────────────────────────────────

    private void UpdateTiR(AppSettings settings)
    {
        var stats   = _monitor.TirStats;
        var lowColor = ParseMediaColor(settings.ColorLow);
        var inColor  = ParseMediaColor(settings.ColorInRange);
        var hiColor  = ParseMediaColor(settings.ColorHigh);

        TirHeaderLabel.Text = stats.Total > 0
            ? $"Time in Range  {stats.InRangePct:F0}%"
            : "Time in Range";

        TirBar.LowPct      = stats.LowPct;
        TirBar.InRangePct  = stats.InRangePct;
        TirBar.HighPct     = stats.HighPct;
        TirBar.LowColor    = lowColor;
        TirBar.InRangeColor = inColor;
        TirBar.HighColor   = hiColor;

        LowPctLabel.Foreground    = new SolidColorBrush(lowColor);
        InRangePctLabel.Foreground = new SolidColorBrush(inColor);
        HighPctLabel.Foreground   = new SolidColorBrush(hiColor);

        if (stats.Total > 0)
        {
            LowPctLabel.Text     = $"↓ {stats.LowPct:F0}%";
            InRangePctLabel.Text = $"✓ {stats.InRangePct:F0}%";
            HighPctLabel.Text    = $"↑ {stats.HighPct:F0}%";
        }
        else
        {
            LowPctLabel.Text = InRangePctLabel.Text = HighPctLabel.Text = "--";
        }

        if (_monitor.Gmi is double gmi && stats.Total > 0)
        {
            var span = _monitor.StatsDataSpanDays;
            GmiLabel.Foreground = span < 14 ? TextTertiary : TextSecondary;
            GmiLabel.Text = span < 14
                ? $"GMI {gmi:F1}%  (based on {span:F1}d — 14d+ recommended)"
                : $"GMI {gmi:F1}%  ·  {stats.Total} readings";
        }
        else
        {
            GmiLabel.Text = "";
        }
    }

    // ── Range button builders ─────────────────────────────────────────────────

    private void BuildChartRangeButtons()
    {
        if (_chartRangeFlow is null || _chart is null) return;

        var ranges = new[]
        {
            (TimeRange.ThreeHours,  "3h"),
            (TimeRange.SixHours,    "6h"),
            (TimeRange.TwelveHours, "12h"),
            (TimeRange.Day,         "24h")
        };

        foreach (var (range, label) in ranges)
        {
            var seg = MakeSegmentButton(label, range == _chart.SelectedRange);
            seg.Tag = range;
            seg.MouseLeftButtonDown += (_, e) =>
            {
                if (_chart is not null)
                    _chart.SelectedRange = range;
                RefreshButtonHighlights(_chartRangeFlow, range);
                e.Handled = true;
            };
            _chartRangeFlow.Children.Add(seg);
        }
    }

    private void BuildStatsRangeButtons()
    {
        if (_statsRangeFlow is null) return;

        var ranges = new[]
        {
            (StatsTimeRange.TwoDays,      "2d"),
            (StatsTimeRange.SevenDays,    "7d"),
            (StatsTimeRange.FourteenDays, "14d"),
            (StatsTimeRange.ThirtyDays,   "30d"),
            (StatsTimeRange.NinetyDays,   "90d")
        };

        foreach (var (range, label) in ranges)
        {
            var seg = MakeSegmentButton(label, range == _monitor.Settings.StatsTimeRange);
            seg.Tag = range;
            seg.MouseLeftButtonDown += (_, e) =>
            {
                _monitor.Settings.StatsTimeRange = range;
                _monitor.Settings.Save();
                RefreshButtonHighlights(_statsRangeFlow, range);
                UpdateTiR(_monitor.Settings);
                e.Handled = true;
            };
            _statsRangeFlow.Children.Add(seg);
        }
    }

    private static void RefreshButtonHighlights(System.Windows.Controls.Panel panel, object selected)
    {
        foreach (var child in panel.Children)
        {
            if (child is Border btn)
                btn.Background = Equals(btn.Tag, selected)
                    ? new SolidColorBrush(SegmentActive)
                    : new SolidColorBrush(SegmentInactive);
        }
    }

    // ── Segment button factory ────────────────────────────────────────────────

    private static Border MakeSegmentButton(string text, bool active)
    {
        var border = new Border
        {
            Background  = new SolidColorBrush(active ? SegmentActive : SegmentInactive),
            CornerRadius = new CornerRadius(4),
            Margin      = new Thickness(0, 0, 3, 0),
            Cursor      = Cursors.Hand
        };
        var tb = new TextBlock
        {
            Text            = text,
            FontFamily      = new FontFamily("Segoe UI"),
            FontSize        = 10,
            Foreground      = new SolidColorBrush(SegmentFg),
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
            VerticalAlignment   = System.Windows.VerticalAlignment.Center,
            Padding         = new Thickness(0, 2, 0, 2)
        };
        border.Child = tb;
        return border;
    }

    // ── Color helpers ─────────────────────────────────────────────────────────

    private static System.Windows.Media.Color ParseMediaColor(string hex)
    {
        try { return (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(hex); }
        catch { return System.Windows.Media.Colors.Gray; }
    }

    private static SolidColorBrush ParseBrush(string hex) => new(ParseMediaColor(hex));
}
