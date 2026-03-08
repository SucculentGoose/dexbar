import Foundation

// Trend values matching Dexcom Share API integers
enum GlucoseTrend: Int, Codable, Sendable {
    case none = 0
    case doubleUp = 1
    case singleUp = 2
    case fortyFiveUp = 3
    case flat = 4
    case fortyFiveDown = 5
    case singleDown = 6
    case doubleDown = 7
    case notComputable = 8
    case rateOutOfRange = 9

    var arrow: String {
        switch self {
        case .doubleUp: "⇈"
        case .singleUp: "↑"
        case .fortyFiveUp: "↗"
        case .flat: "→"
        case .fortyFiveDown: "↘"
        case .singleDown: "↓"
        case .doubleDown: "⇊"
        default: "?"
        }
    }

    var description: String {
        switch self {
        case .doubleUp: "rising quickly"
        case .singleUp: "rising"
        case .fortyFiveUp: "rising slightly"
        case .flat: "steady"
        case .fortyFiveDown: "falling slightly"
        case .singleDown: "falling"
        case .doubleDown: "falling quickly"
        case .notComputable: "not computable"
        case .rateOutOfRange: "out of range"
        case .none: "—"
        }
    }

    var isRisingFast: Bool { self == .doubleUp || self == .singleUp }
    var isDroppingFast: Bool { self == .doubleDown || self == .singleDown }
}

struct GlucoseReading: Identifiable, Codable, Sendable {
    let id: UUID
    let value: Int          // always stored as mg/dL
    let trend: GlucoseTrend
    let date: Date
    /// Rate of change in mg/dL per minute, as provided by the Dexcom API.
    let trendRate: Double?

    init(value: Int, trend: GlucoseTrend, date: Date, trendRate: Double?) {
        self.id = UUID()
        self.value = value
        self.trend = trend
        self.date = date
        self.trendRate = trendRate
    }

    // Exclude `id` from disk storage — regenerate on decode
    enum CodingKeys: String, CodingKey { case value, trend, date, trendRate }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = UUID()
        value     = try c.decode(Int.self,          forKey: .value)
        trend     = try c.decode(GlucoseTrend.self, forKey: .trend)
        date      = try c.decode(Date.self,          forKey: .date)
        trendRate = try c.decodeIfPresent(Double.self, forKey: .trendRate)
    }

    var mmolL: Double { Double(value) / 18.0 }

    func displayValue(unit: GlucoseUnit) -> String {
        switch unit {
        case .mgdL: "\(value)"
        case .mmolL: String(format: "%.1f", mmolL)
        }
    }

    func menuBarLabel(unit: GlucoseUnit) -> String {
        "\(displayValue(unit: unit)) \(trend.arrow)"
    }
}

// Raw Dexcom API response shape
struct DexcomRawReading: Decodable {
    let wt: String   // "Date(1234567890000)"
    let value: Int
    let trend: String
    let trendRate: Double?

    enum CodingKeys: String, CodingKey {
        case wt = "WT"
        case value = "Value"
        case trend = "Trend"
        case trendRate = "TrendRate"
    }

    private static let trendMap: [String: GlucoseTrend] = [
        "None": .none,
        "DoubleUp": .doubleUp,
        "SingleUp": .singleUp,
        "FortyFiveUp": .fortyFiveUp,
        "Flat": .flat,
        "FortyFiveDown": .fortyFiveDown,
        "SingleDown": .singleDown,
        "DoubleDown": .doubleDown,
        "NotComputable": .notComputable,
        "RateOutOfRange": .rateOutOfRange,
    ]

    func toGlucoseReading() -> GlucoseReading? {
        // WT format: "Date(1234567890000)"
        guard let open = wt.firstIndex(of: "("),
              let close = wt.firstIndex(of: ")") else { return nil }
        let msStr = wt[wt.index(after: open)..<close]
        guard let ms = Double(msStr) else { return nil }
        let date = Date(timeIntervalSince1970: ms / 1000.0)
        let glucoseTrend = Self.trendMap[trend] ?? .none
        return GlucoseReading(value: value, trend: glucoseTrend, date: date, trendRate: trendRate)
    }
}

enum GlucoseUnit: String, CaseIterable, Codable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"
}
