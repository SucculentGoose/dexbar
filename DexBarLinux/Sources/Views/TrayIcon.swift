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
    private var onToggleOverlay: (() -> Void)?
    private var iconCounter = 0

    // Directory where we write per-update SVG icon files.
    private let iconDir: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/dexbar/icons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init(monitor: GlucoseMonitorLinux,
         onTogglePopup: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onToggleOverlay: @escaping () -> Void) {
        self.monitor = monitor
        self.onTogglePopup = onTogglePopup
        self.onOpenSettings = onOpenSettings
        self.onToggleOverlay = onToggleOverlay

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
        let label: String
        if let reading = monitor.currentReading {
            let value = reading.displayValue(unit: monitor.unit)
            let arrow = reading.trend.arrow
            label = monitor.isStale ? "⚠ \(value)" : "\(value) \(arrow)"
        } else {
            switch monitor.state {
            case .idle:      label = "---"
            case .loading:   label = "…"
            case .connected: label = "---"
            case .error:     label = "⚠"
            }
        }
        setIconLabel(label)
    }

    // MARK: - Private

    /// Writes a 22×22 SVG icon with the glucose value on top and trend arrow below.
    /// KDE Plasma constrains all SNI icons to a square tray slot, so wide icons get squished.
    private func setIconLabel(_ text: String) {
        iconCounter += 1
        let iconName = "dexbar-\(iconCounter)"
        let svgFile  = iconDir.appendingPathComponent("\(iconName).svg")

        // Split "165 →" into value + arrow
        let parts     = text.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
        let valuePart = parts.first ?? text
        let arrowPart = parts.count > 1 ? parts.last! : ""

        // Font size: shrink for longer values (mmol/L can be "22.2")
        let valueFontSize = valuePart.count >= 4 ? 8 : 10

        let svg: String
        if arrowPart.isEmpty {
            svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22">
              <text x="11" y="15" font-family="sans-serif" font-size="12"
                    font-weight="bold" fill="white" text-anchor="middle">\(valuePart)</text>
            </svg>
            """
        } else {
            svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22">
              <text x="11" y="11" font-family="sans-serif" font-size="\(valueFontSize)"
                    font-weight="bold" fill="white" text-anchor="middle">\(valuePart)</text>
              <text x="11" y="20" font-family="sans-serif" font-size="9"
                    fill="#88ccff" text-anchor="middle">\(arrowPart)</text>
            </svg>
            """
        }

        try? svg.write(to: svgFile, atomically: true, encoding: .utf8)
        app_indicator_set_icon_full(indicator, iconName, text)

        if iconCounter > 1 {
            let oldFile = iconDir.appendingPathComponent("dexbar-\(iconCounter - 1).svg")
            try? FileManager.default.removeItem(at: oldFile)
        }
    }

    private func setupMenu() {
        let menu = gtk_menu_new()!

        let refreshItem  = gtk_menu_item_new_with_label("Refresh Now")!
        let overlayItem  = gtk_menu_item_new_with_label("Toggle Status Overlay")!
        let settingsItem = gtk_menu_item_new_with_label("Open Settings")!
        let sepItem      = gtk_separator_menu_item_new()!
        let quitItem     = gtk_menu_item_new_with_label("Quit")!

        gtk_menu_shell_append(asMenuShell(menu), refreshItem)
        gtk_menu_shell_append(asMenuShell(menu), overlayItem)
        gtk_menu_shell_append(asMenuShell(menu), settingsItem)
        gtk_menu_shell_append(asMenuShell(menu), sepItem)
        gtk_menu_shell_append(asMenuShell(menu), quitItem)

        gtkConnect(refreshItem, signal: "activate") { [weak self] in
            guard let monitor = self?.monitor else { return }
            Task { @MainActor in await monitor.refreshNow() }
        }
        gtkConnect(overlayItem,  signal: "activate") { [weak self] in self?.onToggleOverlay?() }
        gtkConnect(settingsItem, signal: "activate") { [weak self] in self?.onOpenSettings?() }
        gtkConnect(quitItem,     signal: "activate") { gtk_main_quit() }

        gtk_widget_show_all(menu)
        app_indicator_set_menu(indicator, asMenu(menu))
    }
}
#endif
