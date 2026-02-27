import Testing
import SwiftUI
@testable import DexBar

// MARK: - GlucoseTrend

struct GlucoseTrendTests {
    @Test func arrows() {
        #expect(GlucoseTrend.doubleUp.arrow == "⇈")
        #expect(GlucoseTrend.singleUp.arrow == "↑")
        #expect(GlucoseTrend.fortyFiveUp.arrow == "↗")
        #expect(GlucoseTrend.flat.arrow == "→")
        #expect(GlucoseTrend.fortyFiveDown.arrow == "↘")
        #expect(GlucoseTrend.singleDown.arrow == "↓")
        #expect(GlucoseTrend.doubleDown.arrow == "⇊")
        #expect(GlucoseTrend.notComputable.arrow == "?")
        #expect(GlucoseTrend.rateOutOfRange.arrow == "?")
    }

    @Test func descriptions() {
        #expect(GlucoseTrend.doubleUp.description == "rising quickly")
        #expect(GlucoseTrend.singleUp.description == "rising")
        #expect(GlucoseTrend.flat.description == "steady")
        #expect(GlucoseTrend.singleDown.description == "falling")
        #expect(GlucoseTrend.doubleDown.description == "falling quickly")
    }

    @Test func isRisingFast_onlyDoubleUpAndSingleUp() {
        #expect(GlucoseTrend.doubleUp.isRisingFast)
        #expect(GlucoseTrend.singleUp.isRisingFast)
        #expect(!GlucoseTrend.fortyFiveUp.isRisingFast)
        #expect(!GlucoseTrend.flat.isRisingFast)
        #expect(!GlucoseTrend.singleDown.isRisingFast)
    }

    @Test func isDroppingFast_onlyDoubleDownAndSingleDown() {
        #expect(GlucoseTrend.doubleDown.isDroppingFast)
        #expect(GlucoseTrend.singleDown.isDroppingFast)
        #expect(!GlucoseTrend.fortyFiveDown.isDroppingFast)
        #expect(!GlucoseTrend.flat.isDroppingFast)
        #expect(!GlucoseTrend.singleUp.isDroppingFast)
    }

    @Test func rawValues_matchDexcomAPI() {
        #expect(GlucoseTrend(rawValue: 0) == GlucoseTrend.none)
        #expect(GlucoseTrend(rawValue: 1) == .doubleUp)
        #expect(GlucoseTrend(rawValue: 4) == .flat)
        #expect(GlucoseTrend(rawValue: 7) == .doubleDown)
        #expect(GlucoseTrend(rawValue: 9) == .rateOutOfRange)
    }
}

// MARK: - GlucoseReading

struct GlucoseReadingTests {
    private func reading(value: Int, trend: GlucoseTrend = .flat) -> GlucoseReading {
        GlucoseReading(value: value, trend: trend, date: Date())
    }

    @Test func mmolConversion() {
        let r = reading(value: 180)
        #expect(abs(r.mmolL - 10.0) < 0.01)
    }

    @Test func mmolConversion_lowValue() {
        let r = reading(value: 72)
        #expect(abs(r.mmolL - 4.0) < 0.01)
    }

    @Test func displayValue_mgdL() {
        #expect(reading(value: 94).displayValue(unit: .mgdL) == "94")
        #expect(reading(value: 180).displayValue(unit: .mgdL) == "180")
    }

    @Test func displayValue_mmolL() {
        // 180 mg/dL = 10.0 mmol/L
        #expect(reading(value: 180).displayValue(unit: .mmolL) == "10.0")
        // 126 mg/dL = 7.0 mmol/L
        #expect(reading(value: 126).displayValue(unit: .mmolL) == "7.0")
    }

    @Test func menuBarLabel_includesTrendArrow() {
        let r = reading(value: 94, trend: .flat)
        #expect(r.menuBarLabel(unit: .mgdL) == "94 →")
    }

    @Test func menuBarLabel_mmolL() {
        let r = reading(value: 180, trend: .singleUp)
        #expect(r.menuBarLabel(unit: .mmolL) == "10.0 ↑")
    }
}

// MARK: - DexcomRawReading parsing

struct DexcomRawReadingTests {
    @Test func parsesValidReading() throws {
        let raw = DexcomRawReading(
            wt: "Date(1691455258000)",
            value: 85,
            trend: "Flat",
            trendRate: nil
        )
        let reading = try #require(raw.toGlucoseReading())
        #expect(reading.value == 85)
        #expect(reading.trend == .flat)
        #expect(abs(reading.date.timeIntervalSince1970 - 1691455258.0) < 1.0)
    }

    @Test func parsesAllTrendStrings() {
        let trends: [(String, GlucoseTrend)] = [
            ("DoubleUp", .doubleUp),
            ("SingleUp", .singleUp),
            ("FortyFiveUp", .fortyFiveUp),
            ("Flat", .flat),
            ("FortyFiveDown", .fortyFiveDown),
            ("SingleDown", .singleDown),
            ("DoubleDown", .doubleDown),
            ("NotComputable", .notComputable),
            ("RateOutOfRange", .rateOutOfRange),
        ]
        for (string, expected) in trends {
            let raw = DexcomRawReading(wt: "Date(1691455258000)", value: 100, trend: string, trendRate: nil)
            #expect(raw.toGlucoseReading()?.trend == expected, "Failed for trend string: \(string)")
        }
    }

    @Test func unknownTrendDefaultsToNone() {
        let raw = DexcomRawReading(wt: "Date(1691455258000)", value: 100, trend: "Unknown", trendRate: nil)
        #expect(raw.toGlucoseReading()?.trend == GlucoseTrend.none)
    }

    @Test func returnsNilForMalformedTimestamp() {
        let raw = DexcomRawReading(wt: "not-a-date", value: 100, trend: "Flat", trendRate: nil)
        #expect(raw.toGlucoseReading() == nil)
    }

    @Test func returnsNilForMissingParentheses() {
        let raw = DexcomRawReading(wt: "1691455258000", value: 100, trend: "Flat", trendRate: nil)
        #expect(raw.toGlucoseReading() == nil)
    }
}

// MARK: - GlucoseMonitor.readingColor

@MainActor
struct GlucoseMonitorColorTests {
    private func monitor(value: Int) -> GlucoseMonitor {
        let m = GlucoseMonitor()
        m.alertLowThresholdMgdL = 70
        m.alertHighThresholdMgdL = 180
        m.currentReading = GlucoseReading(value: value, trend: .flat, date: Date())
        return m
    }

    @Test func greenWhenInRange() {
        // 90–160 is safely inside both 20-point warning margins
        #expect(monitor(value: 120).readingColor == Color.green)
    }

    @Test func redWhenAboveHighThreshold() {
        #expect(monitor(value: 181).readingColor == Color.red)
    }

    @Test func redWhenBelowLowThreshold() {
        #expect(monitor(value: 69).readingColor == Color.red)
    }

    @Test func yellowWhenApproachingHigh() {
        // 160 < value <= 180 → warning zone
        #expect(monitor(value: 170).readingColor == Color.yellow)
    }

    @Test func yellowWhenApproachingLow() {
        // 70 <= value < 90 → warning zone
        #expect(monitor(value: 75).readingColor == Color.yellow)
    }

    @Test func primaryWhenNoReading() {
        let m = GlucoseMonitor()
        #expect(m.readingColor == Color.primary)
    }
}
