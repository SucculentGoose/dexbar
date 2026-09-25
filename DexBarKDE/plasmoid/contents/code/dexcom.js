// .pragma library marks this as a shared singleton — all QML files share one instance.
.pragma library

// ─── Constants ─────────────────────────────────────────────────────────────

const BASE_URLS = {
    "US":         "https://share2.dexcom.com/ShareWebServices/Services",
    "Outside US": "https://shareous1.dexcom.com/ShareWebServices/Services",
    "Japan":      "https://shareous1.dexcom.jp/ShareWebServices/Services"
}

const APP_ID = "d8665ade-9673-4e27-9ff6-92db4ce13d13"

// Error strings passed to onError; main.qml branches on these.
const ERR_INVALID_CREDENTIALS = "Invalid credentials."
const ERR_SESSION_EXPIRED     = "Session expired."

const STALE_MINUTES = 20
const READING_INTERVAL_MS = 5 * 60 * 1000
const MAX_FETCH_COUNT = 288
// Readings further apart than this are not compared for a delta
// (allows one missed reading plus jitter).
const MAX_DELTA_GAP_MS = 11 * 60 * 1000

const TREND_MAP = {
    "DoubleUp":       { arrow: "⇈", description: "rising quickly" },
    "SingleUp":       { arrow: "↑", description: "rising" },
    "FortyFiveUp":    { arrow: "↗", description: "rising slightly" },
    "Flat":           { arrow: "→", description: "steady" },
    "FortyFiveDown":  { arrow: "↘", description: "falling slightly" },
    "SingleDown":     { arrow: "↓", description: "falling" },
    "DoubleDown":     { arrow: "⇊", description: "falling quickly" },
    "NotComputable":  { arrow: "?", description: "not computable" },
    "RateOutOfRange": { arrow: "?", description: "out of range" }
}

// ─── Pure helper functions (testable with qmltestrunner) ───────────────────

function trendArrow(trend) {
    return (TREND_MAP[trend] || { arrow: "?" }).arrow
}

function trendDescription(trend) {
    return (TREND_MAP[trend] || { description: "unknown" }).description
}

// Returns CSS color string for a reading. `t` is the optional configured thresholds
// { urgentLow, low, high, urgentHigh } in mg/dL; defaults match the other platforms.
function glucoseColor(mgdl, t) {
    const urgentLow  = t ? t.urgentLow  : 55
    const low        = t ? t.low        : 70
    const high       = t ? t.high       : 180
    const urgentHigh = t ? t.urgentHigh : 250
    if (mgdl < urgentLow)   return "#FF3B30"  // urgent low  — red
    if (mgdl < low)         return "#FF9500"  // low         — orange
    if (mgdl <= high)       return "#34C759"  // in range    — green
    if (mgdl <= urgentHigh) return "#FFCC00"  // high        — yellow
    return "#FF3B30"                          // urgent high — red
}

// Parse Dexcom WT timestamp: "Date(1234567890000)" → milliseconds since epoch, or null
function parseWt(wt) {
    if (typeof wt !== "string") return null
    const match = wt.match(/Date\((\d+)\)/)
    if (!match) return null
    return parseInt(match[1], 10)
}

// Returns "94" (mg/dL) or "5.2" (mmol/L)
function displayValue(mgdl, useMmol) {
    if (useMmol) return (mgdl / 18.0).toFixed(1)
    return String(mgdl)
}

function displayUnit(useMmol) {
    return useMmol ? "mmol/L" : "mg/dL"
}

// Returns integer minutes since the given UTC millisecond timestamp
function minutesAgo(timestampMs) {
    return Math.round((Date.now() - timestampMs) / 60000)
}

function isStale(timestampMs) {
    return minutesAgo(timestampMs) > STALE_MINUTES
}

// newer.value - older.value, or null when the readings are too far apart to compare
function readingDelta(older, newer) {
    if (newer.timestampMs - older.timestampMs > MAX_DELTA_GAP_MS) return null
    return newer.value - older.value
}

// How many readings to request so the gap since lastReadingMs (e.g. after sleep)
// is backfilled, capped at the API maximum.
function fetchCountSince(lastReadingMs, nowMs) {
    if (!lastReadingMs) return MAX_FETCH_COUNT
    const missed = Math.floor((nowMs - lastReadingMs) / READING_INTERVAL_MS) + 2
    return Math.min(Math.max(missed, 2), MAX_FETCH_COUNT)
}

