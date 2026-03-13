using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;
using DexBarWindows.Managers;
using DexBarWindows.Models;

namespace DexBarWindows.Controls;

/// <summary>
/// Custom-painted chart displaying glucose readings over a selected time window.
/// </summary>
public class GlucoseChartControl : UserControl
{
    private readonly GlucoseMonitor _monitor;
    private TimeRange _selectedRange = TimeRange.ThreeHours;

    private const int PadLeft = 36;
    private const int PadRight = 6;
    private const int PadTop = 6;
    private const int PadBottom = 22;

    private static readonly Color BackgroundColor = Color.FromArgb(24, 24, 26);
    private static readonly Color GridColor = Color.FromArgb(50, 50, 55);
    private static readonly Color LabelColor = Color.FromArgb(130, 130, 140);
    private static readonly Color TooltipBg = Color.FromArgb(220, 44, 44, 48);

    // Hover state
    private GlucoseReading? _hoveredReading;
    private PointF _hoveredPoint;

    public TimeRange SelectedRange
    {
        get => _selectedRange;
        set { _selectedRange = value; Invalidate(); }
    }

    public GlucoseChartControl(GlucoseMonitor monitor)
    {
        _monitor = monitor;
        DoubleBuffered = true;
        BackColor = BackgroundColor;

        MouseMove += OnChartMouseMove;
        MouseLeave += (_, _) => { _hoveredReading = null; Invalidate(); };
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

        var settings = _monitor.Settings;
        var unit = settings.Unit;
        var readings = GetReadings();

        var plotRect = new Rectangle(
            PadLeft, PadTop,
            Width - PadLeft - PadRight,
            Height - PadTop - PadBottom);

        if (readings.Count == 0)
        {
            DrawNoData(g, plotRect);
            return;
        }

        // Y domain
        double lowThresh  = Threshold(settings.AlertLowThresholdMgdL,  unit);
        double highThresh = Threshold(settings.AlertHighThresholdMgdL, unit);
        var vals = readings.Select(r => DisplayVal(r, unit)).ToList();
        double yPad   = unit == GlucoseUnit.MmolL ? 0.8 : 15;
        double minY   = Math.Min(vals.Min(), lowThresh)  - yPad;
        double maxY   = Math.Max(vals.Max(), highThresh) + yPad;

        // X domain
        var now       = DateTime.UtcNow;
        var startTime = now - _selectedRange.Interval();
        double xSpan  = (now - startTime).TotalSeconds;

        float ToX(DateTime dt) =>
            plotRect.Left + (float)((dt - startTime).TotalSeconds / xSpan) * plotRect.Width;
        float ToY(double v) =>
            plotRect.Bottom - (float)((v - minY) / (maxY - minY)) * plotRect.Height;

        DrawInRangeBand(g, plotRect, ToY, highThresh, lowThresh, settings);
        DrawThresholdLines(g, plotRect, ToY, highThresh, lowThresh, settings);
        DrawYAxis(g, plotRect, minY, maxY, unit);
        DrawXAxis(g, plotRect, startTime, now, ToX);

        if (readings.Count >= 2)
            DrawLine(g, readings, unit, ToX, ToY);

        DrawPoints(g, readings, unit, settings, ToX, ToY);

        // Hover tooltip — draw last so it's on top
        if (_hoveredReading is not null)
            DrawTooltip(g, _hoveredReading, _hoveredPoint, readings, unit, settings);
    }

    // -------------------------------------------------------------------------
    // Mouse hover — find nearest reading
    // -------------------------------------------------------------------------

