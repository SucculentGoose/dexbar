import AppKit
import DexBarCore
import Foundation
import Observation
import SwiftUI

enum MenuBarStyle: String, CaseIterable {
    case full      = "Value & Arrow"
    case compact   = "Compact"
    case valueOnly = "Value Only"
    case arrowOnly = "Arrow Only"
}

@MainActor
@Observable
final class GlucoseMonitor {
    // Current state
    var currentReading: GlucoseReading?
    var recentReadings: [GlucoseReading] = []   // newest first, up to 90 days
    var selectedTimeRange: TimeRange = .threeHours
    var selectedStatsRange: StatsTimeRange = .sevenDays
    var state: MonitorState = .idle
    var lastUpdated: Date?

    var chartReadings: [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-selectedTimeRange.interval)
        return recentReadings.filter { $0.date >= cutoff }
    }

    private var statsReadings: [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-selectedStatsRange.interval)
        return recentReadings.filter { $0.date >= cutoff }
    }

    /// Actual days of data available for the selected stats range.
    var statsDataSpanDays: Double {
        guard let oldest = statsReadings.last?.date else { return 0 }
        return Date().timeIntervalSince(oldest) / 86400
    }

    var tirStats: TiRStats {
        let readings = statsReadings
        let lowCutoff  = alertLowThresholdMgdL
        let highCutoff = alertHighThresholdMgdL
        let low  = readings.filter { Double($0.value) < lowCutoff  }.count
        let high = readings.filter { Double($0.value) > highCutoff }.count
        return TiRStats(lowCount: low, inRangeCount: readings.count - low - high, highCount: high, total: readings.count)
    }

    /// Glucose Management Indicator — estimated HbA1c % from mean glucose.
    /// Formula: GMI = 3.31 + 0.02392 × mean_mg_dL
    var gmi: Double? {
        let readings = statsReadings
        guard !readings.isEmpty else { return nil }
        let mean = Double(readings.reduce(0) { $0 + $1.value }) / Double(readings.count)
        return 3.31 + 0.02392 * mean
    }

    // Settings (persisted via AppStorage in SettingsView; mirrored here)
    var unit: GlucoseUnit = .mgdL
    var refreshInterval: TimeInterval = 5 * 60

    // Alert settings
    var alertUrgentHighEnabled: Bool = true
    var alertUrgentHighThresholdMgdL: Double = 250
    var alertHighEnabled: Bool = true
    var alertHighThresholdMgdL: Double = 180
    var alertLowEnabled: Bool = true
    var alertLowThresholdMgdL: Double = 70
    var alertUrgentLowEnabled: Bool = true
    var alertUrgentLowThresholdMgdL: Double = 55
    var alertRisingFastEnabled: Bool = true
    var alertDroppingFastEnabled: Bool = true
    var alertStaleDataEnabled: Bool = true
    var alertCriticalEnabled: Bool = UserDefaults.standard.object(forKey: "alertCriticalEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(alertCriticalEnabled, forKey: "alertCriticalEnabled") }
    }
    static let staleThreshold: TimeInterval = 20 * 60

    var isStale: Bool {
        guard let reading = currentReading else { return false }
        return Date().timeIntervalSince(reading.date) > Self.staleThreshold
    }

    // Zone colors (persisted in UserDefaults as hex strings)
    var colorUrgentLow: Color = Color(hex: UserDefaults.standard.string(forKey: "colorUrgentLow") ?? "") ?? Color(red: 0.85, green: 0.1, blue: 0.1) {
        didSet { if let h = colorUrgentLow.toHex() { UserDefaults.standard.set(h, forKey: "colorUrgentLow") } }
    }
    var colorLow: Color = Color(hex: UserDefaults.standard.string(forKey: "colorLow") ?? "") ?? .orange {
        didSet { if let h = colorLow.toHex() { UserDefaults.standard.set(h, forKey: "colorLow") } }
    }
    var colorInRange: Color = Color(hex: UserDefaults.standard.string(forKey: "colorInRange") ?? "") ?? .green {
        didSet { if let h = colorInRange.toHex() { UserDefaults.standard.set(h, forKey: "colorInRange") } }
    }
    var colorHigh: Color = Color(hex: UserDefaults.standard.string(forKey: "colorHigh") ?? "") ?? .yellow {
        didSet { if let h = colorHigh.toHex() { UserDefaults.standard.set(h, forKey: "colorHigh") } }
    }
    var colorUrgentHigh: Color = Color(hex: UserDefaults.standard.string(forKey: "colorUrgentHigh") ?? "") ?? Color(red: 0.85, green: 0.1, blue: 0.1) {
        didSet { if let h = colorUrgentHigh.toHex() { UserDefaults.standard.set(h, forKey: "colorUrgentHigh") } }
    }
    var coloredMenuBar: Bool = UserDefaults.standard.bool(forKey: "coloredMenuBar") {
        didSet { UserDefaults.standard.set(coloredMenuBar, forKey: "coloredMenuBar") }
    }
    var menuBarStyle: MenuBarStyle = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "") ?? .full {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }
    var showDelta: Bool = UserDefaults.standard.object(forKey: "showDelta") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showDelta, forKey: "showDelta") }
    }

    var glucoseDelta: Int? {
        guard recentReadings.count >= 2 else { return nil }
        return recentReadings[0].value - recentReadings[1].value
    }

    func formattedDelta(unit: GlucoseUnit) -> String? {
        guard let delta = glucoseDelta else { return nil }
        switch unit {
        case .mgdL:
            return delta >= 0 ? "+\(delta)" : "\(delta)"
        case .mmolL:
            let dMmol = Double(delta) / 18.0
            return dMmol >= 0 ? String(format: "+%.1f", dMmol) : String(format: "%.1f", dMmol)
        }
    }

    var readingColor: Color {
        guard let reading = currentReading else { return .primary }
        let v = Double(reading.value)
        if v < alertUrgentLowThresholdMgdL  { return colorUrgentLow  }
        if v < alertLowThresholdMgdL         { return colorLow         }
        if v > alertUrgentHighThresholdMgdL { return colorUrgentHigh }
        if v > alertHighThresholdMgdL        { return colorHigh        }
        return colorInRange
    }

    private var service: DexcomService?
    private var timer: Timer?
    var nextRefreshDate: Date?
    private var isStarting = false

    private static let readingsURL: URL? = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DexBar/readings.json")
    }()

    private func saveReadings() {
        guard let url = Self.readingsURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try? JSONEncoder().encode(recentReadings)
        try? data?.write(to: url, options: .atomic)
    }

    private func loadPersistedReadings() {
        guard let url = Self.readingsURL,
              let data = try? Data(contentsOf: url),
              let readings = try? JSONDecoder().decode([GlucoseReading].self, from: data) else { return }
        recentReadings = readings
    }

    init() {
        loadPersistedReadings()
        Task { @MainActor in
            await autoConnectIfNeeded()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.handleSystemWake() }
        }
    }

    private func autoConnectIfNeeded() async {
        let username = UserDefaults.standard.string(forKey: "dexcomUsername") ?? ""
        let regionRaw = UserDefaults.standard.string(forKey: "dexcomRegion") ?? DexcomRegion.us.rawValue
        guard !username.isEmpty,
              let password = try? KeychainService.load(key: "password"),
              !password.isEmpty else { return }
        let region = DexcomRegion(rawValue: regionRaw) ?? .us
        await start(username: username, password: password, region: region)
    }

    // MARK: - Lifecycle

    func start(username: String, password: String, region: DexcomRegion) async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        service = DexcomService(region: region)
        state = .loading
        do {
            try await service?.authenticate(username: username, password: password)
        } catch {
            state = .error(error.localizedDescription)
            return
        }
        await refresh(initialLoad: true)
        // Timer is scheduled inside refresh() once the first reading is obtained
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        nextRefreshDate = nil
        service = nil
        state = .idle
    }

    func refreshNow() async {
        await refresh(initialLoad: false)
    }

    func updateRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        // Reschedule based on last reading so the window stays aligned
        if timer != nil {
            scheduleTimer(after: currentReading?.date)
        }
    }

    // MARK: - Private

    /// Schedule the next auto-refresh at `lastReadingDate + refreshInterval`.
    /// If that time is already past (or no reading yet), waits at least 30 s to avoid hammering the API.
    private func scheduleTimer(after lastReadingDate: Date? = nil) {
        timer?.invalidate()
        let fireDate: Date
        if let last = lastReadingDate {
            let candidate = last.addingTimeInterval(refreshInterval)
            fireDate = max(candidate, Date().addingTimeInterval(30))
        } else {
            fireDate = Date().addingTimeInterval(refreshInterval)
        }
        nextRefreshDate = fireDate
        timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func refresh(initialLoad: Bool = false) async {
        guard let service else { return }
        state = .loading
        let maxCount = initialLoad ? 288 : 2
        do {
            let newReadings = try await service.getLatestReadings(maxCount: maxCount)
            let reading = newReadings[0]
            currentReading = reading
            // Merge new readings into history deduplicating by date, cap at 288
            let existingDates = Set(recentReadings.map { $0.date })
            let toAdd = newReadings.filter { !existingDates.contains($0.date) }
            let merged = (toAdd + recentReadings).sorted { $0.date > $1.date }
            recentReadings = Array(merged.prefix(25920))  // 90 days × 288 readings/day
            lastUpdated = Date()
            state = .connected
            await evaluateAlerts(reading: reading)
            await evaluateStaleAlert(reading: reading)
            saveReadings()
            scheduleTimer(after: reading.date)
        } catch DexcomError.sessionExpired, DexcomError.invalidCredentials {
            await reAuthenticateIfPossible()
        } catch DexcomError.serverError(let code) where code == 429 {
            state = .error("Rate limited by Dexcom — will retry soon")
            scheduleTimer()
        } catch {
            state = .error(error.localizedDescription)
            scheduleTimer(after: currentReading?.date)
        }
    }

    private func handleSystemWake() async {
        // Wait briefly for the network to reconnect before attempting a refresh.
        try? await Task.sleep(for: .seconds(3))
        guard service != nil else {
            await autoConnectIfNeeded()
            return
        }
        await refresh()
    }

    private func reAuthenticateIfPossible() async {
        let username = UserDefaults.standard.string(forKey: "dexcomUsername") ?? ""
        let regionRaw = UserDefaults.standard.string(forKey: "dexcomRegion") ?? DexcomRegion.us.rawValue
        guard !username.isEmpty,
              let password = try? KeychainService.load(key: "password"),
              !password.isEmpty else {
            state = .error("Session expired — reconnect in Settings")
            if let svc = service { await svc.clearSession() }
            scheduleTimer(after: currentReading?.date)
            return
        }
        let region = DexcomRegion(rawValue: regionRaw) ?? .us
        await start(username: username, password: password, region: region)
    }

    private func evaluateStaleAlert(reading: GlucoseReading) async {
        guard alertStaleDataEnabled else { return }
        let age = Date().timeIntervalSince(reading.date)
        guard age > Self.staleThreshold else { return }
        let minutes = Int(age / 60)
        await NotificationManager.shared.send(
            type: .staleData,
            title: "No New Readings",
            body: "Last reading was \(minutes) minutes ago. Check your sensor."
        )
    }

    private func evaluateAlerts(reading: GlucoseReading) async {
        let nm = NotificationManager.shared
        let displayVal = reading.displayValue(unit: unit)
        let unitStr = unit.rawValue
        let v = Double(reading.value)

        if alertUrgentHighEnabled, v > alertUrgentHighThresholdMgdL {
            await nm.send(type: .urgentHigh, title: "Urgent High Blood Sugar",
                body: "\(displayVal) \(unitStr) — urgently above your high threshold",
                isCritical: alertCriticalEnabled)
        } else if alertHighEnabled, v > alertHighThresholdMgdL {
            await nm.send(type: .high, title: "High Blood Sugar",
                body: "\(displayVal) \(unitStr) — above your high alert threshold")
        }

        if alertUrgentLowEnabled, v < alertUrgentLowThresholdMgdL {
            await nm.send(type: .urgentLow, title: "Urgent Low Blood Sugar",
                body: "\(displayVal) \(unitStr) — urgently below your low threshold",
                isCritical: alertCriticalEnabled)
        } else if alertLowEnabled, v < alertLowThresholdMgdL {
            await nm.send(type: .low, title: "Low Blood Sugar",
                body: "\(displayVal) \(unitStr) — below your low alert threshold")
        }

        if alertRisingFastEnabled, reading.trend.isRisingFast {
            await nm.send(type: .risingFast, title: "Blood Sugar Rising Fast",
                body: "\(displayVal) \(unitStr) and \(reading.trend.description)")
        }
        if alertDroppingFastEnabled, reading.trend.isDroppingFast {
            await nm.send(type: .droppingFast, title: "Blood Sugar Dropping Fast",
                body: "\(displayVal) \(unitStr) and \(reading.trend.description)")
        }
    }
}
