#if canImport(CAppIndicator)
import CAppIndicator
import CGtk3
import DexBarCore
import Foundation

/// System tray icon using libayatana-appindicator3 (GTK3/StatusNotifierItem).
/// On KDE Plasma 6 this communicates via the StatusNotifierItem D-Bus protocol.
/// Because KDE's SNI implementation does not render app_indicator_set_label,
/// we generate a tiny SVG with the glucose value baked in as the icon itself.
@MainActor
final class TrayIcon {
    private var indicator: UnsafeMutablePointer<AppIndicator>?
    private weak var monitor: GlucoseMonitorLinux?
    private var onTogglePopup: (() -> Void)?
    private var onOpenSettings: (() -> Void)?
    private var iconCounter = 0
    private var updateMenuItem: GWidget?
    private var updateSepItem: GWidget?

    // Directory where we write per-update SVG icon files.
    private let iconDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/dexbar/icons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init(monitor: GlucoseMonitorLinux,
         onTogglePopup: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.onTogglePopup = onTogglePopup
        self.onOpenSettings = onOpenSettings

        indicator = app_indicator_new(
            "com.dexbar.app",
            "dialog-information",
            APP_INDICATOR_CATEGORY_APPLICATION_STATUS
        )
        app_indicator_set_status(indicator, APP_INDICATOR_STATUS_ACTIVE)
        app_indicator_set_icon_theme_path(indicator, iconDir.path)

        setupMenu()
        update()
    }

    // MARK: - Public

    func update() {
        guard let monitor else { return }
        if let reading = monitor.currentReading {
            let value = reading.displayValue(unit: monitor.unit)
            let arrow = reading.trend.arrow
            let delta = monitor.formattedDelta(unit: monitor.unit)
            if monitor.isStale {
                setIconReading("⚠ \(value)", arrow: "", delta: nil, color: "#AAAAAA")
            } else {
                setIconReading(value, arrow: arrow, delta: delta, color: monitor.readingColor)
            }
        } else {
            let label: String
            switch monitor.state {
            case .idle:      label = "---"
            case .loading:   label = "…"
            case .connected: label = "---"
            case .error:     label = "⚠"
            }
            setIconReading(label, arrow: "", delta: nil, color: "#AAAAAA")
        }
    }

    // MARK: - Private

    /// Writes a 22×22 SVG icon with glucose value + trend arrow on one line (colored by range),
    /// and delta (e.g. "+3") on the line below in the same color.
    private func setIconReading(_ value: String, arrow: String, delta: String?, color: String) {
        iconCounter += 1
        let iconName = "dexbar-\(iconCounter)"
        let svgFile  = iconDir.appendingPathComponent("\(iconName).svg")

        let accessLabel = [value, arrow, delta].compactMap { $0 }.joined(separator: " ")

        // Shrink font for long mmol/L values like "22.2"
        let valueFontSize = value.count >= 4 ? 8 : 10

        let svg: String
        if arrow.isEmpty {
            // Error / idle / loading: single centered line in muted color
            svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22">
              <text x="11" y="15" font-family="sans-serif" font-size="10"
                    font-weight="bold" fill="\(color)" text-anchor="middle">\(value)</text>
            </svg>
            """
        } else if let delta, !delta.isEmpty {
            // Full display: value+arrow on top line, delta on bottom line
            svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22">
              <text x="11" y="12" font-family="sans-serif" font-size="\(valueFontSize)"
                    font-weight="bold" fill="\(color)" text-anchor="middle">\(value)\(arrow)</text>
              <text x="11" y="21" font-family="sans-serif" font-size="8"
                    fill="\(color)" text-anchor="middle">\(delta)</text>
            </svg>
            """
        } else {
            // No delta yet (only one reading): single centered line
            svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22">
              <text x="11" y="15" font-family="sans-serif" font-size="\(valueFontSize)"
                    font-weight="bold" fill="\(color)" text-anchor="middle">\(value)\(arrow)</text>
            </svg>
            """
        }

        try? svg.write(to: svgFile, atomically: true, encoding: .utf8)
        app_indicator_set_icon_full(indicator, iconName, accessLabel)

        if iconCounter > 1 {
            let oldFile = iconDir.appendingPathComponent("dexbar-\(iconCounter - 1).svg")
            try? FileManager.default.removeItem(at: oldFile)
        }
    }

    private func setupMenu() {
        let menu = gtk_menu_new()!

        // Update available item — hidden until an update is found
        let updateItem   = gtk_menu_item_new_with_label("Update Available")!
        let updateSep    = gtk_separator_menu_item_new()!
        let statusItem   = gtk_menu_item_new_with_label("Show Status")!
        let refreshItem  = gtk_menu_item_new_with_label("Refresh Now")!
        let settingsItem = gtk_menu_item_new_with_label("Open Settings")!
        let sepItem      = gtk_separator_menu_item_new()!
        let quitItem     = gtk_menu_item_new_with_label("Quit")!

        gtk_menu_shell_append(asMenuShell(menu), updateItem)
        gtk_menu_shell_append(asMenuShell(menu), updateSep)
        gtk_menu_shell_append(asMenuShell(menu), statusItem)
        gtk_menu_shell_append(asMenuShell(menu), refreshItem)
        gtk_menu_shell_append(asMenuShell(menu), settingsItem)
        gtk_menu_shell_append(asMenuShell(menu), sepItem)
        gtk_menu_shell_append(asMenuShell(menu), quitItem)

        gtkConnect(statusItem, signal: "activate") { [weak self] in self?.onTogglePopup?() }
        gtkConnect(refreshItem, signal: "activate") { [weak self] in
            guard let monitor = self?.monitor else { return }
            Task { @MainActor in await monitor.refreshNow() }
        }
        gtkConnect(settingsItem, signal: "activate") { [weak self] in self?.onOpenSettings?() }
        gtkConnect(quitItem,     signal: "activate") { gtk_main_quit() }

        gtk_widget_show_all(menu)

        // Hide update items until an update is actually available
        gtk_widget_hide(updateItem)
        gtk_widget_hide(updateSep)
        self.updateMenuItem = updateItem
        self.updateSepItem  = updateSep
        app_indicator_set_menu(indicator, asMenu(menu))
    }

    /// Reveals the "Install Update" menu item. Clicking it triggers the download+install+restart flow.
    func showUpdateAvailable(version: String, onInstall: @escaping () -> Void) {
        guard let item = updateMenuItem, let sep = updateSepItem else { return }
        gtk_menu_item_set_label(asMenuItem(item), "⬆ Install Update: v\(version)")
        gtkConnect(item, signal: "activate") { onInstall() }
        gtk_widget_show(item)
        gtk_widget_show(sep)
    }

    /// Updates the label of the update menu item (e.g. "Downloading… 45%", "Restarting…").
    func setUpdateStatus(_ text: String) {
        guard let item = updateMenuItem else { return }
        gtk_menu_item_set_label(asMenuItem(item), text)
    }
}
#endif