    private void OnChartMouseMove(object? sender, MouseEventArgs e)
    {
        var settings = _monitor.Settings;
        var unit = settings.Unit;
        var readings = GetReadings();

        if (readings.Count == 0)
        {
            if (_hoveredReading is not null) { _hoveredReading = null; Invalidate(); }
            return;
        }

        var plotRect = new Rectangle(
            PadLeft, PadTop,
            Width - PadLeft - PadRight,
            Height - PadTop - PadBottom);

        if (!plotRect.Contains(e.Location))
        {
            if (_hoveredReading is not null) { _hoveredReading = null; Invalidate(); }
            return;
        }

        // Reconstruct coordinate functions
        double lowThresh  = Threshold(settings.AlertLowThresholdMgdL, unit);
        double highThresh = Threshold(settings.AlertHighThresholdMgdL, unit);
        var vals = readings.Select(r => DisplayVal(r, unit)).ToList();
        double yPad = unit == GlucoseUnit.MmolL ? 0.8 : 15;
        double minY = Math.Min(vals.Min(), lowThresh)  - yPad;
        double maxY = Math.Max(vals.Max(), highThresh) + yPad;

        var now       = DateTime.UtcNow;
        var startTime = now - _selectedRange.Interval();
        double xSpan  = (now - startTime).TotalSeconds;

        float ToX(DateTime dt) =>
            plotRect.Left + (float)((dt - startTime).TotalSeconds / xSpan) * plotRect.Width;
        float ToY(double v) =>
            plotRect.Bottom - (float)((v - minY) / (maxY - minY)) * plotRect.Height;

        // Find nearest reading by pixel distance
        GlucoseReading? nearest = null;
        float nearestDist = float.MaxValue;
        PointF nearestPt = default;

        foreach (var r in readings)
        {
            float px = ToX(r.Date);
            float py = ToY(DisplayVal(r, unit));
            float dist = Math.Abs(e.X - px);
            if (dist < nearestDist)
            {
                nearestDist = dist;
                nearest = r;
                nearestPt = new PointF(px, py);
            }
        }

        // Only show tooltip if within 20px of a data point
        if (nearest is not null && nearestDist <= 20)
        {
            if (_hoveredReading != nearest)
            {
                _hoveredReading = nearest;
                _hoveredPoint = nearestPt;
                Invalidate();
            }
        }
        else if (_hoveredReading is not null)
        {
            _hoveredReading = null;
            Invalidate();
        }
    }

    // -------------------------------------------------------------------------
    // Drawing helpers
    // -------------------------------------------------------------------------

    private static void DrawNoData(Graphics g, Rectangle plotRect)
    {
        using var font  = new Font("Segoe UI", 9f);
        using var brush = new SolidBrush(LabelColor);
        const string text = "No readings for this period";
        var sz = g.MeasureString(text, font);
        g.DrawString(text, font, brush,
            plotRect.Left + (plotRect.Width  - sz.Width)  / 2,
            plotRect.Top  + (plotRect.Height - sz.Height) / 2);
    }

    private static void DrawInRangeBand(
        Graphics g, Rectangle plotRect,
        Func<double, float> toY,
        double highThresh, double lowThresh,
        AppSettings settings)
    {
        var inRangeColor = ParseColor(settings.ColorInRange);
        using var brush = new SolidBrush(Color.FromArgb(28, inRangeColor));
        float y1 = toY(highThresh);
        float y2 = toY(lowThresh);
        g.FillRectangle(brush, plotRect.Left, y1, plotRect.Width, y2 - y1);
    }

    private static void DrawThresholdLines(
        Graphics g, Rectangle plotRect,
        Func<double, float> toY,
        double highThresh, double lowThresh,
        AppSettings settings)
    {
        if (settings.AlertLowEnabled)
        {
            using var pen = new Pen(Color.FromArgb(120, ParseColor(settings.ColorLow)), 1f)
            {
                DashStyle = DashStyle.Dash
            };
            float y = toY(lowThresh);
            g.DrawLine(pen, plotRect.Left, y, plotRect.Right, y);
        }

        if (settings.AlertHighEnabled)
        {
            using var pen = new Pen(Color.FromArgb(120, ParseColor(settings.ColorHigh)), 1f)
            {
                DashStyle = DashStyle.Dash
            };
            float y = toY(highThresh);
            g.DrawLine(pen, plotRect.Left, y, plotRect.Right, y);
        }
    }

