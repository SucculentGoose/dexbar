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

    var isStale: Bool {
        guard let reading = currentReading else { return false }
        return Date().timeIntervalSince(reading.date) > Self.staleThreshold
    }

    static let staleThreshold: TimeInterval = 20 * 60

    var tirStats: TiRStats {
        let cutoff = Date().addingTimeInterval(-statsTimeRange.interval)
        let readings = recentReadings.filter { $0.date >= cutoff }
        let low  = readings.filter { Double($0.value) < alertLowThresholdMgdL  }.count
        let high = readings.filter { Double($0.value) > alertHighThresholdMgdL }.count
        return TiRStats(
            lowCount: low,
            inRangeCount: readings.count - low - high,
            highCount: high,
            total: readings.count
        )
    }

    var gmi: Double? {
        let cutoff = Date().addingTimeInterval(-statsTimeRange.interval)
        let readings = recentReadings.filter { $0.date >= cutoff }
        guard !readings.isEmpty else { return nil }
        let mean = Double(readings.reduce(0) { $0 + $1.value }) / Double(readings.count)
        return 3.31 + 0.02392 * mean
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

    // MARK: - Private

    private let defaults = UserDefaults.standard
    private var service: DexcomService?
    private var timer: Timer?
    var nextRefreshDate: Date?
    private var isStarting = false

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
        onUpdate?()
        do {
            try await service?.authenticate(username: username, password: password)
        } catch {
            state = .error(error.localizedDescription)
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

    private func autoConnectIfNeeded() async {
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
            fireDate = max(candidate, Date().addingTimeInterval(30))
        } else {
            fireDate = Date().addingTimeInterval(refreshInterval)
        }
        nextRefreshDate = fireDate
        timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .default)
    }

    private func refresh(initialLoad: Bool = false) async {
        guard let service else { return }
        state = .loading
        onUpdate?()
        let maxCount = initialLoad ? 288 : 2
        do {
            let newReadings = try await service.getLatestReadings(maxCount: maxCount)
            let reading = newReadings[0]
            currentReading = reading
            let existingDates = Set(recentReadings.map { $0.date })
            let toAdd = newReadings.filter { !existingDates.contains($0.date) }
            let merged = (toAdd + recentReadings).sorted { $0.date > $1.date }
            recentReadings = Array(merged.prefix(25920))
            lastUpdated = Date()
            state = .connected
            evaluateAlerts(reading: reading)
            evaluateStaleAlert(reading: reading)
            saveReadings()
            scheduleTimer(after: reading.date)
        } catch DexcomError.sessionExpired {
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
        await start(username: username, password: password, region: region)
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
        let data = try? JSONEncoder().encode(recentReadings)
        try? data?.write(to: url, options: .atomic)
    }

    private func loadPersistedReadings() {
        guard let url = Self.readingsURL,
              let data = try? Data(contentsOf: url),
              let readings = try? JSONDecoder().decode([GlucoseReading].self, from: data) else { return }
        recentReadings = readings
    }
}
