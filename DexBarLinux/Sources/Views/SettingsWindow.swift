#if canImport(CGtk3)
import CGtk3
import DexBarCore
import Foundation

/// GTK3 settings window with four tabs: Account, Display, Alerts, About.
@MainActor
final class SettingsWindow {
    private var window: GWidget?
    private weak var monitor: GlucoseMonitorLinux?

    // Account tab
    private var usernameEntry: GWidget?
    private var passwordEntry: GWidget?
    private var regionCombo: GWidget?
    private var connectionStatusLabel: GWidget?

    // Display tab
    private var unitCombo: GWidget?
    private var refreshCombo: GWidget?
    private var coloredTrayCheck: GWidget?
    private var autoStartCheck: GWidget?

    // Alerts tab
    private var urgentHighCheck: GWidget?
    private var urgentHighSpin: GWidget?
    private var highCheck: GWidget?
    private var highSpin: GWidget?
    private var lowCheck: GWidget?
    private var lowSpin: GWidget?
    private var urgentLowCheck: GWidget?
    private var urgentLowSpin: GWidget?
    private var risingFastCheck: GWidget?
    private var droppingFastCheck: GWidget?
    private var staleDataCheck: GWidget?

    init(monitor: GlucoseMonitorLinux) {
        self.monitor = monitor
        buildWindow()
    }

    // MARK: - Public

    func show() {
        guard let win = window else { return }
        loadCurrentSettings()
        gtk_widget_show_all(win)
        gtk_window_present(asWindow(win))
    }

    func updateStatus() {
        guard let monitor else { return }
        gtk_label_set_text(asLabel(connectionStatusLabel), monitor.state.statusText)
    }

    // MARK: - Window construction

    private func buildWindow() {
        window = gtk_window_new(GTK_WINDOW_TOPLEVEL)
        gtk_window_set_title(asWindow(window), "DexBar Settings")
        gtkSetAppIcon(window)
        gtk_window_set_default_size(asWindow(window), 380, 440)
        gtk_window_set_resizable(asWindow(window), 0)

        gtkConnectDeleteHide(window) { [weak self] in
            if let win = self?.window { gtk_widget_hide(win) }
        }

        let notebook = gtk_notebook_new()
        containerAdd(window, notebook)

        gtk_notebook_append_page(asNotebook(notebook),
            buildAccountTab(), gtk_label_new("Account"))
        gtk_notebook_append_page(asNotebook(notebook),
            buildDisplayTab(), gtk_label_new("Display"))
        gtk_notebook_append_page(asNotebook(notebook),
            buildAlertsTab(), gtk_label_new("Alerts"))
        gtk_notebook_append_page(asNotebook(notebook),
            buildAboutTab(), gtk_label_new("About"))
    }

    // MARK: Account tab

    private func buildAccountTab() -> GWidget? {
        let grid = gtk_grid_new()
        gtk_grid_set_row_spacing(asGrid(grid), 8)
        gtk_grid_set_column_spacing(asGrid(grid), 8)
        setMargins(grid, 12)

        var row: gint = 0

        attachLabel(grid, "Dexcom Username", col: 0, row: row)
        usernameEntry = gtk_entry_new()
        gtk_grid_attach(asGrid(grid), usernameEntry, 1, row, 1, 1)
        row += 1

        attachLabel(grid, "Password", col: 0, row: row)
        passwordEntry = gtk_entry_new()
        gtk_entry_set_visibility(asEntry(passwordEntry), 0)
        gtk_grid_attach(asGrid(grid), passwordEntry, 1, row, 1, 1)
        row += 1

        attachLabel(grid, "Region", col: 0, row: row)
        regionCombo = gtk_combo_box_text_new()
        for region in DexcomRegion.allCases {
            gtk_combo_box_text_append_text(asComboText(regionCombo), region.rawValue)
        }
        gtk_grid_attach(asGrid(grid), regionCombo, 1, row, 1, 1)
        row += 1

        let connectBtn = gtk_button_new_with_label("Connect")
        gtkConnect(connectBtn, signal: "clicked") { [weak self] in self?.handleConnect() }
        gtk_grid_attach(asGrid(grid), connectBtn, 1, row, 1, 1)
        row += 1

        let disconnectBtn = gtk_button_new_with_label("Disconnect")
        gtkConnect(disconnectBtn, signal: "clicked") { [weak self] in self?.monitor?.stop() }
        gtk_grid_attach(asGrid(grid), disconnectBtn, 1, row, 1, 1)
        row += 1

        connectionStatusLabel = gtk_label_new("Not connected")
        gtk_label_set_xalign(asLabel(connectionStatusLabel), 0)
        gtk_grid_attach(asGrid(grid), connectionStatusLabel, 0, row, 2, 1)

        return grid
    }

