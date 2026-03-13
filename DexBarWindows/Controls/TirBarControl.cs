using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace DexBarWindows.Controls;

/// <summary>
/// Custom-painted horizontal bar showing low / in-range / high proportions.
/// </summary>
public class TirBarControl : Control
{
    public double LowPct      { get; set; }
    public double InRangePct  { get; set; }
    public double HighPct     { get; set; }
    public Color  LowColor    { get; set; } = Color.OrangeRed;
    public Color  InRangeColor { get; set; } = Color.MediumSeaGreen;
    public Color  HighColor   { get; set; } = Color.Gold;

    public TirBarControl()
    {
        DoubleBuffered = true;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint, true);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        float w = Width;
        float h = Height;
        float lowW    = (float)(LowPct    / 100.0 * w);
        float inRangeW = (float)(InRangePct / 100.0 * w);
        float highW   = Math.Max(0, w - lowW - inRangeW);

        using var path = RoundedRect(new RectangleF(0, 0, w, h), 3f);
        g.SetClip(path);

        using (var b = new SolidBrush(LowColor))
            g.FillRectangle(b, 0, 0, lowW, h);
        using (var b = new SolidBrush(InRangeColor))
            g.FillRectangle(b, lowW, 0, inRangeW, h);
        using (var b = new SolidBrush(HighColor))
            g.FillRectangle(b, lowW + inRangeW, 0, highW, h);

        g.ResetClip();
    }

    private static GraphicsPath RoundedRect(RectangleF r, float radius)
    {
        var path = new GraphicsPath();
        float d = radius * 2;
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
