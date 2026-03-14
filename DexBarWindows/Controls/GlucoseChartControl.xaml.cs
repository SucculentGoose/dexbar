using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using DexBarWindows.Managers;
using DexBarWindows.Models;
using Color = System.Windows.Media.Color;
using Colors = System.Windows.Media.Colors;
using Brush = System.Windows.Media.Brush;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;
using Size = System.Windows.Size;
using FontFamily = System.Windows.Media.FontFamily;
using ColorConverter = System.Windows.Media.ColorConverter;
using UserControl = System.Windows.Controls.UserControl;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;

namespace DexBarWindows.Controls;

public partial class GlucoseChartControl : UserControl
{
    private readonly GlucoseMonitor _monitor;
    private TimeRange _selectedRange = TimeRange.ThreeHours;

    private const double PadLeft = 36;
    private const double PadRight = 6;
    private const double PadTop = 6;
    private const double PadBottom = 22;

    private static readonly Color BackgroundColor = Color.FromArgb(255, 24, 24, 26);
    private static readonly Color GridColor = Color.FromArgb(255, 50, 50, 55);
    private static readonly Color LabelColor = Color.FromArgb(255, 130, 130, 140);
    private static readonly Color TooltipBg = Color.FromArgb(220, 44, 44, 48);

    private GlucoseReading? _hoveredReading;
    private Point _hoveredPoint;

    public TimeRange SelectedRange
    {
        get => _selectedRange;
        set { _selectedRange = value; InvalidateVisual(); }
    }

    public GlucoseChartControl(GlucoseMonitor monitor)
    {
        InitializeComponent();
        _monitor = monitor;
        Background = new SolidColorBrush(BackgroundColor);
        MouseMove += OnChartMouseMove;
        MouseLeave += (_, _) => { _hoveredReading = null; InvalidateVisual(); };
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);

        var settings = _monitor.Settings;
        var unit = settings.Unit;
        var readings = GetReadings();

        var plotRect = new Rect(PadLeft, PadTop, ActualWidth - PadLeft - PadRight, ActualHeight - PadTop - PadBottom);

        if (readings.Count == 0)
        {
            DrawNoData(dc, plotRect);
            return;
        }

        double lowThresh  = Threshold(settings.AlertLowThresholdMgdL, unit);
        double highThresh = Threshold(settings.AlertHighThresholdMgdL, unit);
        var vals = readings.Select(r => DisplayVal(r, unit)).ToList();
        double yPad = unit == GlucoseUnit.MmolL ? 0.8 : 15;
        double minY = Math.Min(vals.Min(), lowThresh) - yPad;
        double maxY = Math.Max(vals.Max(), highThresh) + yPad;

        var now       = DateTime.UtcNow;
        var startTime = now - _selectedRange.Interval();
        double xSpan  = (now - startTime).TotalSeconds;

        double ToX(DateTime dt) => plotRect.Left + (dt - startTime).TotalSeconds / xSpan * plotRect.Width;
        double ToY(double v)    => plotRect.Bottom - (v - minY) / (maxY - minY) * plotRect.Height;

