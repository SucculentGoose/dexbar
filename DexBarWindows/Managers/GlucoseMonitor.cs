using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using DexBarWindows.Models;
using DexBarWindows.Services;

namespace DexBarWindows.Managers;

/// <summary>
/// Manages glucose polling, state, alerts, and persisted readings.
/// Thread-safe state changes are marshalled back to the UI thread via the
/// SynchronizationContext captured at construction time.
/// </summary>
public class GlucoseMonitor : IDisposable
{
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    private const int MaxReadings = 25_920;
    private const int InitialFetchCount = 288;
    private const int SubsequentFetchCount = 2;
    private const int MaxAuthRetries = 3;
    private static readonly TimeSpan StaleThreshold = TimeSpan.FromMinutes(20);
    private static readonly TimeSpan AlertCooldown = TimeSpan.FromMinutes(15);

    private static readonly int[] RetryDelaysMs = { 3_000, 5_000, 10_000 };

    private static readonly string ReadingsPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "DexBar",
        "readings.json");

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false,
        Converters = { new JsonStringEnumConverter() }
    };

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    private readonly SynchronizationContext _syncContext;
    private DexcomService? _service;
    private System.Threading.Timer? _timer;
    private string? _username;
    private bool _disposed;

    // Serialization lock: ensures only one poll runs at a time and protects
    // _recentReadings mutations.
    private readonly SemaphoreSlim _pollLock = new(1, 1);

    private readonly Dictionary<string, DateTime> _alertCooldowns = new();

    // -------------------------------------------------------------------------
    // Observable state (always accessed on UI thread via _syncContext)
    // -------------------------------------------------------------------------

    /// <summary>The most recent glucose reading, or null if none available.</summary>
    public GlucoseReading? CurrentReading { get; private set; }

    /// <summary>All readings, newest first, capped at 25,920 entries.</summary>
    public List<GlucoseReading> RecentReadings { get; private set; } = [];

    /// <summary>Current monitor state.</summary>
    public MonitorState State { get; private set; } = new MonitorState.Idle();

    /// <summary>When state was last updated.</summary>
    public DateTime? LastUpdated { get; private set; }

    /// <summary>When the next automatic refresh is scheduled.</summary>
    public DateTime? NextRefreshDate { get; private set; }

    /// <summary>Loaded app settings.</summary>
    public AppSettings Settings { get; private set; }

    // -------------------------------------------------------------------------
    // Callbacks
    // -------------------------------------------------------------------------

    /// <summary>Fired on any state change (always on UI thread).</summary>
    public Action? OnUpdate { get; set; }

    /// <summary>Fired when an alert condition is triggered (title, message).</summary>
    public Action<string, string>? OnAlert { get; set; }

    // -------------------------------------------------------------------------
    // Computed properties
    // -------------------------------------------------------------------------

    /// <summary>
    /// Delta between the two most recent readings (newest - second-newest), in mg/dL.
    /// Null if fewer than 2 readings.
    /// </summary>
    public int? GlucoseDelta =>
        RecentReadings.Count >= 2
            ? RecentReadings[0].Value - RecentReadings[1].Value
            : null;

    /// <summary>
    /// Formatted delta string such as "+3" or "-0.2", respecting the configured unit.
    /// Returns null if fewer than 2 readings.
    /// </summary>
    public string? FormattedDelta(GlucoseUnit unit)
    {
        var delta = GlucoseDelta;
        if (delta is null) return null;

        if (unit == GlucoseUnit.MmolL)
        {
            var mmol = delta.Value / 18.0;
            var sign = mmol >= 0 ? "+" : "";
            return $"{sign}{mmol:F1}";
        }
        else
        {
            var sign = delta.Value >= 0 ? "+" : "";
            return $"{sign}{delta.Value}";
        }
    }

    /// <summary>True if the current reading is older than 20 minutes (or there is none).</summary>
    public bool IsStale =>
        CurrentReading is null ||
        DateTime.UtcNow - CurrentReading.Date > StaleThreshold;

    /// <summary>
    /// Time-in-Range statistics computed over the configured StatsTimeRange window.
    /// </summary>
    public TiRStats TirStats
    {
        get
        {
            var cutoff = DateTime.UtcNow - Settings.StatsTimeRange.Interval();
            var window = RecentReadings.Where(r => r.Date >= cutoff).ToList();

            int low = 0, inRange = 0, high = 0;
            foreach (var r in window)
            {
                if (r.Value <= Settings.AlertLowThresholdMgdL)
                    low++;
                else if (r.Value < Settings.AlertHighThresholdMgdL)
                    inRange++;
                else
                    high++;
            }

            return new TiRStats
            {
                LowCount = low,
                InRangeCount = inRange,
                HighCount = high
            };
        }
    }

    /// <summary>
    /// Glucose Management Indicator (GMI) calculated from mean glucose in the stats window.
    /// Returns null if there are no readings in the window.
    /// </summary>
    public double? Gmi
    {
        get
        {
            var cutoff = DateTime.UtcNow - Settings.StatsTimeRange.Interval();
            var window = RecentReadings.Where(r => r.Date >= cutoff).ToList();
            if (window.Count == 0) return null;

            var mean = window.Average(r => r.Value);
            return 3.31 + 0.02392 * mean;
        }
    }

    /// <summary>
    /// Actual span (in days) of data within the selected stats time range.
    /// </summary>
    public double StatsDataSpanDays
    {
        get
        {
            var cutoff = DateTime.UtcNow - Settings.StatsTimeRange.Interval();
            var window = RecentReadings.Where(r => r.Date >= cutoff).ToList();
            if (window.Count == 0) return 0;

            var oldest = window.Min(r => r.Date);
            var newest = window.Max(r => r.Date);
            return (newest - oldest).TotalDays;
        }
    }

    /// <summary>
    /// Readings filtered to the selected chart time range, newest first.
    /// </summary>
    public List<GlucoseReading> ChartReadings
    {
        get
        {
            var cutoff = DateTime.UtcNow - Settings.SelectedTimeRange.Interval();
            return RecentReadings.Where(r => r.Date >= cutoff).ToList();
        }
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    public GlucoseMonitor()
    {
        _syncContext = SynchronizationContext.Current
            ?? throw new InvalidOperationException(
                "GlucoseMonitor must be constructed on the UI thread.");

        Settings = AppSettings.Load();
        LoadReadingsFromDisk();
    }

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    /// <summary>
    /// Authenticates with Dexcom and begins polling.
    /// </summary>
    public async Task StartAsync(string username, string password, DexcomRegion region)
    {
        _username = username;
        Settings.Region = region;
        Settings.DexcomUsername = username;

        _service = new DexcomService(region);

        await AuthenticateWithRetryAsync(username, password);

        // Fire an initial poll immediately (288 readings), then switch to incremental.
        _ = Task.Run(async () =>
        {
            await PollAsync(isInitial: true);
            ScheduleTimerFromLastReading();
        });
    }

    /// <summary>
    /// Stops polling, clears session, and sets the monitor to Idle.
    /// </summary>
    public async Task StopAsync()
    {
        await DisposeTimerAsync();

        _service?.ClearSession();
        _service = null;
        _username = null;

        PostToUi(() =>
        {
            State = new MonitorState.Idle();
            NotifyUpdate();
        });
    }

    /// <summary>
    /// Triggers an immediate refresh outside of the regular schedule.
    /// </summary>
    public async Task RefreshNowAsync()
    {
        await DisposeTimerAsync();
        await PollAsync(isInitial: false);
        ScheduleTimerFromLastReading();
    }

    /// <summary>
    /// Updates the polling interval and reschedules the timer immediately.
    /// </summary>
    public void UpdateRefreshInterval(TimeSpan interval)
    {
        Settings.RefreshInterval = interval;
        ScheduleTimerFromLastReading();
    }

    // -------------------------------------------------------------------------
    // Timer scheduling
    // -------------------------------------------------------------------------

    private void ScheduleTimer(TimeSpan dueTime)
    {
        NextRefreshDate = DateTime.UtcNow + dueTime;
        _timer?.Dispose();
        _timer = new System.Threading.Timer(
            callback: async _ => await TimerTickAsync(),
            state: null,
            dueTime: dueTime,
            period: Timeout.InfiniteTimeSpan);
    }

    private void ScheduleTimerFromLastReading()
    {
        if (CurrentReading is null)
        {
            ScheduleTimer(Settings.RefreshInterval);
            return;
        }

        // Align next poll to reading timestamp + refresh interval
        var nextExpected = CurrentReading.Date + Settings.RefreshInterval;
        var dueTime = nextExpected - DateTime.UtcNow;

        if (dueTime < TimeSpan.Zero)
            dueTime = TimeSpan.Zero;

        ScheduleTimer(dueTime);
    }

    private async Task TimerTickAsync()
    {
        await PollAsync(isInitial: false);
        ScheduleTimerFromLastReading();
    }

    private Task DisposeTimerAsync()
    {
        var t = Interlocked.Exchange(ref _timer, null);
        t?.Dispose();
        return Task.CompletedTask;
    }

    // -------------------------------------------------------------------------
    // Polling
    // -------------------------------------------------------------------------

    private async Task PollAsync(bool isInitial)
    {
        if (_service is null) return;

        // Prevent concurrent polls
        if (!await _pollLock.WaitAsync(0)) return;
        try
        {
            PostToUi(() =>
            {
                State = new MonitorState.Loading();
                NotifyUpdate();
            });

            var count = isInitial ? InitialFetchCount : SubsequentFetchCount;
            List<GlucoseReading> fetched;

            try
            {
                fetched = await _service.GetLatestReadingsAsync(count);
            }
            catch (DexcomException ex) when (
                ex.ErrorType is DexcomErrorType.InvalidCredentials or DexcomErrorType.SessionExpired)
            {
                // Session expired — try to re-authenticate
                if (_username is null)
                {
                    PostToUi(() =>
                    {
                        State = new MonitorState.Error("Session expired and no username to re-authenticate.");
                        NotifyUpdate();
                    });
                    return;
                }

                var password = CredentialStorage.LoadPassword();
                if (password is null)
                {
                    PostToUi(() =>
                    {
                        State = new MonitorState.Error("Session expired. Please re-enter credentials.");
                        NotifyUpdate();
                    });
                    return;
                }

                try
                {
                    await AuthenticateWithRetryAsync(_username, password);
                    fetched = await _service.GetLatestReadingsAsync(count);
                }
                catch (Exception retryEx)
                {
                    PostToUi(() =>
                    {
                        State = new MonitorState.Error(retryEx.Message);
                        NotifyUpdate();
                    });
                    return;
                }
            }
            catch (Exception ex)
            {
                PostToUi(() =>
                {
                    State = new MonitorState.Error(ex.Message);
                    NotifyUpdate();
                });
                return;
            }

            MergeReadings(fetched);
            SaveReadingsToDisk();

            var latest = RecentReadings.Count > 0 ? RecentReadings[0] : null;

            PostToUi(() =>
            {
                CurrentReading = latest;
                State = new MonitorState.Connected();
                LastUpdated = DateTime.UtcNow;
                NotifyUpdate();

                if (latest is not null)
                    EvaluateAlerts(latest);
            });
        }
        finally
        {
            _pollLock.Release();
        }
    }

    // -------------------------------------------------------------------------
    // Authentication with retry
    // -------------------------------------------------------------------------

    private async Task AuthenticateWithRetryAsync(string username, string password)
    {
        Exception? lastEx = null;

        for (int attempt = 0; attempt < MaxAuthRetries; attempt++)
        {
            if (attempt > 0)
                await Task.Delay(RetryDelaysMs[attempt - 1]);

            try
            {
                await _service!.AuthenticateAsync(username, password);
                return; // success
            }
            catch (DexcomException ex) when (ex.ErrorType == DexcomErrorType.InvalidCredentials)
            {
                // Invalid credentials won't be fixed by retrying
                throw;
            }
            catch (Exception ex)
            {
                lastEx = ex;
            }
        }

        throw lastEx ?? new DexcomException(DexcomErrorType.Unknown, "Authentication failed.");
    }

    // -------------------------------------------------------------------------
    // Reading merge
    // -------------------------------------------------------------------------

    private void MergeReadings(IEnumerable<GlucoseReading> incoming)
    {
        var existing = new HashSet<DateTime>(RecentReadings.Select(r => r.Date));

        foreach (var r in incoming)
        {
            if (existing.Add(r.Date))
                RecentReadings.Add(r);
        }

        // Sort newest first and cap
        RecentReadings = RecentReadings
            .OrderByDescending(r => r.Date)
            .Take(MaxReadings)
            .ToList();
    }

    // -------------------------------------------------------------------------
    // Alerts
    // -------------------------------------------------------------------------

    private void EvaluateAlerts(GlucoseReading reading)
    {
        // Level alerts — mutually exclusive, checked in priority order
        if (reading.Value <= Settings.AlertUrgentLowThresholdMgdL && Settings.AlertUrgentLowEnabled)
        {
            TryFireAlert("UrgentLow",
                "Urgent Low Alert",
                $"Glucose is {reading.DisplayValue(Settings.Unit)} {reading.Trend.Arrow()} (Urgent Low)");
        }
        else if (reading.Value <= Settings.AlertLowThresholdMgdL && Settings.AlertLowEnabled)
        {
            TryFireAlert("Low",
                "Low Alert",
                $"Glucose is {reading.DisplayValue(Settings.Unit)} {reading.Trend.Arrow()} (Low)");
        }
        else if (reading.Value >= Settings.AlertUrgentHighThresholdMgdL && Settings.AlertUrgentHighEnabled)
        {
            TryFireAlert("UrgentHigh",
                "Urgent High Alert",
                $"Glucose is {reading.DisplayValue(Settings.Unit)} {reading.Trend.Arrow()} (Urgent High)");
        }
        else if (reading.Value >= Settings.AlertHighThresholdMgdL && Settings.AlertHighEnabled)
        {
            TryFireAlert("High",
                "High Alert",
                $"Glucose is {reading.DisplayValue(Settings.Unit)} {reading.Trend.Arrow()} (High)");
        }

        // Trend alerts — independent of level alerts
        if (reading.Trend.IsRisingFast() && Settings.AlertRisingFastEnabled)
        {
            TryFireAlert("RisingFast",
                "Rising Fast",
                "Glucose is rising quickly");
        }

        if (reading.Trend.IsDroppingFast() && Settings.AlertDroppingFastEnabled)
        {
            TryFireAlert("DroppingFast",
                "Dropping Fast",
                "Glucose is dropping quickly");
        }

        // Stale data alert
        if (IsStale && Settings.AlertStaleDataEnabled)
        {
            TryFireAlert("StaleData",
                "Stale Data",
                "No readings in 20 minutes");
        }
    }

    private void TryFireAlert(string key, string title, string message)
    {
        var now = DateTime.UtcNow;

        if (_alertCooldowns.TryGetValue(key, out var lastFired) &&
            now - lastFired < AlertCooldown)
        {
            return; // still in cooldown
        }

        _alertCooldowns[key] = now;
        OnAlert?.Invoke(title, message);
    }

    // -------------------------------------------------------------------------
    // Disk persistence
    // -------------------------------------------------------------------------

    private void LoadReadingsFromDisk()
    {
        try
        {
            if (!File.Exists(ReadingsPath))
                return;

            var json = File.ReadAllText(ReadingsPath);
            var loaded = JsonSerializer.Deserialize<List<PersistedReading>>(json, JsonOptions);
            if (loaded is null) return;

            RecentReadings = loaded
                .Select(p => new GlucoseReading
                {
                    Id = p.Id,
                    Value = p.Value,
                    Trend = p.Trend,
                    Date = p.Date,
                    TrendRate = p.TrendRate
                })
                .OrderByDescending(r => r.Date)
                .Take(MaxReadings)
                .ToList();

            CurrentReading = RecentReadings.Count > 0 ? RecentReadings[0] : null;
        }
        catch
        {
            // Non-fatal: start with empty readings
            RecentReadings = [];
        }
    }

    private void SaveReadingsToDisk()
    {
        try
        {
            var dir = Path.GetDirectoryName(ReadingsPath)!;
            Directory.CreateDirectory(dir);

            var persisted = RecentReadings.Select(r => new PersistedReading
            {
                Id = r.Id,
                Value = r.Value,
                Trend = r.Trend,
                Date = r.Date,
                TrendRate = r.TrendRate
            }).ToList();

            var json = JsonSerializer.Serialize(persisted, JsonOptions);
            File.WriteAllText(ReadingsPath, json);
        }
        catch
        {
            // Non-fatal: disk save failure should not crash the app
        }
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /// <summary>Posts an action back to the captured UI synchronization context.</summary>
    private void PostToUi(Action action) =>
        _syncContext.Post(_ => action(), null);

    /// <summary>Fires OnUpdate. Must be called from the UI thread (inside PostToUi).</summary>
    private void NotifyUpdate() => OnUpdate?.Invoke();

    // -------------------------------------------------------------------------
    // IDisposable
    // -------------------------------------------------------------------------

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        _timer?.Dispose();
        _timer = null;
        _pollLock.Dispose();
        _service?.ClearSession();
        GC.SuppressFinalize(this);
    }

    // -------------------------------------------------------------------------
    // Private DTO for JSON persistence (avoids init-only property issues)
    // -------------------------------------------------------------------------

    private sealed class PersistedReading
    {
        public Guid Id { get; set; }
        public int Value { get; set; }
        public GlucoseTrend Trend { get; set; }
        public DateTime Date { get; set; }
        public double? TrendRate { get; set; }
    }
}
