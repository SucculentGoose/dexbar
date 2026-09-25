import Foundation

// MARK: - Monitor State

public enum MonitorState: Equatable, Sendable {
    case idle
    case loading
    case connected
    case error(String)

    public var statusText: String {
        switch self {
        case .idle: "Not connected"
        case .loading: "Loading…"
        case .connected: "Connected"
        case .error(let msg): msg
        }
    }
}

// MARK: - Time in Range

public struct TiRStats: Sendable {
    public let lowCount: Int
    public let inRangeCount: Int
    public let highCount: Int
    public let total: Int

    public init(lowCount: Int, inRangeCount: Int, highCount: Int, total: Int) {
        self.lowCount = lowCount
        self.inRangeCount = inRangeCount
        self.highCount = highCount
        self.total = total
    }

    public var lowPct: Double     { total > 0 ? Double(lowCount)     / Double(total) * 100 : 0 }
    public var inRangePct: Double { total > 0 ? Double(inRangeCount) / Double(total) * 100 : 0 }
    public var highPct: Double    { total > 0 ? Double(highCount)    / Double(total) * 100 : 0 }
}

// MARK: - Time Ranges

public enum StatsTimeRange: String, CaseIterable, Sendable {
    case twoDays      = "2d"
    case sevenDays    = "7d"
    case fourteenDays = "14d"
    case thirtyDays   = "30d"
    case ninetyDays   = "90d"

    public var interval: TimeInterval {
        switch self {
        case .twoDays:      2  * 86400
        case .sevenDays:    7  * 86400
        case .fourteenDays: 14 * 86400
        case .thirtyDays:   30 * 86400
        case .ninetyDays:   90 * 86400
        }
    }
}

public enum TimeRange: String, CaseIterable, Sendable {
    case threeHours  = "3h"
    case sixHours    = "6h"
    case twelveHours = "12h"
    case day         = "24h"

    public var interval: TimeInterval {
        switch self {
        case .threeHours:  3  * 3600
        case .sixHours:    6  * 3600
        case .twelveHours: 12 * 3600
        case .day:         24 * 3600
        }
    }
}

// MARK: - Reading history helpers

public enum ReadingHistory {
    /// Dexcom produces one reading every 5 minutes.
    public static let readingInterval: TimeInterval = 5 * 60
    /// Most readings the Share API returns in one request (24 h).
    public static let maxFetchCount = 288
    /// Two readings further apart than this are not compared for a delta
    /// (allows one missed reading plus jitter).
    public static let maxDeltaGap: TimeInterval = 11 * 60

    /// How many readings to request so that the gap since `lastReading`
    /// is backfilled (e.g. after sleep), capped at the API maximum.
    public static func fetchCount(since lastReading: Date?, now: Date = Date()) -> Int {
        guard let lastReading else { return maxFetchCount }
        let missed = Int(now.timeIntervalSince(lastReading) / readingInterval) + 2
        return min(max(missed, 2), maxFetchCount)
    }

    /// `newer.value - older.value`, or nil when the readings are too far apart
    /// for the difference to be meaningful.
    public static func delta(from older: GlucoseReading, to newer: GlucoseReading) -> Int? {
        guard newer.date.timeIntervalSince(older.date) <= maxDeltaGap else { return nil }
        return newer.value - older.value
    }

    public static func formatDelta(_ delta: Int, unit: GlucoseUnit) -> String {
        switch unit {
        case .mgdL:
            return delta >= 0 ? "+\(delta)" : "\(delta)"
        case .mmolL:
            let d = Double(delta) / 18.0
            return d >= 0 ? String(format: "+%.1f", d) : String(format: "%.1f", d)
        }
    }
}

extension Array where Element == GlucoseReading {
    /// Readings newer than `interval` ago. Assumes the array is sorted newest-first,
    /// so it stops at the first older reading instead of scanning the whole history.
    public func newest(within interval: TimeInterval, now: Date = Date()) -> ArraySlice<GlucoseReading> {
        let cutoff = now.addingTimeInterval(-interval)
        return prefix { $0.date >= cutoff }
    }
}

extension TiRStats {
    /// Single-pass count of low / in-range / high readings.
    public init<C: Collection>(readings: C, lowThreshold: Double, highThreshold: Double)
    where C.Element == GlucoseReading {
        var low = 0, high = 0
        for r in readings {
            let v = Double(r.value)
            if v < lowThreshold { low += 1 } else if v > highThreshold { high += 1 }
        }
        self.init(lowCount: low, inRangeCount: readings.count - low - high, highCount: high, total: readings.count)
    }
}

extension ReadingHistory {
    /// Glucose Management Indicator — estimated HbA1c % from mean glucose.
    /// Formula: GMI = 3.31 + 0.02392 × mean_mg_dL
    public static func gmi<C: Collection>(_ readings: C) -> Double? where C.Element == GlucoseReading {
        guard !readings.isEmpty else { return nil }
        let mean = Double(readings.reduce(0) { $0 + $1.value }) / Double(readings.count)
        return 3.31 + 0.02392 * mean
    }
}
