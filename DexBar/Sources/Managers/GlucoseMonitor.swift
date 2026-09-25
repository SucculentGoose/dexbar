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
        Array(recentReadings.newest(within: selectedTimeRange.interval))
    }

    private var statsReadings: ArraySlice<GlucoseReading> {
        recentReadings.newest(within: selectedStatsRange.interval)
    }

    /// Actual days of data available for the selected stats range.
    var statsDataSpanDays: Double {
        guard let oldest = statsReadings.last?.date else { return 0 }
        return Date().timeIntervalSince(oldest) / 86400
    }

    var tirStats: TiRStats {
        TiRStats(readings: statsReadings, lowThreshold: alertLowThresholdMgdL, highThreshold: alertHighThresholdMgdL)
    }

    /// Glucose Management Indicator — estimated HbA1c % from mean glucose.
    var gmi: Double? {
        ReadingHistory.gmi(statsReadings)
    }

    // Settings are loaded from `defaults` in init(). Display/alert settings are written
    // by SettingsView via AppStorage and mirrored here; the rest persist on change.
    private let defaults: UserDefaults
    private let readingsURL: URL?

    var unit: GlucoseUnit = .mgdL
    var refreshInterval: TimeInterval = 5 * 60

    // Alert settings
    var alertUrgentHighEnabled = true
    var alertUrgentHighThresholdMgdL: Double = 250
    var alertHighEnabled = true
    var alertHighThresholdMgdL: Double = 180
    var alertLowEnabled = true
    var alertLowThresholdMgdL: Double = 70
    var alertUrgentLowEnabled = true
    var alertUrgentLowThresholdMgdL: Double = 55
    var alertRisingFastEnabled = true
    var alertDroppingFastEnabled = true
    var alertStaleDataEnabled = true
    var alertCriticalEnabled = false {
        didSet { defaults.set(alertCriticalEnabled, forKey: "alertCriticalEnabled") }
    }
    static let staleThreshold: TimeInterval = 20 * 60

    var isStale: Bool {
        guard let reading = currentReading else { return false }
        return Date().timeIntervalSince(reading.date) > Self.staleThreshold
    }

    // Zone colors (persisted in UserDefaults as hex strings)
    private static let defaultUrgentColor = Color(red: 0.85, green: 0.1, blue: 0.1)
    var colorUrgentLow: Color = GlucoseMonitor.defaultUrgentColor {
        didSet { if let h = colorUrgentLow.toHex() { defaults.set(h, forKey: "colorUrgentLow") } }
    }
    var colorLow: Color = .orange {
        didSet { if let h = colorLow.toHex() { defaults.set(h, forKey: "colorLow") } }
    }
    var colorInRange: Color = .green {
        didSet { if let h = colorInRange.toHex() { defaults.set(h, forKey: "colorInRange") } }
    }
    var colorHigh: Color = .yellow {
        didSet { if let h = colorHigh.toHex() { defaults.set(h, forKey: "colorHigh") } }
    }
    var colorUrgentHigh: Color = GlucoseMonitor.defaultUrgentColor {
        didSet { if let h = colorUrgentHigh.toHex() { defaults.set(h, forKey: "colorUrgentHigh") } }
    }
    var coloredMenuBar = false {
        didSet { defaults.set(coloredMenuBar, forKey: "coloredMenuBar") }
    }
    var menuBarStyle: MenuBarStyle = .full {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }
    var showDelta = true {
        didSet { defaults.set(showDelta, forKey: "showDelta") }
    }

    /// Change from the previous reading, or nil if there is no recent previous reading.
    var glucoseDelta: Int? {
        guard recentReadings.count >= 2 else { return nil }
        return ReadingHistory.delta(from: recentReadings[1], to: recentReadings[0])
    }

    func formattedDelta(unit: GlucoseUnit) -> String? {
        glucoseDelta.map { ReadingHistory.formatDelta($0, unit: unit) }
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
    private var consecutiveStalePolls = 0
    /// Set when Dexcom rejects the stored password. Automatic reconnects stay off
    /// until the user connects again, since repeated failed logins can lock the account.
    private var credentialsRejected = false

    static let defaultReadingsURL: URL? = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DexBar/readings.json")
    }()

    private func saveReadings() {
        guard let url = readingsURL else { return }
        let readings = recentReadings
        Task.detached(priority: .utility) {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try? JSONEncoder().encode(readings)
            try? data?.write(to: url, options: .atomic)
        }
    }

    private func loadPersistedReadings() {
        guard let url = readingsURL,
              let data = try? Data(contentsOf: url),
              let readings = try? JSONDecoder().decode([GlucoseReading].self, from: data) else { return }
        recentReadings = readings
    }

    private func loadSettings() {
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) as? Double ?? fallback }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func color(_ key: String) -> Color? { defaults.string(forKey: key).flatMap { Color(hex: $0) } }

        unit = GlucoseUnit(rawValue: defaults.string(forKey: "glucoseUnit") ?? "") ?? .mgdL
        refreshInterval = double("refreshIntervalMinutes", 5) * 60
        alertUrgentHighEnabled = bool("alertUrgentHighEnabled", true)
        alertUrgentHighThresholdMgdL = double("alertUrgentHighMgdL", 250)
        alertHighEnabled = bool("alertHighEnabled", true)
        alertHighThresholdMgdL = double("alertHighMgdL", 180)
        alertLowEnabled = bool("alertLowEnabled", true)
        alertLowThresholdMgdL = double("alertLowMgdL", 70)
        alertUrgentLowEnabled = bool("alertUrgentLowEnabled", true)
        alertUrgentLowThresholdMgdL = double("alertUrgentLowMgdL", 55)
        alertRisingFastEnabled = bool("alertRisingFastEnabled", true)
        alertDroppingFastEnabled = bool("alertDroppingFastEnabled", true)
        alertStaleDataEnabled = bool("alertStaleDataEnabled", true)
        alertCriticalEnabled = bool("alertCriticalEnabled", false)
        if let c = color("colorUrgentLow") { colorUrgentLow = c }
        if let c = color("colorLow") { colorLow = c }
        if let c = color("colorInRange") { colorInRange = c }
        if let c = color("colorHigh") { colorHigh = c }
        if let c = color("colorUrgentHigh") { colorUrgentHigh = c }
        coloredMenuBar = defaults.bool(forKey: "coloredMenuBar")
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "") ?? .full
        showDelta = bool("showDelta", true)
    }

    /// - Parameters:
    ///   - defaults: settings store; tests pass an isolated suite.
    ///   - readingsURL: where reading history is persisted; nil disables persistence.
    ///   - autoConnect: log in with stored credentials and watch for wake. Off in tests.
    init(defaults: UserDefaults = .standard,
         readingsURL: URL? = GlucoseMonitor.defaultReadingsURL,
         autoConnect: Bool = true) {
        self.defaults = defaults
        self.readingsURL = readingsURL
        loadSettings()
        loadPersistedReadings()
        guard autoConnect else { return }
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
        guard !credentialsRejected else { return }
        let username = defaults.string(forKey: "dexcomUsername") ?? ""
        let regionRaw = defaults.string(forKey: "dexcomRegion") ?? DexcomRegion.us.rawValue
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
        consecutiveStalePolls = 0
        credentialsRejected = false
        service = DexcomService(region: region)
        state = .loading
        do {
            try await service?.authenticate(username: username, password: password)
        } catch DexcomError.invalidCredentials {
            stopPolling(credentialsError: DexcomError.invalidCredentials.localizedDescription)
            return
        } catch {
            state = .error(error.localizedDescription)
            scheduleTimer()
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
        consecutiveStalePolls = 0
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

    /// Stops automatic polling after Dexcom rejects the stored password; retrying
    /// with the same password only risks locking the account.
    private func stopPolling(credentialsError message: String) {
        timer?.invalidate()
        timer = nil
        nextRefreshDate = nil
        service = nil
        credentialsRejected = true
        state = .error(message)
    }

    /// Schedule the next auto-refresh at `lastReadingDate + refreshInterval`.
    /// If that time is already past (or no reading yet), waits at least 30 s to avoid hammering the API.
    private func scheduleTimer(after lastReadingDate: Date? = nil) {
        timer?.invalidate()
        let floor = min(30 * pow(2, Double(consecutiveStalePolls)), 300)
        let fireDate: Date
        if let last = lastReadingDate {
            let candidate = last.addingTimeInterval(refreshInterval)
            fireDate = max(candidate, Date().addingTimeInterval(floor))
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
        // After a sleep or outage, request enough readings to fill the gap.
        let maxCount = initialLoad
            ? ReadingHistory.maxFetchCount
            : ReadingHistory.fetchCount(since: recentReadings.first?.date)
        do {
            let newReadings = try await service.getLatestReadings(maxCount: maxCount)
            let reading = newReadings[0]
            if reading.date == currentReading?.date {
                consecutiveStalePolls += 1
            } else {
                consecutiveStalePolls = 0
            }
            currentReading = reading
            // Merge new readings into history deduplicating by date
            let existingDates = Set(recentReadings.map { $0.date })
            let toAdd = newReadings.filter { !existingDates.contains($0.date) }
            if !toAdd.isEmpty {
                let merged = (toAdd + recentReadings).sorted { $0.date > $1.date }
                recentReadings = Array(merged.prefix(25920))  // 90 days × 288 readings/day
                saveReadings()
            }
            lastUpdated = Date()
            state = .connected
            await evaluateAlerts(reading: reading)
            await evaluateStaleAlert(reading: reading)
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
        let username = defaults.string(forKey: "dexcomUsername") ?? ""
        let regionRaw = defaults.string(forKey: "dexcomRegion") ?? DexcomRegion.us.rawValue
        guard !username.isEmpty,
              let password = try? KeychainService.load(key: "password"),
              !password.isEmpty else {
            state = .error("Session expired — reconnect in Settings")
            if let svc = service { await svc.clearSession() }
            scheduleTimer(after: currentReading?.date)
            return
        }
        let region = DexcomRegion(rawValue: regionRaw) ?? .us
        // Retry up to 3 times with increasing delays — the network may still be
        // reconnecting after a sleep/wake cycle when this is called.
        let delays: [UInt64] = [3_000_000_000, 5_000_000_000, 10_000_000_000]
        for (attempt, delay) in delays.enumerated() {
            try? await Task.sleep(nanoseconds: delay)
            do {
                service = DexcomService(region: region)
                state = .loading
                try await service?.authenticate(username: username, password: password)
                await refresh(initialLoad: false)
                return
            } catch DexcomError.invalidCredentials {
                stopPolling(credentialsError: "Dexcom rejected the saved password — reconnect in Settings")
                return
            } catch DexcomError.sessionExpired where attempt < delays.count - 1 {
                // Still failing — try again after next delay
                continue
            } catch {
                state = .error(error.localizedDescription)
                scheduleTimer(after: currentReading?.date)
                return
            }
        }
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
