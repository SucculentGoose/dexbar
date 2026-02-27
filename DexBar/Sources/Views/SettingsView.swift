import SwiftUI

struct SettingsView: View {
    @Environment(GlucoseMonitor.self) private var monitor

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
    @AppStorage("alertHighEnabled") private var alertHighEnabled = true
    @AppStorage("alertHighMgdL") private var alertHighMgdL = 180.0
    @AppStorage("alertLowEnabled") private var alertLowEnabled = true
    @AppStorage("alertLowMgdL") private var alertLowMgdL = 70.0
    @AppStorage("alertRisingFastEnabled") private var alertRisingFast = true
    @AppStorage("alertDroppingFastEnabled") private var alertDroppingFast = true

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
        Form {
            Section("Units") {
                Picker("Blood sugar unit", selection: $unitRaw) {
                    ForEach(GlucoseUnit.allCases, id: \.rawValue) { u in
                        Text(u.rawValue).tag(u.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: unitRaw) { _, new in
                    monitor.unit = GlucoseUnit(rawValue: new) ?? .mgdL
                }
            }
            Section("Refresh Interval") {
                Picker("Refresh every", selection: $refreshMinutes) {
                    Text("1 minute").tag(1.0)
                    Text("2 minutes").tag(2.0)
                    Text("5 minutes").tag(5.0)
                    Text("10 minutes").tag(10.0)
                    Text("15 minutes").tag(15.0)
                }
                .onChange(of: refreshMinutes) { _, new in
                    monitor.updateRefreshInterval(new * 60)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Alerts Tab

    private var alertsTab: some View {
        Form {
            Section("High Alert") {
                Toggle("Alert when above", isOn: $alertHighEnabled)
                    .onChange(of: alertHighEnabled) { _, v in monitor.alertHighEnabled = v }
                if alertHighEnabled {
                    thresholdSlider(
                        value: $alertHighMgdL,
                        range: 120...400,
                        label: "High threshold"
                    ) { monitor.alertHighThresholdMgdL = $0 }
                }
            }
            Section("Low Alert") {
                Toggle("Alert when below", isOn: $alertLowEnabled)
                    .onChange(of: alertLowEnabled) { _, v in monitor.alertLowEnabled = v }
                if alertLowEnabled {
                    thresholdSlider(
                        value: $alertLowMgdL,
                        range: 40...120,
                        label: "Low threshold"
                    ) { monitor.alertLowThresholdMgdL = $0 }
                }
            }
            Section("Trend Alerts") {
                Toggle("Alert on rising fast (↑ ⇈)", isOn: $alertRisingFast)
                    .onChange(of: alertRisingFast) { _, v in monitor.alertRisingFastEnabled = v }
                Toggle("Alert on dropping fast (↓ ⇊)", isOn: $alertDroppingFast)
                    .onChange(of: alertDroppingFast) { _, v in monitor.alertDroppingFastEnabled = v }
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
}
