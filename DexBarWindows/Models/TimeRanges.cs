namespace DexBarWindows.Models;

public enum StatsTimeRange
{
    TwoDays,
    SevenDays,
    FourteenDays,
    ThirtyDays,
    NinetyDays
}

public static class StatsTimeRangeExtensions
{
    public static TimeSpan Interval(this StatsTimeRange r) => r switch
    {
        StatsTimeRange.TwoDays => TimeSpan.FromDays(2),
        StatsTimeRange.SevenDays => TimeSpan.FromDays(7),
        StatsTimeRange.FourteenDays => TimeSpan.FromDays(14),
        StatsTimeRange.ThirtyDays => TimeSpan.FromDays(30),
        StatsTimeRange.NinetyDays => TimeSpan.FromDays(90),
        _ => TimeSpan.FromDays(7)
    };
}

public enum TimeRange
{
    ThreeHours,
    SixHours,
    TwelveHours,
    Day
}

public static class TimeRangeExtensions
{
    public static TimeSpan Interval(this TimeRange r) => r switch
    {
        TimeRange.ThreeHours => TimeSpan.FromHours(3),
        TimeRange.SixHours => TimeSpan.FromHours(6),
        TimeRange.TwelveHours => TimeSpan.FromHours(12),
        TimeRange.Day => TimeSpan.FromHours(24),
        _ => TimeSpan.FromHours(3)
    };
}
