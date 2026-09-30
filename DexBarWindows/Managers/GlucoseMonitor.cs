using System.IO;
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
    private const int MaxFetchCount = 288;   // Share API limit (24 h of readings)
    private const int MaxAuthRetries = 3;
    private static readonly TimeSpan StaleThreshold = TimeSpan.FromMinutes(20);
    private static readonly TimeSpan ReadingInterval = TimeSpan.FromMinutes(5);
    // Readings further apart than this are not compared for a delta
    // (allows one missed reading plus jitter).
    private static readonly TimeSpan MaxDeltaGap = TimeSpan.FromMinutes(11);
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

    private int _consecutiveStalePolls;

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
    /// Null if fewer than 2 readings or if they are too far apart to compare.
    /// </summary>
    public int? GlucoseDelta =>
        RecentReadings.Count >= 2 ? Delta(RecentReadings[1], RecentReadings[0]) : null;

    /// <summary>newer.Value - older.Value, or null when the readings are too far apart.</summary>
    public static int? Delta(GlucoseReading older, GlucoseReading newer) =>
        newer.Date - older.Date <= MaxDeltaGap ? newer.Value - older.Value : null;

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
            int low = 0, inRange = 0, high = 0;
            foreach (var r in StatsWindow())
            {
                if (r.Value < Settings.AlertLowThresholdMgdL)
                    low++;
                else if (r.Value > Settings.AlertHighThresholdMgdL)
                    high++;
                else
                    inRange++;
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
            var window = StatsWindow();
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
            var window = StatsWindow();
            if (window.Count == 0) return 0;

            // Newest first, so the ends of the window are the extremes.
            return (window[0].Date - window[^1].Date).TotalDays;
        }
    }

    /// <summary>
    /// Readings filtered to the selected chart time range, newest first.
    /// </summary>
    public List<GlucoseReading> ChartReadings =>
        NewestWithin(Settings.SelectedTimeRange.Interval());

    private List<GlucoseReading> StatsWindow() =>
        NewestWithin(Settings.StatsTimeRange.Interval());

    /// <summary>
    /// Readings newer than <paramref name="interval"/> ago. RecentReadings is sorted
    /// newest-first, so this stops at the first older reading rather than scanning
    /// the whole history.
    /// </summary>
    private List<GlucoseReading> NewestWithin(TimeSpan interval)
    {
        var cutoff = DateTime.UtcNow - interval;
        return RecentReadings.TakeWhile(r => r.Date >= cutoff).ToList();
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
        _consecutiveStalePolls = 0;
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
        _consecutiveStalePolls = 0;

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
        var scheduled = NextRefreshDate;
        await DisposeTimerAsync();
        var gotNewReading = await PollAsync(isInitial: false, isManual: true);
        // A manual refresh with no new reading keeps the existing schedule.
        if (!gotNewReading && _service is not null && scheduled is DateTime next && next > DateTime.UtcNow)
            ScheduleTimer(next - DateTime.UtcNow);
        else
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
        // No service means we're stopped (or the password was rejected) — don't poll.
        if (_service is null)
        {
            NextRefreshDate = null;
            return;
        }

        if (CurrentReading is null)
        {
            ScheduleTimer(Settings.RefreshInterval);
            return;
        }

        // Align next poll to reading timestamp + refresh interval
        var nextExpected = CurrentReading.Date + Settings.RefreshInterval;
        var dueTime = nextExpected - DateTime.UtcNow;

        var floor = TimeSpan.FromSeconds(Math.Min(30 * Math.Pow(2, _consecutiveStalePolls), 300));
        if (dueTime < floor)
            dueTime = floor;

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

    /// <returns>True if the poll produced a reading newer than the current one.</returns>
    private async Task<bool> PollAsync(bool isInitial, bool isManual = false)
    {
        if (_service is null) return false;

        // Prevent concurrent polls
        if (!await _pollLock.WaitAsync(0)) return false;
        try
        {
            PostToUi(() =>
            {
                State = new MonitorState.Loading();
                NotifyUpdate();
            });

            // After a sleep or outage, request enough readings to fill the gap.
            var count = isInitial ? MaxFetchCount : FetchCountSinceLastReading();
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
                    return false;
                }

                var password = CredentialStorage.LoadPassword();
                if (password is null)
                {
                    PostToUi(() =>
                    {
                        State = new MonitorState.Error("Session expired. Please re-enter credentials.");
                        NotifyUpdate();
                    });
                    return false;
                }

                try
                {
                    await AuthenticateWithRetryAsync(_username, password);
                    fetched = await _service.GetLatestReadingsAsync(count);
                }
                catch (DexcomException authEx) when (authEx.ErrorType == DexcomErrorType.InvalidCredentials)
                {
                    // Retrying a rejected password only risks locking the Dexcom account.
                    // Stop polling until the user reconnects in Settings.
                    _service = null;
                    await DisposeTimerAsync();
                    PostToUi(() =>
                    {
                        State = new MonitorState.Error("Dexcom rejected the saved password — reconnect in Settings.");
                        NextRefreshDate = null;
                        NotifyUpdate();
                    });
                    return false;
                }
                catch (Exception retryEx)
                {
                    PostToUi(() =>
                    {
                        State = new MonitorState.Error(retryEx.Message);
                        NotifyUpdate();
                    });
                    return false;
                }
            }
            catch (Exception ex)
            {
                PostToUi(() =>
                {
                    State = new MonitorState.Error(ex.Message);
                    NotifyUpdate();
                });
                return false;
            }

            var merged = MergeReadings(fetched, out var added);
            if (added > 0)
                SaveReadingsToDisk(merged);

            var latest = merged.Count > 0 ? merged[0] : null;

            var isStale = latest is not null && CurrentReading is not null && latest.Date == CurrentReading.Date;
            // Manual refreshes don't count toward the stale-poll backoff.
            if (!isStale)
                _consecutiveStalePolls = 0;
            else if (!isManual)
                _consecutiveStalePolls++;

            PostToUi(() =>
            {
                RecentReadings = merged;
                CurrentReading = latest;
                State = new MonitorState.Connected();
                LastUpdated = DateTime.UtcNow;
                NotifyUpdate();

                if (latest is not null)
                    EvaluateAlerts(latest);
            });

            return !isStale;
        }
        finally
        {
            _pollLock.Release();
        }
    }

    private int FetchCountSinceLastReading()
    {
        var readings = RecentReadings;
        if (readings.Count == 0) return MaxFetchCount;
        var missed = (int)((DateTime.UtcNow - readings[0].Date) / ReadingInterval) + 2;
        return Math.Clamp(missed, 2, MaxFetchCount);
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

    private List<GlucoseReading> MergeReadings(IEnumerable<GlucoseReading> incoming, out int added)
    {
        var merged = new List<GlucoseReading>(RecentReadings);
        var existing = new HashSet<DateTime>(merged.Select(r => r.Date));

        added = 0;
        foreach (var r in incoming)
        {
            if (existing.Add(r.Date))
            {
                merged.Add(r);
                added++;
            }
        }

        // Sort newest first and cap
        return merged
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
        if (reading.Value < Settings.AlertUrgentLowThresholdMgdL && Settings.AlertUrgentLowEnabled)
        {
            TryFireAlert("UrgentLow",
                "Urgent Low Alert",
                $"Glucose is {reading.DisplayValue(Settings.Unit)} {reading.Trend.Arrow()} (Urgent Low)");
        }
        else if (reading.Value < Settings.AlertLowThresholdMgdL && Settings.AlertLowEnabled)
        {
            TryFireAlert("Low",
                "Low Alert",
                $"Glucose is {reading.DisplayValue(Settings.Unit)} {reading.Trend.Arrow()} (Low)");
        }
        else if (reading.Value > Settings.AlertUrgentHighThresholdMgdL && Settings.AlertUrgentHighEnabled)
        {
            TryFireAlert("UrgentHigh",
                "Urgent High Alert",
                $"Glucose is {reading.DisplayValue(Settings.Unit)} {reading.Trend.Arrow()} (Urgent High)");
        }
        else if (reading.Value > Settings.AlertHighThresholdMgdL && Settings.AlertHighEnabled)
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

    private void SaveReadingsToDisk(List<GlucoseReading> readings)
    {
        try
        {
            var dir = Path.GetDirectoryName(ReadingsPath)!;
            Directory.CreateDirectory(dir);

            var persisted = readings.Select(r => new PersistedReading
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
