import SwiftUI

struct SettingsView: View {
    @Environment(GlucoseMonitor.self) private var monitor
    @EnvironmentObject private var sparkle: SparkleController

    // Account
    @AppStorage("dexcomUsername") private var username = ""
    @AppStorage("dexcomRegion") private var regionRaw = DexcomRegion.us.rawValue
    @State private var password = ""
    @State private var connectionStatus: String = ""
    @State private var isConnecting = false

    // Display
    @AppStorage("glucoseUnit") private var unitRaw = GlucoseUnit.mgdL.rawValue
    @AppStorage("refreshIntervalMinutes") private var refreshMinutes = 5.0

    // Alerts
    @AppStorage("alertUrgentHighEnabled") private var alertUrgentHigh = true
    @AppStorage("alertUrgentHighMgdL")    private var urgentHighMgdL  = 250.0
    @AppStorage("alertHighEnabled")       private var alertHighEnabled = true
    @AppStorage("alertHighMgdL")          private var alertHighMgdL    = 180.0
    @AppStorage("alertLowEnabled")        private var alertLowEnabled  = true
    @AppStorage("alertLowMgdL")           private var alertLowMgdL     = 70.0
    @AppStorage("alertUrgentLowEnabled")  private var alertUrgentLow   = true
    @AppStorage("alertUrgentLowMgdL")     private var urgentLowMgdL    = 55.0
    @AppStorage("alertRisingFastEnabled") private var alertRisingFast  = true
    @AppStorage("alertDroppingFastEnabled") private var alertDroppingFast = true
    @AppStorage("alertStaleDataEnabled")  private var alertStaleData   = true

    private let minGap = 5.0   // minimum mg/dL gap between adjacent thresholds

    private var region: DexcomRegion {
        DexcomRegion(rawValue: regionRaw) ?? .us
    }
    private var unit: GlucoseUnit {
        GlucoseUnit(rawValue: unitRaw) ?? .mgdL
    }

    var body: some View {
        TabView {
            accountTab
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            displayTab
                .tabItem { Label("Display", systemImage: "dial.low") }
            alertsTab
                .tabItem { Label("Alerts", systemImage: "bell") }
            disclaimerTab
                .tabItem { Label("Disclaimer", systemImage: "exclamationmark.triangle") }
            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 400)
        .padding(20)
        .onAppear(perform: loadPassword)
    }

    // MARK: - Account Tab

