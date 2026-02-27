import Foundation
import Observation
import SwiftUI

enum MonitorState: Equatable {
    case idle
    case loading
    case connected
    case error(String)

    var statusText: String {
        switch self {
        case .idle: "Not connected"
        case .loading: "Loading…"
        case .connected: "Connected"
        case .error(let msg): msg
        }
    }
}

@MainActor
@Observable
final class GlucoseMonitor {
    // Current state
    var currentReading: GlucoseReading?
    var recentReadings: [GlucoseReading] = []
    var state: MonitorState = .idle
    var lastUpdated: Date?

    // Settings (persisted via AppStorage in SettingsView; mirrored here)
    var unit: GlucoseUnit = .mgdL
    var refreshInterval: TimeInterval = 5 * 60

    // Alert settings
    var alertHighEnabled: Bool = true
    var alertHighThresholdMgdL: Double = 180
    var alertLowEnabled: Bool = true
    var alertLowThresholdMgdL: Double = 70
    var alertRisingFastEnabled: Bool = true
    var alertDroppingFastEnabled: Bool = true
    var coloredMenuBar: Bool = UserDefaults.standard.bool(forKey: "coloredMenuBar") {
        didSet { UserDefaults.standard.set(coloredMenuBar, forKey: "coloredMenuBar") }
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
        let val = Double(reading.value)
        if val < alertLowThresholdMgdL || val > alertHighThresholdMgdL { return .red }
        let warnLow = alertLowThresholdMgdL + 20
        let warnHigh = alertHighThresholdMgdL - 20
        if val < warnLow || val > warnHigh { return .yellow }
        return .green
    }

    private var service: DexcomService?
    private var timer: Timer?
    var nextRefreshDate: Date?

    init() {
        Task { @MainActor in
            await autoConnectIfNeeded()
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
        service = DexcomService(region: region)
        state = .loading
        do {
            try await service?.authenticate(username: username, password: password)
        } catch {
            state = .error(error.localizedDescription)
            return
        }
        await refresh()
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
        await refresh()
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

    private func refresh() async {
        guard let service else { return }
        state = .loading
        do {
            let readings = try await service.getLatestReadings()
            let reading = readings[0]
            currentReading = reading
            // Merge new readings into history (newest first), cap at 5
            let merged = (readings + recentReadings).sorted { $0.date > $1.date }
            recentReadings = Array(merged.prefix(5))
            lastUpdated = Date()
            state = .connected
            await evaluateAlerts(reading: reading)
            scheduleTimer(after: reading.date)
        } catch DexcomError.sessionExpired {
            // Try re-authenticating
            state = .error("Session expired — reconnect in Settings")
            await service.clearSession()
            scheduleTimer(after: currentReading?.date)
        } catch {
            state = .error(error.localizedDescription)
            scheduleTimer(after: currentReading?.date)
        }
    }

    private func evaluateAlerts(reading: GlucoseReading) async {
        let nm = NotificationManager.shared
        let displayVal = reading.displayValue(unit: unit)
        let unitStr = unit.rawValue

        if alertHighEnabled, Double(reading.value) > alertHighThresholdMgdL {
            await nm.send(
                type: .high,
                title: "High Blood Sugar",
                body: "\(displayVal) \(unitStr) — above your high alert threshold"
            )
        }

        if alertLowEnabled, Double(reading.value) < alertLowThresholdMgdL {
            await nm.send(
                type: .low,
                title: "Low Blood Sugar",
                body: "\(displayVal) \(unitStr) — below your low alert threshold"
            )
        }

        if alertRisingFastEnabled, reading.trend.isRisingFast {
            await nm.send(
                type: .risingFast,
                title: "Blood Sugar Rising Fast",
                body: "\(displayVal) \(unitStr) and \(reading.trend.description)"
            )
        }

        if alertDroppingFastEnabled, reading.trend.isDroppingFast {
            await nm.send(
                type: .droppingFast,
                title: "Blood Sugar Dropping Fast",
                body: "\(displayVal) \(unitStr) and \(reading.trend.description)"
            )
        }
    }
}