    private static void DrawYAxis(Graphics g, Rectangle plotRect, double minY, double maxY, GlucoseUnit unit)
    {
        using var font  = new Font("Segoe UI", 7.5f);
        using var brush = new SolidBrush(LabelColor);
        using var gridPen = new Pen(GridColor, 1f);

        const int steps = 4;
        for (int i = 0; i <= steps; i++)
        {
            double val = minY + (maxY - minY) * i / steps;
            float y    = plotRect.Bottom - (float)((val - minY) / (maxY - minY)) * plotRect.Height;
            string lbl = unit == GlucoseUnit.MmolL ? val.ToString("F1") : ((int)val).ToString();
            var sz = g.MeasureString(lbl, font);
            g.DrawString(lbl, font, brush, PadLeft - sz.Width - 2, y - sz.Height / 2);
            g.DrawLine(gridPen, plotRect.Left, y, plotRect.Right, y);
        }
    }

    private static void DrawXAxis(
        Graphics g, Rectangle plotRect,
        DateTime startTime, DateTime now,
        Func<DateTime, float> toX)
    {
        using var font  = new Font("Segoe UI", 7.5f);
        using var brush = new SolidBrush(LabelColor);

        // Start at the first whole hour after startTime
        var firstHour = new DateTime(startTime.Year, startTime.Month, startTime.Day,
            startTime.Hour, 0, 0, DateTimeKind.Utc).AddHours(1);

        int span  = (int)(now - startTime).TotalHours;
        int stride = span <= 3 ? 1 : span <= 6 ? 2 : span <= 12 ? 3 : 6;

        for (var t = firstHour; t <= now; t = t.AddHours(stride))
        {
            float x = toX(t);
            if (x < plotRect.Left || x > plotRect.Right) continue;
            string lbl = t.ToLocalTime().ToString("h tt");
            var sz = g.MeasureString(lbl, font);
            g.DrawString(lbl, font, brush, x - sz.Width / 2, plotRect.Bottom + 3);
        }
    }

    private static void DrawLine(
        Graphics g, List<GlucoseReading> readings, GlucoseUnit unit,
        Func<DateTime, float> toX, Func<double, float> toY)
    {
        var pts = readings
            .Select(r => new PointF(toX(r.Date), toY(DisplayVal(r, unit))))
            .ToArray();
        using var pen = new Pen(Color.FromArgb(180, 100, 160, 255), 1.8f);
        g.DrawLines(pen, pts);
    }

    private static void DrawPoints(
        Graphics g, List<GlucoseReading> readings, GlucoseUnit unit,
        AppSettings settings, Func<DateTime, float> toX, Func<double, float> toY)
    {
        foreach (var r in readings)
        {
            float x = toX(r.Date);
            float y = toY(DisplayVal(r, unit));
            var color = GlucoseColor(r.Value, settings);
            using var brush = new SolidBrush(color);
            g.FillEllipse(brush, x - 3f, y - 3f, 6f, 6f);
        }
    }

