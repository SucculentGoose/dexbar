// .pragma library marks this as a shared singleton — all QML files share one instance.
.pragma library

// ─── Constants ─────────────────────────────────────────────────────────────

const BASE_URLS = {
    "US":         "https://share2.dexcom.com/ShareWebServices/Services",
    "Outside US": "https://shareous1.dexcom.com/ShareWebServices/Services",
    "Japan":      "https://shareous1.dexcom.jp/ShareWebServices/Services"
}

const APP_ID = "d8665ade-9673-4e27-9ff6-92db4ce13d13"

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

// Returns CSS color string matching DexBar thresholds from GlucoseMonitor.swift
function glucoseColor(mgdl) {
    if (mgdl < 55)   return "#FF3B30"  // urgent low  — red
    if (mgdl < 70)   return "#FF9500"  // low         — orange
    if (mgdl <= 180) return "#34C759"  // in range    — green
    if (mgdl <= 250) return "#FFCC00"  // high        — yellow
    return "#FF3B30"                    // urgent high — red
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
    return minutesAgo(timestampMs) > 15
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
            onError("Invalid username or password.")
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
            onError("Invalid credentials.")
            return
        }
        onSuccess(sessionId)
    }, onError)
}

// Fetch up to maxCount readings from the last 24h.
// Calls onSuccess([{ value, trend, trendRate, timestampMs }]) or onError(string).
function fetchReadings(baseUrl, sessionId, maxCount, onSuccess, onError) {
    const url = baseUrl
        + "/Publisher/ReadPublisherLatestGlucoseValues"
        + "?sessionId=" + encodeURIComponent(sessionId)
        + "&minutes=1440"
        + "&maxCount=" + String(maxCount)
    const xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status === 500) { onError("Session expired."); return }
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
        if (xhr.status === 500) { onError("Invalid credentials."); return }
        if (xhr.status < 200 || xhr.status >= 300) { onError("HTTP " + xhr.status); return }
        onSuccess(xhr.responseText)
    }
    xhr.open("POST", url)
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.setRequestHeader("Accept", "application/json")
    xhr.send(body)
}
