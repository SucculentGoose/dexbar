using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using DexBarWindows.Models;

namespace DexBarWindows.Services;

public enum DexcomErrorType
{
    InvalidCredentials,
    SessionExpired,
    NetworkError,
    ParseError,
    Unknown
}

public class DexcomException : Exception
{
    public DexcomErrorType ErrorType { get; }

    public DexcomException(DexcomErrorType errorType, string message, Exception? inner = null)
        : base(message, inner)
    {
        ErrorType = errorType;
    }
}

public class DexcomService
{
    private static readonly HttpClient _http = new();
    private static readonly JsonSerializerOptions _jsonOptions = new() { PropertyNameCaseInsensitive = true };
    private static readonly Regex _wtRegex = new(@"\d+", RegexOptions.Compiled);
    private const string AppId = "d8665ade-9673-4e27-9ff6-92db4ce13d13";

    // Note: _sessionId is not thread-safe. The monitor ensures only one poll runs at a time.
    private string? _sessionId;
    private readonly DexcomRegion _region;

    private static readonly Dictionary<string, GlucoseTrend> TrendNameMap =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["DoubleUp"] = GlucoseTrend.DoubleUp,
            ["SingleUp"] = GlucoseTrend.SingleUp,
            ["FortyFiveUp"] = GlucoseTrend.FortyFiveUp,
            ["Flat"] = GlucoseTrend.Flat,
            ["FortyFiveDown"] = GlucoseTrend.FortyFiveDown,
            ["SingleDown"] = GlucoseTrend.SingleDown,
            ["DoubleDown"] = GlucoseTrend.DoubleDown,
            ["NotComputable"] = GlucoseTrend.NotComputable,
            ["RateOutOfRange"] = GlucoseTrend.RateOutOfRange
        };

    public DexcomService(DexcomRegion region)
    {
        _region = region;
    }

    /// <summary>
    /// Authenticates against the Dexcom Share API and stores the resulting session ID.
    /// </summary>
    public async Task AuthenticateAsync(string username, string password)
    {
        var baseUrl = _region.BaseUrl();

        // Step 1: authenticate account → accountId
        var authBody = JsonSerializer.Serialize(new
        {
            accountName = username,
            password,
            applicationId = AppId
        });

        string accountId;
        try
        {
            var authResponse = await PostJsonAsync(
                $"{baseUrl}/General/AuthenticatePublisherAccount",
                authBody);

            accountId = StripQuotes(authResponse);
        }
        catch (DexcomException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new DexcomException(DexcomErrorType.NetworkError,
                "Failed to authenticate with Dexcom.", ex);
        }

        // Step 2: login with accountId → sessionId
        var loginBody = JsonSerializer.Serialize(new
        {
            accountId,
            password,
            applicationId = AppId
        });

        try
        {
            var loginResponse = await PostJsonAsync(
                $"{baseUrl}/General/LoginPublisherAccountById",
                loginBody);

            _sessionId = StripQuotes(loginResponse);
        }
        catch (DexcomException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new DexcomException(DexcomErrorType.NetworkError,
                "Failed to obtain Dexcom session.", ex);
        }
    }

    /// <summary>
    /// Fetches the latest glucose readings. AuthenticateAsync must be called first.
    /// </summary>
    public async Task<List<GlucoseReading>> GetLatestReadingsAsync(int maxCount = 2)
    {
        if (_sessionId is null)
            throw new DexcomException(DexcomErrorType.SessionExpired,
                "No active session. Call AuthenticateAsync first.");

        var url = $"{_region.BaseUrl()}/Publisher/ReadPublisherLatestGlucoseValues" +
                  $"?sessionId={Uri.EscapeDataString(_sessionId)}&minutes=1440&maxCount={maxCount}";

        HttpResponseMessage response;
        try
        {
            response = await _http.GetAsync(url);
        }
        catch (Exception ex)
        {
            throw new DexcomException(DexcomErrorType.NetworkError,
                "Network error fetching glucose readings.", ex);
        }

        if (response.StatusCode == HttpStatusCode.InternalServerError)
        {
            _sessionId = null;
            throw new DexcomException(DexcomErrorType.InvalidCredentials,
                "Invalid credentials or session expired (HTTP 500).");
        }

        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync();

        List<DexcomRawReading> rawReadings;
        try
        {
            rawReadings = JsonSerializer.Deserialize<List<DexcomRawReading>>(json, _jsonOptions)
                ?? [];
        }
        catch (Exception ex)
        {
            throw new DexcomException(DexcomErrorType.ParseError,
                "Failed to parse glucose readings.", ex);
        }

        return rawReadings.Select(ParseRawReading).ToList();
    }

    /// <summary>Clears the stored session ID, forcing re-authentication on next use.</summary>
    public void ClearSession() => _sessionId = null;

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    private static async Task<string> PostJsonAsync(string url, string jsonBody)
    {
        using var content = new StringContent(jsonBody, Encoding.UTF8, "application/json");

        HttpResponseMessage response;
        try
        {
            response = await _http.PostAsync(url, content);
        }
        catch (Exception ex)
        {
            throw new DexcomException(DexcomErrorType.NetworkError,
                $"HTTP request to {url} failed.", ex);
        }

        if (response.StatusCode == HttpStatusCode.InternalServerError)
            throw new DexcomException(DexcomErrorType.InvalidCredentials,
                "Invalid credentials (HTTP 500).");

        response.EnsureSuccessStatusCode();

        return await response.Content.ReadAsStringAsync();
    }

    /// <summary>Strips surrounding double-quotes from a Dexcom UUID response.</summary>
    private static string StripQuotes(string value) =>
        value.Trim().Trim('"');

    private static GlucoseReading ParseRawReading(DexcomRawReading raw)
    {
        var date = ParseWtTimestamp(raw.WT);
        TrendNameMap.TryGetValue(raw.Trend ?? string.Empty, out var trend);

        return new GlucoseReading
        {
            Value = raw.Value,
            Trend = trend,
            Date = date,
            TrendRate = raw.TrendRate
        };
    }

    /// <summary>
    /// Parses a Dexcom WT timestamp of the form "Date(1234567890000)" into a UTC DateTime.
    /// </summary>
    private static DateTime ParseWtTimestamp(string? wt)
    {
        if (wt is null) return DateTime.UtcNow;

        // Extract the numeric milliseconds from "Date(ms)"
        var match = _wtRegex.Match(wt);
        if (!match.Success || !long.TryParse(match.Value, out var ms))
            return DateTime.UtcNow;

        return DateTimeOffset.FromUnixTimeMilliseconds(ms).UtcDateTime;
    }

    // -------------------------------------------------------------------------
    // Internal DTO for JSON deserialization
    // -------------------------------------------------------------------------

    private sealed class DexcomRawReading
    {
        [JsonPropertyName("WT")]
        public string? WT { get; set; }

        [JsonPropertyName("Value")]
        public int Value { get; set; }

        [JsonPropertyName("Trend")]
        public string? Trend { get; set; }

        [JsonPropertyName("TrendRate")]
        public double? TrendRate { get; set; }
    }
}