    private void DrawTooltip(
        Graphics g, GlucoseReading reading, PointF pt,
        List<GlucoseReading> readings, GlucoseUnit unit, AppSettings settings)
    {
        // Highlight dot
        var dotColor = GlucoseColor(reading.Value, settings);
        using var highlightBrush = new SolidBrush(Color.FromArgb(60, dotColor));
        g.FillEllipse(highlightBrush, pt.X - 8f, pt.Y - 8f, 16f, 16f);
        using var dotBrush = new SolidBrush(dotColor);
        g.FillEllipse(dotBrush, pt.X - 4f, pt.Y - 4f, 8f, 8f);

        // Build tooltip text lines
        string valueLine = $"{reading.DisplayValue(unit)} {reading.Trend.Arrow()}";
        string timeLine  = reading.Date.ToLocalTime().ToString("h:mm tt");

        // Delta from previous reading
        string? deltaLine = null;
        var idx = readings.IndexOf(reading);
        if (idx >= 0 && idx < readings.Count - 1)
        {
            int delta = reading.Value - readings[idx + 1].Value;
            var sign = delta >= 0 ? "+" : "";
            deltaLine = unit == GlucoseUnit.MmolL
                ? $"{sign}{delta / 18.0:F1} mmol/L"
                : $"{sign}{delta} mg/dL";
        }

        // Measure tooltip
        using var fontValue = new Font("Segoe UI", 10f, FontStyle.Bold);
        using var fontSmall = new Font("Segoe UI", 8f);
        var szValue = g.MeasureString(valueLine, fontValue);
        var szTime  = g.MeasureString(timeLine, fontSmall);
        var szDelta = deltaLine is not null ? g.MeasureString(deltaLine, fontSmall) : SizeF.Empty;

        float tipW = Math.Max(szValue.Width, Math.Max(szTime.Width, szDelta.Width)) + 16;
        float tipH = szValue.Height + szTime.Height + (deltaLine is not null ? szDelta.Height : 0) + 12;

        // Position tooltip above the point, clamped within control bounds
        float tipX = pt.X - tipW / 2;
        float tipY = pt.Y - tipH - 12;
        if (tipX < PadLeft) tipX = PadLeft;
        if (tipX + tipW > Width - PadRight) tipX = Width - PadRight - tipW;
        if (tipY < PadTop) tipY = pt.Y + 12; // flip below if too close to top

        // Draw tooltip background
        var tipRect = new RectangleF(tipX, tipY, tipW, tipH);
        using var bgBrush = new SolidBrush(TooltipBg);
        using var path = RoundedRect(tipRect, 6);
        g.FillPath(bgBrush, path);
        using var borderPen = new Pen(Color.FromArgb(80, 255, 255, 255), 1f);
        g.DrawPath(borderPen, path);

        // Draw text
        float textY = tipY + 4;
        using var valueBrush = new SolidBrush(dotColor);
        g.DrawString(valueLine, fontValue, valueBrush, tipX + 8, textY);
        textY += szValue.Height;

        if (deltaLine is not null)
        {
            using var deltaBrush = new SolidBrush(Color.FromArgb(180, 180, 188));
            g.DrawString(deltaLine, fontSmall, deltaBrush, tipX + 8, textY);
            textY += szDelta.Height;
        }

        using var timeBrush = new SolidBrush(Color.FromArgb(130, 130, 140));
        g.DrawString(timeLine, fontSmall, timeBrush, tipX + 8, textY);
    }

    private static GraphicsPath RoundedRect(RectangleF bounds, float radius)
    {
        var path = new GraphicsPath();
        float d = radius * 2;
        path.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
        path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
        path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
        path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private List<GlucoseReading> GetReadings()
    {
        var cutoff = DateTime.UtcNow - _selectedRange.Interval();
        return _monitor.RecentReadings.Where(r => r.Date >= cutoff).ToList();
    }

    private static double DisplayVal(GlucoseReading r, GlucoseUnit unit) =>
        unit == GlucoseUnit.MmolL ? r.MmolL : r.Value;

    private static double Threshold(int mgdL, GlucoseUnit unit) =>
        unit == GlucoseUnit.MmolL ? mgdL / 18.0 : mgdL;

    private static Color GlucoseColor(int mgdL, AppSettings s)
    {
        if (mgdL <= s.AlertUrgentLowThresholdMgdL)  return ParseColor(s.ColorUrgentLow);
        if (mgdL <= s.AlertLowThresholdMgdL)         return ParseColor(s.ColorLow);
        if (mgdL <  s.AlertHighThresholdMgdL)         return ParseColor(s.ColorInRange);
        if (mgdL <  s.AlertUrgentHighThresholdMgdL)   return ParseColor(s.ColorHigh);
        return ParseColor(s.ColorUrgentHigh);
    }

    private static Color ParseColor(string hex)
    {
        try { return ColorTranslator.FromHtml(hex); }
        catch { return Color.Gray; }
    }
}