    // MARK: Display tab

    private func buildDisplayTab() -> GWidget? {
        let grid = gtk_grid_new()
        gtk_grid_set_row_spacing(asGrid(grid), 8)
        gtk_grid_set_column_spacing(asGrid(grid), 8)
        setMargins(grid, 12)

        var row: gint = 0

        attachLabel(grid, "Units", col: 0, row: row)
        unitCombo = gtk_combo_box_text_new()
        for unit in GlucoseUnit.allCases {
            gtk_combo_box_text_append_text(asComboText(unitCombo), unit.rawValue)
        }
        gtkConnect(unitCombo, signal: "changed") { [weak self] in self?.saveDisplaySettings() }
        gtk_grid_attach(asGrid(grid), unitCombo, 1, row, 1, 1)
        row += 1

        attachLabel(grid, "Refresh Interval", col: 0, row: row)
        refreshCombo = gtk_combo_box_text_new()
        for (label, _) in refreshIntervalOptions {
            gtk_combo_box_text_append_text(asComboText(refreshCombo), label)
        }
        gtkConnect(refreshCombo, signal: "changed") { [weak self] in self?.saveDisplaySettings() }
        gtk_grid_attach(asGrid(grid), refreshCombo, 1, row, 1, 1)
        row += 1

        attachLabel(grid, "Launch at Login", col: 0, row: row)
        autoStartCheck = gtk_check_button_new()
        gtk_toggle_button_set_active(asToggle(autoStartCheck), AutoStart.isEnabled ? 1 : 0)
        gtkConnect(autoStartCheck, signal: "toggled") { [weak self] in self?.handleAutoStartToggle() }
        gtk_grid_attach(asGrid(grid), autoStartCheck, 1, row, 1, 1)
        row += 1

        attachLabel(grid, "Colored Tray Icon", col: 0, row: row)
        coloredTrayCheck = gtk_check_button_new()
        gtkConnect(coloredTrayCheck, signal: "toggled") { [weak self] in self?.saveDisplaySettings() }
        gtk_grid_attach(asGrid(grid), coloredTrayCheck, 1, row, 1, 1)

        return grid
    }

    // MARK: Alerts tab

    private func buildAlertsTab() -> GWidget? {
        let vbox = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
        setMargins(vbox, 12)

        let grid = gtk_grid_new()
        gtk_grid_set_row_spacing(asGrid(grid), 6)
        gtk_grid_set_column_spacing(asGrid(grid), 8)
        packStart(vbox, grid)

        var row: gint = 0
        (urgentHighCheck, urgentHighSpin) = alertRow(grid, label: "Urgent High (mg/dL)", row: row, default: 250)
        row += 1
        (highCheck, highSpin)             = alertRow(grid, label: "High (mg/dL)", row: row, default: 180)
        row += 1
        (lowCheck, lowSpin)               = alertRow(grid, label: "Low (mg/dL)", row: row, default: 70)
        row += 1
        (urgentLowCheck, urgentLowSpin)   = alertRow(grid, label: "Urgent Low (mg/dL)", row: row, default: 55)

        packStart(vbox, gtkSeparator())

        risingFastCheck   = checkRow(vbox, label: "Rising Fast alert")
        droppingFastCheck = checkRow(vbox, label: "Dropping Fast alert")
        staleDataCheck    = checkRow(vbox, label: "Stale Data alert (no reading for 20 min)")

        let saveAlerts: () -> Void = { [weak self] in self?.saveAlertSettings() }
        for w in [urgentHighCheck, highCheck, lowCheck, urgentLowCheck,
                  risingFastCheck, droppingFastCheck, staleDataCheck] {
            gtkConnect(w, signal: "toggled", saveAlerts)
        }
        for w in [urgentHighSpin, highSpin, lowSpin, urgentLowSpin] {
            gtkConnect(w, signal: "value-changed", saveAlerts)
        }

        return vbox
    }

    // MARK: About tab

