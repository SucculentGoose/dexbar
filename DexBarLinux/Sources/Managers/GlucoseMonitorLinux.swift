import DexBarCore
import Foundation

/// Callback-based glucose state manager for the Linux app.
/// Mirrors the behaviour of the macOS GlucoseMonitor without any SwiftUI dependencies.
@MainActor
final class GlucoseMonitorLinux {

    // MARK: - Observable state

    var currentReading: GlucoseReading?
    var recentReadings: [GlucoseReading] = []
    var state: MonitorState = .idle
    var lastUpdated: Date?

    /// Fired every time state or currentReading changes so UI components can refresh.
    var onUpdate: (() -> Void)?

    // MARK: - Computed properties

    /// Change from the previous reading, or nil if there is no recent previous reading.
    var glucoseDelta: Int? {
        guard recentReadings.count >= 2 else { return nil }
        return ReadingHistory.delta(from: recentReadings[1], to: recentReadings[0])
    }

    func formattedDelta(unit: GlucoseUnit) -> String? {
        glucoseDelta.map { ReadingHistory.formatDelta($0, unit: unit) }
    }

    var isStale: Bool {
        guard let reading = currentReading else { return false }
        return Date().timeIntervalSince(reading.date) > Self.staleThreshold
    }

    static let staleThreshold: TimeInterval = 20 * 60

    private var statsReadings: ArraySlice<GlucoseReading> {
        recentReadings.newest(within: statsTimeRange.interval)
    }

    var tirStats: TiRStats {
        TiRStats(readings: statsReadings, lowThreshold: alertLowThresholdMgdL, highThreshold: alertHighThresholdMgdL)
    }

    var gmi: Double? {
        ReadingHistory.gmi(statsReadings)
    }

    /// Actual days of data available for the selected stats range.
    var statsDataSpanDays: Double {
        guard let oldest = statsReadings.last?.date else { return 0 }
        return Date().timeIntervalSince(oldest) / 86400
    }

    // MARK: - Chart

    var selectedTimeRange: TimeRange {
        get { TimeRange(rawValue: defaults.string(forKey: "selectedTimeRange") ?? TimeRange.threeHours.rawValue) ?? .threeHours }
        set { defaults.set(newValue.rawValue, forKey: "selectedTimeRange") }
    }

    /// Readings in the selected chart range, newest first.
    var chartReadings: [GlucoseReading] {
        Array(recentReadings.newest(within: selectedTimeRange.interval))
    }

    /// Returns the hex color string for a single reading based on threshold settings.
    func colorForReading(_ reading: GlucoseReading) -> String {
        let v = Double(reading.value)
        if v < alertUrgentLowThresholdMgdL  { return colorUrgentLow  }
        if v < alertLowThresholdMgdL         { return colorLow         }
        if v > alertUrgentHighThresholdMgdL { return colorUrgentHigh }
        if v > alertHighThresholdMgdL        { return colorHigh        }
        return colorInRange
    }

    // MARK: - Settings (via UserDefaults)

    var unit: GlucoseUnit {
        get { GlucoseUnit(rawValue: defaults.string(forKey: "unit") ?? GlucoseUnit.mgdL.rawValue) ?? .mgdL }
        set { defaults.set(newValue.rawValue, forKey: "unit") }
    }

    var refreshInterval: TimeInterval {
        get {
            let v = defaults.double(forKey: "refreshInterval")
            return v > 0 ? v : 5 * 60
        }
        set { defaults.set(newValue, forKey: "refreshInterval") }
    }

    var region: DexcomRegion {
        get { DexcomRegion(rawValue: defaults.string(forKey: "dexcomRegion") ?? DexcomRegion.us.rawValue) ?? .us }
        set { defaults.set(newValue.rawValue, forKey: "dexcomRegion") }
    }

