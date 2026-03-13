namespace DexBarWindows.Models;

public class GlucoseReading
{
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>Always stored in mg/dL.</summary>
    public int Value { get; init; }

    public GlucoseTrend Trend { get; init; }

    public DateTime Date { get; init; }

    public double? TrendRate { get; init; }

    public double MmolL => Value / 18.0;

    public string DisplayValue(GlucoseUnit unit) =>
        unit == GlucoseUnit.MmolL ? MmolL.ToString("F1") : Value.ToString();

    public string MenuBarLabel(GlucoseUnit unit) =>
        $"{DisplayValue(unit)}{Trend.Arrow()}";
}