    private var accountTab: some View {
        Form {
            Section("Dexcom Credentials") {
                TextField("Username / Email / Phone", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                Picker("Region", selection: $regionRaw) {
                    ForEach(DexcomRegion.allCases, id: \.rawValue) { r in
                        Text(r.rawValue).tag(r.rawValue)
                    }
                }
            }
            Section {
                HStack {
                    Button(isConnecting ? "Connecting…" : "Connect") {
                        Task { await connect() }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isConnecting)
                    if !connectionStatus.isEmpty {
                        Spacer()
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundStyle(connectionStatus.contains("✓") ? .green : .red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Display Tab

    private var displayTab: some View {
        @Bindable var monitor = monitor
        return Form {
            Section("Menu Bar") {
                Toggle("Color-coded indicator dot", isOn: $monitor.coloredMenuBar)
                Text("Shows a colored dot next to the reading based on your threshold zones.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show delta", isOn: $monitor.showDelta)
                Text("Appends the change from the previous reading (e.g. +3 or −0.2) next to the value.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Range Colors") {
                colorRow("Urgent Low  (< \(thresholdLabel(urgentLowMgdL)))",  color: $monitor.colorUrgentLow)
                colorRow("Low  (\(thresholdLabel(urgentLowMgdL))–\(thresholdLabel(alertLowMgdL)))",         color: $monitor.colorLow)
                colorRow("In Range  (\(thresholdLabel(alertLowMgdL))–\(thresholdLabel(alertHighMgdL)))",   color: $monitor.colorInRange)
                colorRow("High  (\(thresholdLabel(alertHighMgdL))–\(thresholdLabel(urgentHighMgdL)))",     color: $monitor.colorHigh)
                colorRow("Urgent High  (> \(thresholdLabel(urgentHighMgdL)))", color: $monitor.colorUrgentHigh)
            }
            Section("Units") {
                Picker("Blood sugar unit", selection: $unitRaw) {
                    ForEach(GlucoseUnit.allCases, id: \.rawValue) { u in
                        Text(u.rawValue).tag(u.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: unitRaw) { _, new in monitor.unit = GlucoseUnit(rawValue: new) ?? .mgdL }
            }
            Section("Refresh Interval") {
                Picker("Refresh every", selection: $refreshMinutes) {
                    Text("1 minute").tag(1.0)
                    Text("2 minutes").tag(2.0)
                    Text("5 minutes").tag(5.0)
                    Text("10 minutes").tag(10.0)
                    Text("15 minutes").tag(15.0)
                }
                .onChange(of: refreshMinutes) { _, new in monitor.updateRefreshInterval(new * 60) }
            }
        }
        .formStyle(.grouped)
    }

    private func colorRow(_ label: String, color: Binding<Color>) -> some View {
        HStack {
            Text(label)
            Spacer()
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28)
        }
    }

    private func thresholdLabel(_ mgdL: Double) -> String {
        unit == .mmolL ? String(format: "%.1f", mgdL / 18.0) : "\(Int(mgdL))"
    }

    // MARK: - Alerts Tab

    private var alertsTab: some View {
        Form {
            Section {
                Text("Thresholds define color zones and optional notifications. Values must stay ordered: Urgent Low < Low < High < Urgent High.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Urgent High") {
                Toggle("Alert when urgently high", isOn: $alertUrgentHigh)
                    .onChange(of: alertUrgentHigh) { _, v in monitor.alertUrgentHighEnabled = v }
                thresholdSlider(value: $urgentHighMgdL, range: 181...400, label: "Urgent High") { newVal in
                    urgentHighMgdL = max(newVal, alertHighMgdL + minGap)
                    monitor.alertUrgentHighThresholdMgdL = urgentHighMgdL
                }
            }
            Section("High") {
                Toggle("Alert when high", isOn: $alertHighEnabled)
                    .onChange(of: alertHighEnabled) { _, v in monitor.alertHighEnabled = v }
                thresholdSlider(value: $alertHighMgdL, range: 120...399, label: "High") { newVal in
                    alertHighMgdL = min(max(newVal, alertLowMgdL + minGap), urgentHighMgdL - minGap)
                    monitor.alertHighThresholdMgdL = alertHighMgdL
                }
            }
            Section("Low") {
                Toggle("Alert when low", isOn: $alertLowEnabled)
                    .onChange(of: alertLowEnabled) { _, v in monitor.alertLowEnabled = v }
                thresholdSlider(value: $alertLowMgdL, range: 56...180, label: "Low") { newVal in
                    alertLowMgdL = min(max(newVal, urgentLowMgdL + minGap), alertHighMgdL - minGap)
                    monitor.alertLowThresholdMgdL = alertLowMgdL
                }
            }
            Section("Urgent Low") {
                Toggle("Alert when urgently low", isOn: $alertUrgentLow)
                    .onChange(of: alertUrgentLow) { _, v in monitor.alertUrgentLowEnabled = v }
                thresholdSlider(value: $urgentLowMgdL, range: 40...109, label: "Urgent Low") { newVal in
                    urgentLowMgdL = min(newVal, alertLowMgdL - minGap)
                    monitor.alertUrgentLowThresholdMgdL = urgentLowMgdL
                }
            }
            Section("Trend Alerts") {
                Toggle("Alert on rising fast (↑ ⇈)", isOn: $alertRisingFast)
                    .onChange(of: alertRisingFast) { _, v in monitor.alertRisingFastEnabled = v }
                Toggle("Alert on dropping fast (↓ ⇊)", isOn: $alertDroppingFast)
                    .onChange(of: alertDroppingFast) { _, v in monitor.alertDroppingFastEnabled = v }
            }
            Section("No Data") {
                Toggle("Alert when no new readings for 20 min", isOn: $alertStaleData)
                    .onChange(of: alertStaleData) { _, v in monitor.alertStaleDataEnabled = v }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Disclaimer Tab

    private var disclaimerTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Not a Medical Device", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text("""
                    DexBar is an unofficial convenience tool and is **not a medical device**. \
                    It is not approved, certified, or intended for use in medical diagnosis, \
                    treatment, or any clinical decision-making.
                    """)

                Text("""
                    Blood glucose data displayed by DexBar is sourced from the Dexcom Share \
                    service and may be delayed, inaccurate, or unavailable due to network \
                    conditions, sensor issues, or API changes beyond our control.
                    """)

                Text("""
                    **Always verify your blood sugar using your official Dexcom receiver, \
                    the Dexcom app, or another clinically approved method before making any \
                    medical decisions** — including adjusting insulin, food intake, or \
                    physical activity.
                    """)

                Text("""
                    Do not rely solely on this app. In an emergency, contact emergency \
                    services or a qualified healthcare professional immediately.
                    """)
                    .foregroundStyle(.secondary)

                Divider()

                Text("DexBar is not affiliated with or endorsed by Dexcom, Inc.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func thresholdSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        label: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let displayBinding = Binding<Double>(
            get: {
                unit == .mmolL ? value.wrappedValue / 18.0 : value.wrappedValue
            },
            set: { newVal in
                value.wrappedValue = unit == .mmolL ? newVal * 18.0 : newVal
                onChange(value.wrappedValue)
            }
        )
        let displayRange: ClosedRange<Double> = unit == .mmolL
            ? (range.lowerBound / 18.0)...(range.upperBound / 18.0)
            : range

        return HStack {
            Text(label)
            Slider(value: displayBinding, in: displayRange)
            Text(String(format: unit == .mmolL ? "%.1f" : "%.0f", displayBinding.wrappedValue))
                .monospacedDigit()
                .frame(width: 40)
            Text(unit.rawValue)
                .foregroundStyle(.secondary)
        }
    }

    private func loadPassword() {
        password = (try? KeychainService.load(key: "password")) ?? ""
        // Sync AppStorage values to monitor
        monitor.unit = unit
        monitor.alertHighEnabled = alertHighEnabled
        monitor.alertHighThresholdMgdL = alertHighMgdL
        monitor.alertLowEnabled = alertLowEnabled
        monitor.alertLowThresholdMgdL = alertLowMgdL
        monitor.alertRisingFastEnabled = alertRisingFast
        monitor.alertDroppingFastEnabled = alertDroppingFast
    }

    private func connect() async {
        isConnecting = true
        connectionStatus = ""
        do {
            try KeychainService.save(key: "password", value: password)
        } catch {
            connectionStatus = "Keychain error"
            isConnecting = false
            return
        }
        await monitor.start(username: username, password: password, region: region)
        isConnecting = false
        switch monitor.state {
        case .connected:
            connectionStatus = "✓ Connected"
        case .error(let msg):
            connectionStatus = msg
        default:
            connectionStatus = ""
        }
    }

    // MARK: - Updates Tab

    private var updatesTab: some View {
        Form {
            Section("Automatic Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { sparkle.updater.automaticallyChecksForUpdates },
                    set: { sparkle.updater.automaticallyChecksForUpdates = $0 }
                ))
                Toggle("Automatically download updates", isOn: Binding(
                    get: { sparkle.updater.automaticallyDownloadsUpdates },
                    set: { sparkle.updater.automaticallyDownloadsUpdates = $0 }
                ))
            }
            Section {
                Button("Check for Updates Now") {
                    sparkle.updater.checkForUpdates()
                }
                .disabled(!sparkle.updater.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }
}