    private func buildAboutTab() -> GWidget? {
        let vbox = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
        setMargins(vbox, 16)
        gtk_widget_set_halign(vbox, GTK_ALIGN_CENTER)
        gtk_widget_set_valign(vbox, GTK_ALIGN_CENTER)

        packStart(vbox, gtkLabel("DexBar"))
        packStart(vbox, gtkLabel("Linux Edition · v\(AppVersion.current)"))

        let desc = gtkLabel("Blood glucose readings from\nDexcom Share in your system tray.")
        gtk_label_set_justify(asLabel(desc), GTK_JUSTIFY_CENTER)
        packStart(vbox, desc)

        let link = gtk_link_button_new_with_label(
            "https://github.com/SucculentGoose/dexbar", "View on GitHub")!
        packStart(vbox, link)

        let disclaimer = gtkLabel("⚠️ Not a medical device.\nAlways verify readings with your CGM.")
        gtk_label_set_justify(asLabel(disclaimer), GTK_JUSTIFY_CENTER)
        packStart(vbox, disclaimer)

        return vbox
    }

    // MARK: - Helpers

    private func attachLabel(_ grid: GWidget?, _ text: String, col: gint, row: gint) {
        let lbl = gtkLabel(text)
        gtk_label_set_xalign(asLabel(lbl), 1.0)
        gtk_grid_attach(asGrid(grid), lbl, col, row, 1, 1)
    }

    private func alertRow(_ grid: GWidget?, label: String, row: gint, default val: Double) -> (GWidget?, GWidget?) {
        let check = gtk_check_button_new_with_label(label)
        gtk_grid_attach(asGrid(grid), check, 0, row, 1, 1)
        let spin = gtk_spin_button_new_with_range(40, 400, 5)
        gtk_spin_button_set_value(asSpin(spin), val)
        gtk_grid_attach(asGrid(grid), spin, 1, row, 1, 1)
        return (check, spin)
    }

    private func checkRow(_ vbox: GWidget?, label: String) -> GWidget? {
        let check = gtk_check_button_new_with_label(label)
        packStart(vbox, check)
        return check
    }

    private func setMargins(_ w: GWidget?, _ m: gint) {
        gtk_widget_set_margin_start(w, m)
        gtk_widget_set_margin_end(w, m)
        gtk_widget_set_margin_top(w, m)
        gtk_widget_set_margin_bottom(w, m)
    }

    // MARK: - Load / Save

    private func loadCurrentSettings() {
        guard let monitor else { return }
        let defaults = UserDefaults.standard

        if let username = defaults.string(forKey: "dexcomUsername") {
            gtk_entry_set_text(asEntry(usernameEntry), username)
        }
        // Don't populate the password field with the real value — just show a placeholder
        // so the user knows a password is saved without exposing it.
#if canImport(CLibSecret)
        let hasSavedPassword = SecretServiceStorage.load(key: "password") != nil
#else
        let hasSavedPassword = defaults.string(forKey: "dexcomPasswordFallback") != nil
#endif
        if hasSavedPassword {
            gtk_entry_set_placeholder_text(asEntry(passwordEntry), "●●●●●●●● (saved)")
        }
        let regionIdx = DexcomRegion.allCases.firstIndex(of: monitor.region).map { gint($0) } ?? 0
        gtk_combo_box_set_active(asCombo(regionCombo), regionIdx)

        let unitIdx = GlucoseUnit.allCases.firstIndex(of: monitor.unit).map { gint($0) } ?? 0
        gtk_combo_box_set_active(asCombo(unitCombo), unitIdx)

        let refreshIdx = refreshIntervalOptions.firstIndex(where: { $0.1 == monitor.refreshInterval }).map { gint($0) } ?? 2
        gtk_combo_box_set_active(asCombo(refreshCombo), refreshIdx)

        gtk_toggle_button_set_active(asToggle(coloredTrayCheck), monitor.coloredTrayIcon ? 1 : 0)

        gtk_toggle_button_set_active(asToggle(urgentHighCheck), monitor.alertUrgentHighEnabled ? 1 : 0)
        gtk_spin_button_set_value(asSpin(urgentHighSpin), monitor.alertUrgentHighThresholdMgdL)
        gtk_toggle_button_set_active(asToggle(highCheck), monitor.alertHighEnabled ? 1 : 0)
        gtk_spin_button_set_value(asSpin(highSpin), monitor.alertHighThresholdMgdL)
        gtk_toggle_button_set_active(asToggle(lowCheck), monitor.alertLowEnabled ? 1 : 0)
        gtk_spin_button_set_value(asSpin(lowSpin), monitor.alertLowThresholdMgdL)
        gtk_toggle_button_set_active(asToggle(urgentLowCheck), monitor.alertUrgentLowEnabled ? 1 : 0)
        gtk_spin_button_set_value(asSpin(urgentLowSpin), monitor.alertUrgentLowThresholdMgdL)
        gtk_toggle_button_set_active(asToggle(risingFastCheck), monitor.alertRisingFastEnabled ? 1 : 0)
        gtk_toggle_button_set_active(asToggle(droppingFastCheck), monitor.alertDroppingFastEnabled ? 1 : 0)
        gtk_toggle_button_set_active(asToggle(staleDataCheck), monitor.alertStaleDataEnabled ? 1 : 0)

        gtk_label_set_text(asLabel(connectionStatusLabel), monitor.state.statusText)
    }