        DrawInRangeBand(dc, plotRect, ToY, highThresh, lowThresh, settings);
        DrawThresholdLines(dc, plotRect, ToY, highThresh, lowThresh, settings);
        DrawYAxis(dc, plotRect, minY, maxY, unit);
        DrawXAxis(dc, plotRect, startTime, now, ToX);
        if (readings.Count >= 2) DrawLine(dc, readings, unit, ToX, ToY);
        DrawPoints(dc, readings, unit, settings, ToX, ToY);
        if (_hoveredReading is not null) DrawTooltip(dc, _hoveredReading, _hoveredPoint, readings, unit, settings);
    }

    private void OnChartMouseMove(object sender, MouseEventArgs e)
    {
        var settings = _monitor.Settings;
        var unit = settings.Unit;
        var readings = GetReadings();
        var pos = e.GetPosition(this);

        if (readings.Count == 0)
        {
            if (_hoveredReading is not null) { _hoveredReading = null; InvalidateVisual(); }
            return;
        }

        var plotRect = new Rect(PadLeft, PadTop, ActualWidth - PadLeft - PadRight, ActualHeight - PadTop - PadBottom);
        if (!plotRect.Contains(pos))
        {
            if (_hoveredReading is not null) { _hoveredReading = null; InvalidateVisual(); }
            return;
        }

        double lowThresh  = Threshold(settings.AlertLowThresholdMgdL, unit);
        double highThresh = Threshold(settings.AlertHighThresholdMgdL, unit);
        var vals = readings.Select(r => DisplayVal(r, unit)).ToList();
        double yPad = unit == GlucoseUnit.MmolL ? 0.8 : 15;
        double minY = Math.Min(vals.Min(), lowThresh) - yPad;
        double maxY = Math.Max(vals.Max(), highThresh) + yPad;
        var now       = DateTime.UtcNow;
        var startTime = now - _selectedRange.Interval();
        double xSpan  = (now - startTime).TotalSeconds;

        double ToX(DateTime dt) => plotRect.Left + (dt - startTime).TotalSeconds / xSpan * plotRect.Width;
        double ToY(double v)    => plotRect.Bottom - (v - minY) / (maxY - minY) * plotRect.Height;

        GlucoseReading? nearest = null;
        double nearestDist = double.MaxValue;
        Point nearestPt = default;
        foreach (var r in readings)
        {
            double px = ToX(r.Date);
            double py = ToY(DisplayVal(r, unit));
            double dist = Math.Abs(pos.X - px);
            if (dist < nearestDist) { nearestDist = dist; nearest = r; nearestPt = new Point(px, py); }
        }

        if (nearest is not null && nearestDist <= 20)
        {
            if (_hoveredReading != nearest) { _hoveredReading = nearest; _hoveredPoint = nearestPt; InvalidateVisual(); }
        }
        else if (_hoveredReading is not null)
        {
            _hoveredReading = null;
            InvalidateVisual();
        }
    }

    private void DrawNoData(DrawingContext dc, Rect plotRect)
    {
        const string text = "No readings for this period";
        var ft = MakeFormattedText(text, 9.0, new SolidColorBrush(LabelColor));
        double x = plotRect.Left + (plotRect.Width - ft.Width) / 2;
        double y = plotRect.Top + (plotRect.Height - ft.Height) / 2;
        dc.DrawText(ft, new Point(x, y));
    }

    private static void DrawInRangeBand(DrawingContext dc, Rect plotRect, Func<double, double> toY, double highThresh, double lowThresh, AppSettings settings)
    {
        var inRangeColor = ParseColor(settings.ColorInRange);
        var brush = new SolidColorBrush(Color.FromArgb(28, inRangeColor.R, inRangeColor.G, inRangeColor.B));
        double y1 = toY(highThresh);
        double y2 = toY(lowThresh);
        dc.DrawRectangle(brush, null, new Rect(plotRect.Left, y1, plotRect.Width, y2 - y1));
    }

    private static void DrawThresholdLines(DrawingContext dc, Rect plotRect, Func<double, double> toY, double highThresh, double lowThresh, AppSettings settings)
    {
        if (settings.AlertLowEnabled)
        {
            var c = ParseColor(settings.ColorLow);
            var pen = new Pen(new SolidColorBrush(Color.FromArgb(120, c.R, c.G, c.B)), 1.0)
            {
                DashStyle = DashStyles.Dash
            };
            double y = toY(lowThresh);
            dc.DrawLine(pen, new Point(plotRect.Left, y), new Point(plotRect.Right, y));
        }
        if (settings.AlertHighEnabled)
        {
            var c = ParseColor(settings.ColorHigh);
            var pen = new Pen(new SolidColorBrush(Color.FromArgb(120, c.R, c.G, c.B)), 1.0)
            {
                DashStyle = DashStyles.Dash
            };
            double y = toY(highThresh);
            dc.DrawLine(pen, new Point(plotRect.Left, y), new Point(plotRect.Right, y));
        }
    }

    private void DrawYAxis(DrawingContext dc, Rect plotRect, double minY, double maxY, GlucoseUnit unit)
    {
        var labelBrush = new SolidColorBrush(LabelColor);
        var gridPen = new Pen(new SolidColorBrush(GridColor), 1.0);
        const int steps = 4;
        for (int i = 0; i <= steps; i++)
        {
            double val = minY + (maxY - minY) * i / steps;
            double y = plotRect.Bottom - (val - minY) / (maxY - minY) * plotRect.Height;
            string lbl = unit == GlucoseUnit.MmolL ? val.ToString("F1") : ((int)val).ToString();
            var ft = MakeFormattedText(lbl, 7.5, labelBrush);
            dc.DrawText(ft, new Point(PadLeft - ft.Width - 2, y - ft.Height / 2));
            dc.DrawLine(gridPen, new Point(plotRect.Left, y), new Point(plotRect.Right, y));
        }
    }

    private void DrawXAxis(DrawingContext dc, Rect plotRect, DateTime startTime, DateTime now, Func<DateTime, double> toX)
    {
        var labelBrush = new SolidColorBrush(LabelColor);
        var firstHour = new DateTime(startTime.Year, startTime.Month, startTime.Day, startTime.Hour, 0, 0, DateTimeKind.Utc).AddHours(1);
        int span = (int)(now - startTime).TotalHours;
        int stride = span <= 3 ? 1 : span <= 6 ? 2 : span <= 12 ? 3 : 6;
        for (var t = firstHour; t <= now; t = t.AddHours(stride))
        {
            double x = toX(t);
            if (x < plotRect.Left || x > plotRect.Right) continue;
            string lbl = t.ToLocalTime().ToString("h tt");
            var ft = MakeFormattedText(lbl, 7.5, labelBrush);
            dc.DrawText(ft, new Point(x - ft.Width / 2, plotRect.Bottom + 3));
        }
    }

    private static void DrawLine(DrawingContext dc, List<GlucoseReading> readings, GlucoseUnit unit, Func<DateTime, double> toX, Func<double, double> toY)
    {
        var pen = new Pen(new SolidColorBrush(Color.FromArgb(180, 100, 160, 255)), 1.8);
        var geometry = new StreamGeometry();
        using (var ctx = geometry.Open())
        {
            bool first = true;
            foreach (var r in readings)
            {
                var pt = new Point(toX(r.Date), toY(DisplayVal(r, unit)));
                if (first) { ctx.BeginFigure(pt, false, false); first = false; }
                else ctx.LineTo(pt, true, false);
            }
        }
        geometry.Freeze();
        dc.DrawGeometry(null, pen, geometry);
    }

    private static void DrawPoints(DrawingContext dc, List<GlucoseReading> readings, GlucoseUnit unit, AppSettings settings, Func<DateTime, double> toX, Func<double, double> toY)
    {
        foreach (var r in readings)
        {
            double x = toX(r.Date);
            double y = toY(DisplayVal(r, unit));
            var color = GlucoseColor(r.Value, settings);
            var brush = new SolidColorBrush(color);
            dc.DrawEllipse(brush, null, new Point(x, y), 3.0, 3.0);
        }
    }

    private void DrawTooltip(DrawingContext dc, GlucoseReading reading, Point pt, List<GlucoseReading> readings, GlucoseUnit unit, AppSettings settings)
    {
        var dotColor = GlucoseColor(reading.Value, settings);

        // Highlight ring
        var highlightBrush = new SolidColorBrush(Color.FromArgb(60, dotColor.R, dotColor.G, dotColor.B));
        dc.DrawEllipse(highlightBrush, null, pt, 8.0, 8.0);

        // Dot
        var dotBrush = new SolidColorBrush(dotColor);
        dc.DrawEllipse(dotBrush, null, pt, 4.0, 4.0);

        string valueLine = $"{reading.DisplayValue(unit)} {reading.Trend.Arrow()}";
        string timeLine  = reading.Date.ToLocalTime().ToString("h:mm tt");
        string? deltaLine = null;
        var idx = readings.IndexOf(reading);
        if (idx >= 0 && idx < readings.Count - 1)
        {
            int delta = reading.Value - readings[idx + 1].Value;
            string sign = delta >= 0 ? "+" : "";
            deltaLine = unit == GlucoseUnit.MmolL
                ? $"{sign}{delta / 18.0:F1} mmol/L"
                : $"{sign}{delta} mg/dL";
        }

        var ftValue = MakeFormattedText(valueLine, 10.0, new SolidColorBrush(dotColor), bold: true);
        var ftTime  = MakeFormattedText(timeLine, 8.0, new SolidColorBrush(Color.FromArgb(255, 130, 130, 140)));
        FormattedText? ftDelta = deltaLine is not null
            ? MakeFormattedText(deltaLine, 8.0, new SolidColorBrush(Color.FromArgb(255, 180, 180, 188)))
            : null;

        double tipW = Math.Max(ftValue.Width, Math.Max(ftTime.Width, ftDelta?.Width ?? 0)) + 16;
        double tipH = ftValue.Height + ftTime.Height + (ftDelta is not null ? ftDelta.Height : 0) + 12;
        double tipX = pt.X - tipW / 2;
        double tipY = pt.Y - tipH - 12;

        if (tipX < PadLeft) tipX = PadLeft;
        if (tipX + tipW > ActualWidth - PadRight) tipX = ActualWidth - PadRight - tipW;
        if (tipY < PadTop) tipY = pt.Y + 12;

        var tipRect = new Rect(tipX, tipY, tipW, tipH);

        // Tooltip background (rounded rect via geometry)
        var bgBrush = new SolidColorBrush(TooltipBg);
        var borderPen = new Pen(new SolidColorBrush(Color.FromArgb(80, 255, 255, 255)), 1.0);
        var rrGeometry = BuildRoundedRect(tipRect, 6);
        dc.DrawGeometry(bgBrush, borderPen, rrGeometry);

        double textY = tipY + 4;
        dc.DrawText(ftValue, new Point(tipX + 8, textY));
        textY += ftValue.Height;
        if (ftDelta is not null)
        {
            dc.DrawText(ftDelta, new Point(tipX + 8, textY));
            textY += ftDelta.Height;
        }
        dc.DrawText(ftTime, new Point(tipX + 8, textY));
    }

    private static Geometry BuildRoundedRect(Rect bounds, double radius)
    {
        var geo = new StreamGeometry();
        using (var ctx = geo.Open())
        {
            double d = radius;
            ctx.BeginFigure(new Point(bounds.Left + d, bounds.Top), true, true);
            ctx.LineTo(new Point(bounds.Right - d, bounds.Top), true, false);
            ctx.ArcTo(new Point(bounds.Right, bounds.Top + d), new Size(d, d), 0, false, SweepDirection.Clockwise, true, false);
            ctx.LineTo(new Point(bounds.Right, bounds.Bottom - d), true, false);
            ctx.ArcTo(new Point(bounds.Right - d, bounds.Bottom), new Size(d, d), 0, false, SweepDirection.Clockwise, true, false);
            ctx.LineTo(new Point(bounds.Left + d, bounds.Bottom), true, false);
            ctx.ArcTo(new Point(bounds.Left, bounds.Bottom - d), new Size(d, d), 0, false, SweepDirection.Clockwise, true, false);
            ctx.LineTo(new Point(bounds.Left, bounds.Top + d), true, false);
            ctx.ArcTo(new Point(bounds.Left + d, bounds.Top), new Size(d, d), 0, false, SweepDirection.Clockwise, true, false);
        }
        geo.Freeze();
        return geo;
    }

    private List<GlucoseReading> GetReadings()
    {
        var cutoff = DateTime.UtcNow - _selectedRange.Interval();
        return _monitor.RecentReadings.Where(r => r.Date >= cutoff).ToList();
    }

    private FormattedText MakeFormattedText(string text, double emSize, Brush brush, bool bold = false)
    {
        var typeface = bold
            ? new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal)
            : new Typeface("Segoe UI");
        return new FormattedText(
            text,
            CultureInfo.CurrentCulture,
            System.Windows.FlowDirection.LeftToRight,
            typeface,
            emSize,
            brush,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
    }

    private static double DisplayVal(GlucoseReading r, GlucoseUnit unit) =>
        unit == GlucoseUnit.MmolL ? r.MmolL : r.Value;

    private static double Threshold(int mgdL, GlucoseUnit unit) =>
        unit == GlucoseUnit.MmolL ? mgdL / 18.0 : mgdL;

    private static Color GlucoseColor(int mgdL, AppSettings s)
    {
        if (mgdL <= s.AlertUrgentLowThresholdMgdL) return ParseColor(s.ColorUrgentLow);
        if (mgdL <= s.AlertLowThresholdMgdL)       return ParseColor(s.ColorLow);
        if (mgdL < s.AlertHighThresholdMgdL)        return ParseColor(s.ColorInRange);
        if (mgdL < s.AlertUrgentHighThresholdMgdL)  return ParseColor(s.ColorHigh);
        return ParseColor(s.ColorUrgentHigh);
    }

    private static Color ParseColor(string hex)
    {
        try
        {
            return (Color)ColorConverter.ConvertFromString(hex);
        }
        catch
        {
            return Colors.Gray;
        }
    }
}
