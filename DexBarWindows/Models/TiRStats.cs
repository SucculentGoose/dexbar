namespace DexBarWindows.Models;

public class TiRStats
{
    public int LowCount { get; init; }
    public int InRangeCount { get; init; }
    public int HighCount { get; init; }

    public int Total => LowCount + InRangeCount + HighCount;

    public double LowPct => Total > 0 ? LowCount * 100.0 / Total : 0;
    public double InRangePct => Total > 0 ? InRangeCount * 100.0 / Total : 0;
    public double HighPct => Total > 0 ? HighCount * 100.0 / Total : 0;
}
