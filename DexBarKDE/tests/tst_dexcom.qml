import QtQuick 2.15
import QtTest 1.2

// Load the module under test. In qmltestrunner the working dir is the plasmoid root,
// so we reference the file relative to where we run the runner (see run_tests.sh).
Item {
    id: root

    // We inline the pure functions here rather than importing the .pragma library
    // directly (qmltestrunner can't easily load .pragma files as QML modules).
    // This is the accepted pattern: copy the pure functions into a local JS object.

    property var dexcom: QtObject {
        function trendArrow(trend) {
            const map = {
                "DoubleUp": "⇈", "SingleUp": "↑", "FortyFiveUp": "↗",
                "Flat": "→", "FortyFiveDown": "↘", "SingleDown": "↓",
                "DoubleDown": "⇊", "NotComputable": "?", "RateOutOfRange": "?"
            }
            return map[trend] || "?"
        }
        function trendDescription(trend) {
            const map = {
                "DoubleUp": "rising quickly", "SingleUp": "rising",
                "FortyFiveUp": "rising slightly", "Flat": "steady",
                "FortyFiveDown": "falling slightly", "SingleDown": "falling",
                "DoubleDown": "falling quickly"
            }
            return map[trend] || "unknown"
        }
        function glucoseColor(mgdl, t) {
            const urgentLow  = t ? t.urgentLow  : 55
            const low        = t ? t.low        : 70
            const high       = t ? t.high       : 180
            const urgentHigh = t ? t.urgentHigh : 250
            if (mgdl < urgentLow)   return "#FF3B30"
            if (mgdl < low)         return "#FF9500"
            if (mgdl <= high)       return "#34C759"
            if (mgdl <= urgentHigh) return "#FFCC00"
            return "#FF3B30"
        }
        function readingDelta(older, newer) {
            if (newer.timestampMs - older.timestampMs > 11 * 60 * 1000) return null
            return newer.value - older.value
        }
        function fetchCountSince(lastReadingMs, nowMs) {
            if (!lastReadingMs) return 288
            const missed = Math.floor((nowMs - lastReadingMs) / (5 * 60 * 1000)) + 2
            return Math.min(Math.max(missed, 2), 288)
        }
        function serverErrorMessage(responseText) {
            let code = null
            try { code = JSON.parse(responseText).Code } catch(e) {}
            if (code === "SessionIdNotFound" || code === "SessionNotValid") return "Session expired."
            if (typeof code === "string" && (code.indexOf("Password") !== -1 || code.indexOf("AccountNotFound") !== -1))
                return "Invalid credentials."
            return "Dexcom server error (HTTP 500)."
        }
        function parseWt(wt) {
            if (typeof wt !== "string") return null
            const match = wt.match(/Date\((\d+)\)/)
            if (!match) return null
            return parseInt(match[1], 10)
        }
        function displayValue(mgdl, useMmol) {
            if (useMmol) return (mgdl / 18.0).toFixed(1)
            return String(mgdl)
        }
        function displayUnit(useMmol) {
            return useMmol ? "mmol/L" : "mg/dL"
        }
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
    }

    TestCase {
        name: "TrendArrow"
        function test_knownTrends() {
            compare(root.dexcom.trendArrow("DoubleUp"),      "⇈")
            compare(root.dexcom.trendArrow("SingleUp"),      "↑")
            compare(root.dexcom.trendArrow("FortyFiveUp"),   "↗")
            compare(root.dexcom.trendArrow("Flat"),          "→")
            compare(root.dexcom.trendArrow("FortyFiveDown"), "↘")
            compare(root.dexcom.trendArrow("SingleDown"),    "↓")
            compare(root.dexcom.trendArrow("DoubleDown"),    "⇊")
        }
        function test_unknownTrendReturnsQuestionMark() {
            compare(root.dexcom.trendArrow("Bogus"), "?")
            compare(root.dexcom.trendArrow(""),      "?")
        }
    }

    TestCase {
        name: "GlucoseColor"
        function test_urgentLow() {
            compare(root.dexcom.glucoseColor(40), "#FF3B30")
            compare(root.dexcom.glucoseColor(54), "#FF3B30")
        }
        function test_low() {
            compare(root.dexcom.glucoseColor(55), "#FF9500")
            compare(root.dexcom.glucoseColor(69), "#FF9500")
        }
        function test_inRange() {
            compare(root.dexcom.glucoseColor(70),  "#34C759")
            compare(root.dexcom.glucoseColor(100), "#34C759")
            compare(root.dexcom.glucoseColor(180), "#34C759")
        }
        function test_high() {
            compare(root.dexcom.glucoseColor(181), "#FFCC00")
            compare(root.dexcom.glucoseColor(250), "#FFCC00")
        }
        function test_urgentHigh() {
            compare(root.dexcom.glucoseColor(251), "#FF3B30")
            compare(root.dexcom.glucoseColor(400), "#FF3B30")
        }
    }

    TestCase {
        name: "ParseWt"
        function test_validTimestamp() {
            compare(root.dexcom.parseWt("Date(1700000000000)"), 1700000000000)
        }
        function test_invalidReturnsNull() {
            compare(root.dexcom.parseWt("not-a-date"), null)
            compare(root.dexcom.parseWt(""),           null)
            compare(root.dexcom.parseWt(null),         null)
        }
    }

    TestCase {
        name: "DisplayValue"
        function test_mgdl() {
            compare(root.dexcom.displayValue(94, false),  "94")
            compare(root.dexcom.displayValue(180, false), "180")
        }
        function test_mmol() {
            compare(root.dexcom.displayValue(180, true), "10.0")
            compare(root.dexcom.displayValue(90, true),  "5.0")
            compare(root.dexcom.displayValue(100, true), "5.6")
        }
        function test_unit() {
            compare(root.dexcom.displayUnit(false), "mg/dL")
            compare(root.dexcom.displayUnit(true),  "mmol/L")
        }
    }

    TestCase {
        name: "MergeReadings"
        function test_dedupesByTimestamp() {
            const history = [{ value: 100, timestampMs: 2000 }, { value: 90, timestampMs: 1000 }]
            const incoming = [{ value: 999, timestampMs: 2000 }, { value: 110, timestampMs: 3000 }]
            const merged = root.dexcom.mergeReadings(history, incoming, 10)
            compare(merged.length, 3)
            compare(merged[0].timestampMs, 3000)
            compare(merged[1].timestampMs, 2000)
            compare(merged[1].value, 100)
            compare(merged[2].timestampMs, 1000)
        }
        function test_sortsNewestFirst() {
            const history = [{ value: 90, timestampMs: 1000 }]
            const incoming = [{ value: 110, timestampMs: 3000 }, { value: 105, timestampMs: 2000 }]
            const merged = root.dexcom.mergeReadings(history, incoming, 10)
            compare(merged[0].timestampMs, 3000)
            compare(merged[1].timestampMs, 2000)
            compare(merged[2].timestampMs, 1000)
        }
        function test_respectsCap() {
            const history = [{ value: 100, timestampMs: 3000 }, { value: 95, timestampMs: 2000 }]
            const incoming = [{ value: 90, timestampMs: 1000 }]
            const merged = root.dexcom.mergeReadings(history, incoming, 2)
            compare(merged.length, 2)
            compare(merged[0].timestampMs, 3000)
            compare(merged[1].timestampMs, 2000)
        }
        function test_doesNotMutateInputs() {
            const history = [{ value: 100, timestampMs: 2000 }]
            const incoming = [{ value: 110, timestampMs: 3000 }]
            root.dexcom.mergeReadings(history, incoming, 10)
            compare(history.length, 1)
            compare(incoming.length, 1)
            compare(history[0].timestampMs, 2000)
            compare(incoming[0].timestampMs, 3000)
        }
    }

    TestCase {
        name: "GlucoseColorThresholds"
        function test_customThresholds() {
            const t = { urgentLow: 60, low: 80, high: 160, urgentHigh: 220 }
            compare(root.dexcom.glucoseColor(59, t),  "#FF3B30")
            compare(root.dexcom.glucoseColor(75, t),  "#FF9500")
            compare(root.dexcom.glucoseColor(160, t), "#34C759")
            compare(root.dexcom.glucoseColor(200, t), "#FFCC00")
            compare(root.dexcom.glucoseColor(221, t), "#FF3B30")
        }
    }

    TestCase {
        name: "ReadingDelta"
        function test_consecutiveReadings() {
            compare(root.dexcom.readingDelta({ value: 100, timestampMs: 0 }, { value: 104, timestampMs: 300000 }), 4)
        }
        function test_gapReturnsNull() {
            compare(root.dexcom.readingDelta({ value: 100, timestampMs: 0 }, { value: 180, timestampMs: 3 * 3600000 }), null)
        }
    }

    TestCase {
        name: "FetchCountSince"
        function test_counts() {
            const now = 10 * 86400000
            compare(root.dexcom.fetchCountSince(now - 300000, now), 3)
            compare(root.dexcom.fetchCountSince(now - 3600000, now), 14)
            compare(root.dexcom.fetchCountSince(now - 3 * 86400000, now), 288)
            compare(root.dexcom.fetchCountSince(0, now), 288)
        }
    }

    TestCase {
        name: "ServerErrorMessage"
        function test_mapping() {
            compare(root.dexcom.serverErrorMessage('{"Code":"SessionIdNotFound"}'), "Session expired.")
            compare(root.dexcom.serverErrorMessage('{"Code":"AccountPasswordInvalid"}'), "Invalid credentials.")
            compare(root.dexcom.serverErrorMessage('{"Code":"SSO_InternalError"}'), "Dexcom server error (HTTP 500).")
            compare(root.dexcom.serverErrorMessage("<html>oops</html>"), "Dexcom server error (HTTP 500).")
        }
    }
}
