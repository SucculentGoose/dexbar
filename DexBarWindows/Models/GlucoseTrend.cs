namespace DexBarWindows.Models;

public enum GlucoseTrend
{
    None = 0,
    DoubleUp = 1,
    SingleUp = 2,
    FortyFiveUp = 3,
    Flat = 4,
    FortyFiveDown = 5,
    SingleDown = 6,
    DoubleDown = 7,
    NotComputable = 8,
    RateOutOfRange = 9
}

public static class GlucoseTrendExtensions
{
    public static string Arrow(this GlucoseTrend trend) => trend switch
    {
        GlucoseTrend.DoubleUp => "⇈",
        GlucoseTrend.SingleUp => "↑",
        GlucoseTrend.FortyFiveUp => "↗",
        GlucoseTrend.Flat => "→",
        GlucoseTrend.FortyFiveDown => "↘",
        GlucoseTrend.SingleDown => "↓",
        GlucoseTrend.DoubleDown => "⇊",
        _ => "?"
    };

    public static string Description(this GlucoseTrend trend) => trend switch
    {
        GlucoseTrend.DoubleUp => "rising quickly",
        GlucoseTrend.SingleUp => "rising",
        GlucoseTrend.FortyFiveUp => "rising slowly",
        GlucoseTrend.Flat => "steady",
        GlucoseTrend.FortyFiveDown => "falling slowly",
        GlucoseTrend.SingleDown => "falling",
        GlucoseTrend.DoubleDown => "falling quickly",
        _ => "unknown"
    };

    public static bool IsRisingFast(this GlucoseTrend trend) =>
        trend is GlucoseTrend.DoubleUp or GlucoseTrend.SingleUp;

    public static bool IsDroppingFast(this GlucoseTrend trend) =>
        trend is GlucoseTrend.DoubleDown or GlucoseTrend.SingleDown;
}