// Dexcom reports both bad credentials and transient faults as HTTP 500; the body's
// Code field tells them apart. Anything unrecognised is treated as retryable.
function serverErrorMessage(responseText) {
    let code = null
    try { code = JSON.parse(responseText).Code } catch(e) {}
    if (code === "SessionIdNotFound" || code === "SessionNotValid") return ERR_SESSION_EXPIRED
    if (typeof code === "string" && (code.indexOf("Password") !== -1 || code.indexOf("AccountNotFound") !== -1))
        return ERR_INVALID_CREDENTIALS
    return "Dexcom server error (HTTP 500)."
}

// Merge incoming readings into history (both newest-first), dedupe by timestampMs,
// sort newest-first, and cap the result length. Never mutates its inputs.
function mergeReadings(history, incoming, cap) {
    const seen = {}
    for (let i = 0; i < history.length; i++) {
        seen[history[i].timestampMs] = true
    }
    const merged = history.slice()
    for (let i = 0; i < incoming.length; i++) {
        const r = incoming[i]
        if (!seen[r.timestampMs]) {
            seen[r.timestampMs] = true
            merged.push(r)
        }
    }
    merged.sort(function(a, b) { return b.timestampMs - a.timestampMs })
    return merged.slice(0, cap)
}

// ─── API calls (callback-based; use XMLHttpRequest internally) ─────────────

// Step 1 of auth: username → accountId
function fetchAccountId(baseUrl, username, password, onSuccess, onError) {
    const body = JSON.stringify({
        accountName: username,
        password: password,
        applicationId: APP_ID
    })
    _post(baseUrl + "/General/AuthenticatePublisherAccount", body, function(text) {
        let accountId
        try { accountId = JSON.parse(text) } catch(e) { onError("Parse error"); return }
        if (!accountId || accountId === "00000000-0000-0000-0000-000000000000") {
            onError(ERR_INVALID_CREDENTIALS)
            return
        }
        onSuccess(accountId)
    }, onError)
}

// Step 2 of auth: accountId → sessionId
function fetchSessionId(baseUrl, accountId, password, onSuccess, onError) {
    const body = JSON.stringify({
        accountId: accountId,
        password: password,
        applicationId: APP_ID
    })
    _post(baseUrl + "/General/LoginPublisherAccountById", body, function(text) {
        let sessionId
        try { sessionId = JSON.parse(text) } catch(e) { onError("Parse error"); return }
        if (!sessionId || sessionId === "00000000-0000-0000-0000-000000000000") {
            onError(ERR_INVALID_CREDENTIALS)
            return
        }
        onSuccess(sessionId)
    }, onError)
}

// Fetch up to maxCount readings from the last 24h.
// Calls onSuccess([{ value, trend, trendRate, timestampMs }]) or onError(string).
function fetchReadings(baseUrl, sessionId, maxCount, onSuccess, onError, minutes) {
    const mins = minutes || 1440
    const url = baseUrl
        + "/Publisher/ReadPublisherLatestGlucoseValues"
        + "?sessionId=" + encodeURIComponent(sessionId)
        + "&minutes=" + String(mins)
        + "&maxCount=" + String(maxCount)
    const xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status === 500) { onError(serverErrorMessage(xhr.responseText)); return }
        if (xhr.status < 200 || xhr.status >= 300) { onError("HTTP " + xhr.status); return }
        let raw
        try { raw = JSON.parse(xhr.responseText) } catch(e) { onError("Parse error"); return }
        const readings = raw
            .map(function(r) {
                return {
                    value:       r.Value,
                    trend:       r.Trend,
                    trendRate:   r.TrendRate || null,
                    timestampMs: parseWt(r.WT)
                }
            })
            .filter(function(r) { return r.timestampMs !== null })
        if (readings.length === 0) { onError("No recent readings."); return }
        onSuccess(readings)
    }
    xhr.open("GET", url)
    xhr.setRequestHeader("Accept", "application/json")
    xhr.send()
}

// ─── Internal ──────────────────────────────────────────────────────────────

function _post(url, body, onSuccess, onError) {
    const xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status === 500) { onError(serverErrorMessage(xhr.responseText)); return }
        if (xhr.status < 200 || xhr.status >= 300) { onError("HTTP " + xhr.status); return }
        onSuccess(xhr.responseText)
    }
    xhr.open("POST", url)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.setRequestHeader("Accept", "application/json")
    xhr.send(body)
}
