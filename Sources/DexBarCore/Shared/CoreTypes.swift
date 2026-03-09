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
