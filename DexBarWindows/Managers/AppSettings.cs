using System.Text.Json;
using System.Text.Json.Serialization;
using DexBarWindows.Models;

namespace DexBarWindows.Managers;

/// <summary>
/// Persists application settings to %APPDATA%\DexBar\settings.json.
/// </summary>
public class AppSettings
{
    private static readonly string SettingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "DexBar",
        "settings.json");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    // -------------------------------------------------------------------------
    // Display / unit settings
    // -------------------------------------------------------------------------

    public GlucoseUnit Unit { get; set; } = GlucoseUnit.MgdL;
    public int RefreshIntervalSeconds { get; set; } = 300; // 5 minutes
    public DexcomRegion Region { get; set; } = DexcomRegion.US;
    public StatsTimeRange StatsTimeRange { get; set; } = StatsTimeRange.SevenDays;
    public TimeRange SelectedTimeRange { get; set; } = TimeRange.ThreeHours;

    [JsonIgnore]
    public TimeSpan RefreshInterval
    {
        get => TimeSpan.FromSeconds(RefreshIntervalSeconds);
        set => RefreshIntervalSeconds = (int)value.TotalSeconds;
    }

    // -------------------------------------------------------------------------
    // Alert settings
    // -------------------------------------------------------------------------

    public bool AlertUrgentHighEnabled { get; set; } = true;
    public int AlertUrgentHighThresholdMgdL { get; set; } = 250;

    public bool AlertHighEnabled { get; set; } = true;
    public int AlertHighThresholdMgdL { get; set; } = 180;

    public bool AlertLowEnabled { get; set; } = true;
    public int AlertLowThresholdMgdL { get; set; } = 70;

    public bool AlertUrgentLowEnabled { get; set; } = true;
    public int AlertUrgentLowThresholdMgdL { get; set; } = 55;

    public bool AlertRisingFastEnabled { get; set; } = true;
    public bool AlertDroppingFastEnabled { get; set; } = true;
    public bool AlertStaleDataEnabled { get; set; } = true;

    // -------------------------------------------------------------------------
    // Color settings (hex strings)
    // -------------------------------------------------------------------------

    public string ColorUrgentLow { get; set; } = "#D91A1A";
    public string ColorLow { get; set; } = "#FF8C00";
    public string ColorInRange { get; set; } = "#34C759";
    public string ColorHigh { get; set; } = "#FFD60A";
    public string ColorUrgentHigh { get; set; } = "#D91A1A";

    // -------------------------------------------------------------------------
    // Tray / display settings
    // -------------------------------------------------------------------------

    public bool ColoredTrayIcon { get; set; } = true;
    public bool ShowDelta { get; set; } = true;

    // -------------------------------------------------------------------------
    // Dexcom credentials (password is in Windows Credential Manager, not here)
    // -------------------------------------------------------------------------

    public string? DexcomUsername { get; set; }

    // -------------------------------------------------------------------------
    // Persistence
    // -------------------------------------------------------------------------

    /// <summary>
    /// Loads settings from %APPDATA%\DexBar\settings.json.
    /// Returns a default-initialized instance if the file doesn't exist or cannot be parsed.
    /// </summary>
    public static AppSettings Load()
    {
        try
        {
            if (!File.Exists(SettingsPath))
                return new AppSettings();

            var json = File.ReadAllText(SettingsPath);
            return JsonSerializer.Deserialize<AppSettings>(json, JsonOptions)
                   ?? new AppSettings();
        }
        catch
        {
            // Return defaults if the file is corrupt or unreadable.
            return new AppSettings();
        }
    }

    /// <summary>
    /// Saves the current settings to %APPDATA%\DexBar\settings.json.
    /// Creates the directory if it does not exist.
    /// </summary>
    public void Save()
    {
        var dir = Path.GetDirectoryName(SettingsPath)!;
        Directory.CreateDirectory(dir);

        var json = JsonSerializer.Serialize(this, JsonOptions);
        File.WriteAllText(SettingsPath, json);
    }

    // -------------------------------------------------------------------------
    // Glucose color helper
    // -------------------------------------------------------------------------

    /// <summary>
    /// Returns the configured hex color string for the given glucose value (mg/dL).
    /// </summary>
    public string GlucoseColor(int valueMgdL)
    {
        if (valueMgdL <= AlertUrgentLowThresholdMgdL) return ColorUrgentLow;
        if (valueMgdL <= AlertLowThresholdMgdL)       return ColorLow;
        if (valueMgdL <  AlertHighThresholdMgdL)      return ColorInRange;
        if (valueMgdL <  AlertUrgentHighThresholdMgdL) return ColorHigh;
        return ColorUrgentHigh;
    }
}
