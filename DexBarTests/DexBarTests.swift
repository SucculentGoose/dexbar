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
        GlucoseReading(value: value, trend: trend, date: Date(), trendRate: nil)
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

/// A monitor that never touches the user's real settings, reading history, or Dexcom account.
@MainActor
private func isolatedMonitor() -> GlucoseMonitor {
    let suite = "com.dexbar.app.tests"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GlucoseMonitor(defaults: defaults, readingsURL: nil, autoConnect: false)
}

@MainActor
struct GlucoseMonitorColorTests {
    private func monitor(value: Int) -> GlucoseMonitor {
        let m = isolatedMonitor()
        m.alertUrgentLowThresholdMgdL = 55
        m.alertLowThresholdMgdL = 70
        m.alertHighThresholdMgdL = 180
        m.alertUrgentHighThresholdMgdL = 250
        // Assign distinct sentinel colors so each zone is unambiguous
        m.colorUrgentLow = .purple
        m.colorLow = .orange
        m.colorInRange = .green
        m.colorHigh = .yellow
        m.colorUrgentHigh = .red
        m.currentReading = GlucoseReading(value: value, trend: .flat, date: Date(), trendRate: nil)
        return m
    }

    @Test func urgentLowColor() {
        #expect(monitor(value: 54).readingColor == .purple)
    }

    @Test func lowColor() {
        #expect(monitor(value: 60).readingColor == .orange)
    }

    @Test func inRangeColor() {
        #expect(monitor(value: 120).readingColor == .green)
    }

    @Test func highColor() {
        #expect(monitor(value: 181).readingColor == .yellow)
    }

    @Test func urgentHighColor() {
        #expect(monitor(value: 251).readingColor == .red)
    }

    @Test func primaryWhenNoReading() {
        let m = isolatedMonitor()
        #expect(m.readingColor == Color.primary)
    }
}

// MARK: - ReadingHistory

struct ReadingHistoryTests {
    private func reading(_ value: Int, minutesAgo: Double) -> GlucoseReading {
        GlucoseReading(value: value, trend: .flat, date: Date().addingTimeInterval(-minutesAgo * 60), trendRate: nil)
    }

    @Test func deltaBetweenConsecutiveReadings() {
        #expect(ReadingHistory.delta(from: reading(100, minutesAgo: 5), to: reading(104, minutesAgo: 0)) == 4)
    }

    @Test func deltaIsNilAcrossAGap() {
        #expect(ReadingHistory.delta(from: reading(100, minutesAgo: 180), to: reading(180, minutesAgo: 0)) == nil)
    }

    @Test func fetchCountCoversGap() {
        let now = Date()
        #expect(ReadingHistory.fetchCount(since: now.addingTimeInterval(-5 * 60), now: now) == 3)
        #expect(ReadingHistory.fetchCount(since: now.addingTimeInterval(-60 * 60), now: now) == 14)
        #expect(ReadingHistory.fetchCount(since: now.addingTimeInterval(-3 * 86400), now: now) == 288)
        #expect(ReadingHistory.fetchCount(since: nil, now: now) == 288)
    }

    @Test func newestWithinStopsAtCutoff() {
        let readings = [reading(1, minutesAgo: 0), reading(2, minutesAgo: 30), reading(3, minutesAgo: 300)]
        #expect(readings.newest(within: 60 * 60).map(\.value) == [1, 2])
    }

    @Test func tirStatsSinglePass() {
        let readings = [reading(50, minutesAgo: 0), reading(120, minutesAgo: 5), reading(200, minutesAgo: 10)]
        let stats = TiRStats(readings: readings, lowThreshold: 70, highThreshold: 180)
        #expect(stats.lowCount == 1 && stats.inRangeCount == 1 && stats.highCount == 1 && stats.total == 3)
    }

    @Test func formatDelta() {
        #expect(ReadingHistory.formatDelta(3, unit: .mgdL) == "+3")
        #expect(ReadingHistory.formatDelta(-4, unit: .mgdL) == "-4")
        #expect(ReadingHistory.formatDelta(-9, unit: .mmolL) == "-0.5")
    }
}