    var statsTimeRange: StatsTimeRange {
        get { StatsTimeRange(rawValue: defaults.string(forKey: "statsTimeRange") ?? StatsTimeRange.sevenDays.rawValue) ?? .sevenDays }
        set { defaults.set(newValue.rawValue, forKey: "statsTimeRange") }
    }

    // Alert settings
    var alertUrgentHighEnabled: Bool {
        get { defaults.object(forKey: "alertUrgentHighEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "alertUrgentHighEnabled") }
    }
    var alertUrgentHighThresholdMgdL: Double {
        get { defaults.object(forKey: "alertUrgentHighThresholdMgdL") as? Double ?? 250 }
        set { defaults.set(newValue, forKey: "alertUrgentHighThresholdMgdL") }
    }
    var alertHighEnabled: Bool {
        get { defaults.object(forKey: "alertHighEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "alertHighEnabled") }
    }
    var alertHighThresholdMgdL: Double {
        get { defaults.object(forKey: "alertHighThresholdMgdL") as? Double ?? 180 }
        set { defaults.set(newValue, forKey: "alertHighThresholdMgdL") }
    }
    var alertLowEnabled: Bool {
        get { defaults.object(forKey: "alertLowEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "alertLowEnabled") }
    }
    var alertLowThresholdMgdL: Double {
        get { defaults.object(forKey: "alertLowThresholdMgdL") as? Double ?? 70 }
        set { defaults.set(newValue, forKey: "alertLowThresholdMgdL") }
    }
    var alertUrgentLowEnabled: Bool {
        get { defaults.object(forKey: "alertUrgentLowEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "alertUrgentLowEnabled") }
    }
    var alertUrgentLowThresholdMgdL: Double {
        get { defaults.object(forKey: "alertUrgentLowThresholdMgdL") as? Double ?? 55 }
        set { defaults.set(newValue, forKey: "alertUrgentLowThresholdMgdL") }
    }
    var alertRisingFastEnabled: Bool {
        get { defaults.object(forKey: "alertRisingFastEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "alertRisingFastEnabled") }
    }
    var alertDroppingFastEnabled: Bool {
        get { defaults.object(forKey: "alertDroppingFastEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "alertDroppingFastEnabled") }
    }
    var alertStaleDataEnabled: Bool {
        get { defaults.object(forKey: "alertStaleDataEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "alertStaleDataEnabled") }
    }

    // MARK: - Reading color (matches macOS defaults)

    var colorUrgentLow:  String {
        get { defaults.string(forKey: "colorUrgentLow")  ?? "#D91A1A" }
        set { defaults.set(newValue, forKey: "colorUrgentLow") }
    }
    var colorLow: String {
        get { defaults.string(forKey: "colorLow")  ?? "#FF8C00" }
        set { defaults.set(newValue, forKey: "colorLow") }
    }
    var colorInRange: String {
        get { defaults.string(forKey: "colorInRange") ?? "#34C759" }
        set { defaults.set(newValue, forKey: "colorInRange") }
    }
    var colorHigh: String {
        get { defaults.string(forKey: "colorHigh") ?? "#FFD60A" }
        set { defaults.set(newValue, forKey: "colorHigh") }
    }
    var colorUrgentHigh: String {
        get { defaults.string(forKey: "colorUrgentHigh") ?? "#D91A1A" }
        set { defaults.set(newValue, forKey: "colorUrgentHigh") }
    }

    var coloredTrayIcon: Bool {
        get { defaults.object(forKey: "coloredMenuBar") == nil ? true : defaults.bool(forKey: "coloredMenuBar") }
        set { defaults.set(newValue, forKey: "coloredMenuBar") }
    }

    var readingColor: String {
        guard coloredTrayIcon else { return "#8E8E93" }
        guard let reading = currentReading else { return colorInRange }
        let v = Double(reading.value)
        if v < alertUrgentLowThresholdMgdL  { return colorUrgentLow  }
        if v < alertLowThresholdMgdL         { return colorLow         }
        if v > alertUrgentHighThresholdMgdL { return colorUrgentHigh }
        if v > alertHighThresholdMgdL        { return colorHigh        }
        return colorInRange
    }

    // MARK: - Private

    private let defaults = UserDefaults.standard
    private var service: DexcomService?
    private var timer: Timer?
    var nextRefreshDate: Date?
    private var isStarting = false
    private var consecutiveStalePolls = 0
    /// Set when Dexcom rejects the stored password. Automatic reconnects stay off
    /// until the user connects again, since repeated failed logins can lock the account.
    private var credentialsRejected = false

    private static let readingsURL: URL? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".local/share/dexbar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("readings.json")
    }()

    init() {
        loadPersistedReadings()
        Task { @MainActor in await autoConnectIfNeeded() }
    }

    // MARK: - Lifecycle

    func start(username: String, password: String, region: DexcomRegion) async {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        service = DexcomService(region: region)
        state = .loading
        consecutiveStalePolls = 0
        credentialsRejected = false
        onUpdate?()
        do {
            try await service?.authenticate(username: username, password: password)
        } catch DexcomError.invalidCredentials {
            stopPolling(credentialsError: DexcomError.invalidCredentials.localizedDescription)
            return
        } catch {
            // Often the network isn't up yet at login — keep retrying.
            state = .error(error.localizedDescription)
            scheduleTimer()
            onUpdate?()
            return
        }
        await refresh(initialLoad: true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        nextRefreshDate = nil
        service = nil
        state = .idle
        consecutiveStalePolls = 0
        onUpdate?()
    }

    func refreshNow() async {
        await refresh(initialLoad: false)
    }

    func updateRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        if timer != nil {
            scheduleTimer(after: currentReading?.date)
        }
    }

    // MARK: - Private helpers

    /// Stops automatic polling after Dexcom rejects the stored password; retrying
    /// with the same password only risks locking the account.
    private func stopPolling(credentialsError message: String) {
        timer?.invalidate()
        timer = nil
        nextRefreshDate = nil
        service = nil
        credentialsRejected = true
        state = .error(message)
        onUpdate?()
    }

    private func autoConnectIfNeeded() async {
        guard !credentialsRejected else { return }
        let username = defaults.string(forKey: "dexcomUsername") ?? ""
        guard !username.isEmpty else { return }
#if canImport(CLibSecret)
        guard let password = SecretServiceStorage.load(key: "password"), !password.isEmpty else { return }
#else
        guard let password = defaults.string(forKey: "dexcomPasswordFallback"), !password.isEmpty else { return }
#endif
        await start(username: username, password: password, region: region)
    }

    private func scheduleTimer(after lastReadingDate: Date? = nil) {
        timer?.invalidate()
        let fireDate: Date
        if let last = lastReadingDate {
            let candidate = last.addingTimeInterval(refreshInterval)
            let floor = min(30 * pow(2, Double(consecutiveStalePolls)), 300)
            fireDate = max(candidate, Date().addingTimeInterval(floor))
        } else {
            fireDate = Date().addingTimeInterval(refreshInterval)
        }
        nextRefreshDate = fireDate
        timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // If we're firing much later than expected, the system likely woke from sleep.
                // Give the network a few seconds to reconnect before refreshing.
                if let expected = self.nextRefreshDate,
                   Date().timeIntervalSince(expected) > 30 {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
                await self.refresh()
            }
        }
        RunLoop.main.add(timer!, forMode: .default)
    }

    private func refresh(initialLoad: Bool = false) async {
        guard let service else { return }
        state = .loading
        onUpdate?()
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
            let existingDates = Set(recentReadings.map { $0.date })
            let toAdd = newReadings.filter { !existingDates.contains($0.date) }
            if !toAdd.isEmpty {
                let merged = (toAdd + recentReadings).sorted { $0.date > $1.date }
                recentReadings = Array(merged.prefix(25920))
                saveReadings()
            }
            lastUpdated = Date()
            state = .connected
            evaluateAlerts(reading: reading)
            evaluateStaleAlert(reading: reading)
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
        onUpdate?()
    }

    private func reAuthenticateIfPossible() async {
        let username = defaults.string(forKey: "dexcomUsername") ?? ""
        guard !username.isEmpty else {
            state = .error("Session expired — reconnect in Settings")
            onUpdate?()
            return
        }
#if canImport(CLibSecret)
        guard let password = SecretServiceStorage.load(key: "password"), !password.isEmpty else {
            state = .error("Session expired — reconnect in Settings")
            onUpdate?()
            return
        }
#else
        guard let password = defaults.string(forKey: "dexcomPasswordFallback"), !password.isEmpty else {
            state = .error("Session expired — reconnect in Settings")
            onUpdate?()
            return
        }
#endif
        // Retry up to 3 times with increasing delays — the network may still be
        // reconnecting after a sleep/wake cycle when this is called.
        let delays: [UInt64] = [3_000_000_000, 5_000_000_000, 10_000_000_000]
        for (attempt, delay) in delays.enumerated() {
            try? await Task.sleep(nanoseconds: delay)
            do {
                service = DexcomService(region: region)
                state = .loading
                onUpdate?()
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
                onUpdate?()
                return
            }
        }
    }

    private func evaluateAlerts(reading: GlucoseReading) {
#if canImport(CLibNotify)
        let nm = LinuxNotificationManager.shared
        let displayVal = reading.displayValue(unit: unit)
        let unitStr = unit.rawValue
        let v = Double(reading.value)

        if alertUrgentHighEnabled, v > alertUrgentHighThresholdMgdL {
            nm.send(type: .urgentHigh, title: "Urgent High Blood Sugar",
                body: "\(displayVal) \(unitStr) — urgently above your high threshold", urgent: true)
        } else if alertHighEnabled, v > alertHighThresholdMgdL {
            nm.send(type: .high, title: "High Blood Sugar",
                body: "\(displayVal) \(unitStr) — above your high alert threshold")
        }
        if alertUrgentLowEnabled, v < alertUrgentLowThresholdMgdL {
            nm.send(type: .urgentLow, title: "Urgent Low Blood Sugar",
                body: "\(displayVal) \(unitStr) — urgently below your low threshold", urgent: true)
        } else if alertLowEnabled, v < alertLowThresholdMgdL {
            nm.send(type: .low, title: "Low Blood Sugar",
                body: "\(displayVal) \(unitStr) — below your low alert threshold")
        }
        if alertRisingFastEnabled, reading.trend.isRisingFast {
            nm.send(type: .risingFast, title: "Blood Sugar Rising Fast",
                body: "\(displayVal) \(unitStr) and \(reading.trend.description)")
        }
        if alertDroppingFastEnabled, reading.trend.isDroppingFast {
            nm.send(type: .droppingFast, title: "Blood Sugar Dropping Fast",
                body: "\(displayVal) \(unitStr) and \(reading.trend.description)")
        }
#endif
    }

    private func evaluateStaleAlert(reading: GlucoseReading) {
#if canImport(CLibNotify)
        guard alertStaleDataEnabled else { return }
        let age = Date().timeIntervalSince(reading.date)
        guard age > Self.staleThreshold else { return }
        let minutes = Int(age / 60)
        LinuxNotificationManager.shared.send(
            type: .staleData,
            title: "No New Readings",
            body: "Last reading was \(minutes) minutes ago. Check your sensor."
        )
#endif
    }

    private func saveReadings() {
        guard let url = Self.readingsURL else { return }
        let readings = recentReadings
        Task.detached(priority: .utility) {
            let data = try? JSONEncoder().encode(readings)
            try? data?.write(to: url, options: .atomic)
        }
    }

    private func loadPersistedReadings() {
        guard let url = Self.readingsURL,
              let data = try? Data(contentsOf: url),
              let readings = try? JSONDecoder().decode([GlucoseReading].self, from: data) else { return }
        recentReadings = readings
    }
}
