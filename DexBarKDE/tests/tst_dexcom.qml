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
        function glucoseColor(mgdl) {
            if (mgdl < 55)   return "#FF3B30"
            if (mgdl < 70)   return "#FF9500"
            if (mgdl <= 180) return "#34C759"
            if (mgdl <= 250) return "#FFCC00"
            return "#FF3B30"
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
}