    private func handleConnect() {
        guard let monitor else { return }
        let username = String(cString: gtk_entry_get_text(asEntry(usernameEntry)!))
        let typedPassword = String(cString: gtk_entry_get_text(asEntry(passwordEntry)!))
        let regionIdx = gtk_combo_box_get_active(asCombo(regionCombo))
        let region = DexcomRegion.allCases[max(0, Int(regionIdx))]

        // If the field is empty, fall back to whatever is already saved in the keyring
        let password: String
        if !typedPassword.isEmpty {
            password = typedPassword
        } else {
#if canImport(CLibSecret)
            guard let saved = SecretServiceStorage.load(key: "password"), !saved.isEmpty else {
                gtk_label_set_text(asLabel(connectionStatusLabel), "Enter username and password")
                return
            }
            password = saved
#else
            guard let saved = UserDefaults.standard.string(forKey: "dexcomPasswordFallback"), !saved.isEmpty else {
                gtk_label_set_text(asLabel(connectionStatusLabel), "Enter username and password")
                return
            }
            password = saved
#endif
        }

        guard !username.isEmpty else {
            gtk_label_set_text(asLabel(connectionStatusLabel), "Enter username and password")
            return
        }

        UserDefaults.standard.set(username, forKey: "dexcomUsername")
        monitor.region = region

        if !typedPassword.isEmpty {
#if canImport(CLibSecret)
            _ = SecretServiceStorage.save(key: "password", value: password)
#else
            UserDefaults.standard.set(password, forKey: "dexcomPasswordFallback")
#endif
        }

        Task { @MainActor in
            await monitor.start(username: username, password: password, region: region)
            self.updateStatus()
        }
    }

    private func saveDisplaySettings() {
        guard let monitor else { return }
        let unitIdx = gtk_combo_box_get_active(asCombo(unitCombo))
        if unitIdx >= 0 { monitor.unit = GlucoseUnit.allCases[Int(unitIdx)] }
        let refreshIdx = gtk_combo_box_get_active(asCombo(refreshCombo))
        if refreshIdx >= 0 { monitor.updateRefreshInterval(refreshIntervalOptions[Int(refreshIdx)].1) }
        monitor.coloredTrayIcon = gtk_toggle_button_get_active(asToggle(coloredTrayCheck)) != 0
        monitor.onUpdate?()
    }

    private func saveAlertSettings() {
        guard let monitor else { return }
        monitor.alertUrgentHighEnabled = gtk_toggle_button_get_active(asToggle(urgentHighCheck)) != 0
        monitor.alertUrgentHighThresholdMgdL = gtk_spin_button_get_value(asSpin(urgentHighSpin))
        monitor.alertHighEnabled = gtk_toggle_button_get_active(asToggle(highCheck)) != 0
        monitor.alertHighThresholdMgdL = gtk_spin_button_get_value(asSpin(highSpin))
        monitor.alertLowEnabled = gtk_toggle_button_get_active(asToggle(lowCheck)) != 0
        monitor.alertLowThresholdMgdL = gtk_spin_button_get_value(asSpin(lowSpin))
        monitor.alertUrgentLowEnabled = gtk_toggle_button_get_active(asToggle(urgentLowCheck)) != 0
        monitor.alertUrgentLowThresholdMgdL = gtk_spin_button_get_value(asSpin(urgentLowSpin))
        monitor.alertRisingFastEnabled = gtk_toggle_button_get_active(asToggle(risingFastCheck)) != 0
        monitor.alertDroppingFastEnabled = gtk_toggle_button_get_active(asToggle(droppingFastCheck)) != 0
        monitor.alertStaleDataEnabled = gtk_toggle_button_get_active(asToggle(staleDataCheck)) != 0
    }

    private func handleAutoStartToggle() {
        if gtk_toggle_button_get_active(asToggle(autoStartCheck)) != 0 {
            AutoStart.enable()
        } else {
            AutoStart.disable()
        }
    }
}

// MARK: - Refresh interval options

private let refreshIntervalOptions: [(String, TimeInterval)] = [
    ("1 minute",    60),
    ("2 minutes",  120),
    ("5 minutes",  300),
    ("10 minutes", 600),
    ("15 minutes", 900),
]

#endif
