#if canImport(CDbusmenu)
import CDbusmenu
import CGtk4
import DexBarCore
import Foundation

/// System tray icon using D-Bus StatusNotifierItem + libdbusmenu-glib.
/// Replaces the old libayatana-appindicator3 implementation for GTK4 compatibility.
@MainActor
final class TrayIcon {
    private weak var monitor: GlucoseMonitorLinux?
    private var onTogglePopup: (() -> Void)?
    private var onOpenSettings: (() -> Void)?
    private var iconCounter = 0

    // D-Bus
    private var busOwnerId: guint = 0
    private var connection: OpaquePointer?  // GDBusConnection
    private var registrationId: guint = 0

    // Dbusmenu
    private var menuServer: UnsafeMutablePointer<DbusmenuServer>?
    private var updateMenuItem: UnsafeMutablePointer<DbusmenuMenuitem>?
    private var updateSepItem: UnsafeMutablePointer<DbusmenuMenuitem>?

    // Current icon state
    private var currentIconName: String = "dialog-information"

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

        setupDbusmenu()
        registerOnSessionBus()
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

    // MARK: - D-Bus StatusNotifierItem

    /// The SNI D-Bus interface XML introspection data.
    private static let sniInterfaceXML: String = """
    <node>
      <interface name="org.kde.StatusNotifierItem">
        <property name="Category" type="s" access="read"/>
        <property name="Id" type="s" access="read"/>
        <property name="Title" type="s" access="read"/>
        <property name="Status" type="s" access="read"/>
        <property name="IconName" type="s" access="read"/>
        <property name="IconThemePath" type="s" access="read"/>
        <property name="Menu" type="o" access="read"/>
        <signal name="NewIcon"/>
        <signal name="NewTitle"/>
        <method name="Activate">
          <arg name="x" type="i" direction="in"/>
          <arg name="y" type="i" direction="in"/>
        </method>
      </interface>
    </node>
    """

    private func registerOnSessionBus() {
        let pid = getpid()
        let busName = "org.kde.StatusNotifierItem-\(pid)-1"

        busOwnerId = g_bus_own_name(
            G_BUS_TYPE_SESSION,
            busName,
            G_BUS_NAME_OWNER_FLAGS_NONE,
            { connection, _, userData in
                // bus acquired
                guard let userData else { return }
                let tray = Unmanaged<TrayIcon>.fromOpaque(userData).takeUnretainedValue()
                tray.onBusAcquired(connection: connection!)
            },
            { _, _, userData in
                // name acquired — register with StatusNotifierWatcher
                guard let userData else { return }
                let tray = Unmanaged<TrayIcon>.fromOpaque(userData).takeUnretainedValue()
                tray.registerWithWatcher()
            },
            nil, // name lost
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }

    private func onBusAcquired(connection: OpaquePointer) {
        self.connection = connection

        var error: UnsafeMutablePointer<GError>?
        guard let nodeInfo = g_dbus_node_info_new_for_xml(Self.sniInterfaceXML, &error) else {
            if let error { g_error_free(error) }
            return
        }
        defer { g_dbus_node_info_unref(nodeInfo) }

        guard let interfaceInfo = nodeInfo.pointee.interfaces?.pointee else { return }

        var vtable = GDBusInterfaceVTable(
            method_call: { connection, _, _, _, methodName, parameters, invocation, userData in
                guard let userData, let methodName else { return }
                let tray = Unmanaged<TrayIcon>.fromOpaque(userData).takeUnretainedValue()
                let method = String(cString: methodName)
                if method == "Activate" {
                    MainActor.assumeIsolated {
                        tray.onTogglePopup?()
                    }
                }
                g_dbus_method_invocation_return_value(invocation, nil)
            },
            get_property: { connection, _, _, _, propertyName, error, userData -> OpaquePointer? in
                guard let userData, let propertyName else { return nil }
                let tray = Unmanaged<TrayIcon>.fromOpaque(userData).takeUnretainedValue()
                let prop = String(cString: propertyName)
                switch prop {
                case "Category":      return g_variant_new_string("ApplicationStatus")
                case "Id":            return g_variant_new_string("dexbar")
                case "Title":         return g_variant_new_string("DexBar")
                case "Status":        return g_variant_new_string("Active")
                case "IconName":      return g_variant_new_string(tray.currentIconName)
                case "IconThemePath": return g_variant_new_string(tray.iconDir.path)
                case "Menu":          return g_variant_new_object_path("/MenuBar")
                default:              return nil
                }
            },
            set_property: nil,
            padding: (nil, nil, nil, nil, nil, nil, nil, nil)
        )

        let raw = Unmanaged.passUnretained(self).toOpaque()
        registrationId = g_dbus_connection_register_object(
            connection,
            "/StatusNotifierItem",
            interfaceInfo,
            &vtable,
            raw,
            nil,
            &error
        )
        if let error { g_error_free(error) }
    }

    private func registerWithWatcher() {
        guard let connection else { return }
        let pid = getpid()
        let serviceName = "org.kde.StatusNotifierItem-\(pid)-1"

        // Build the GVariant "(s)" tuple manually since g_variant_new is variadic
        let strVariant = g_variant_new_string(serviceName)
        let tupleChildren: [OpaquePointer?] = [strVariant]
        let paramVariant = tupleChildren.withUnsafeBufferPointer { buf -> OpaquePointer? in
            let mutable = UnsafeMutablePointer(mutating: buf.baseAddress!)
            return g_variant_new_tuple(mutable, 1)
        }

        g_dbus_connection_call(
            connection,
            "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher",
            "org.kde.StatusNotifierWatcher",
            "RegisterStatusNotifierItem",
            paramVariant,
            nil,
            G_DBUS_CALL_FLAGS_NONE,
            -1,
            nil, nil, nil
        )
    }

    private func emitNewIcon() {
        guard let connection else { return }
        g_dbus_connection_emit_signal(
            connection,
            nil,
            "/StatusNotifierItem",
            "org.kde.StatusNotifierItem",
            "NewIcon",
            nil,
            nil
        )
    }

    // MARK: - Dbusmenu

    private func setupDbusmenu() {
        menuServer = dbusmenu_server_new("/MenuBar")
        let root = dbusmenu_menuitem_new()

        // Update available item — hidden until an update is found
        let updateItem = dbusmenu_menuitem_new()!
        dbusmenu_menuitem_property_set(updateItem, DBUSMENU_MENUITEM_PROP_LABEL, "Update Available")
        dbusmenu_menuitem_property_set_bool(updateItem, DBUSMENU_MENUITEM_PROP_VISIBLE, 0)
        dbusmenu_menuitem_child_append(root, updateItem)
        self.updateMenuItem = updateItem

        let updateSep = dbusmenu_menuitem_new()!
        dbusmenu_menuitem_property_set(updateSep, DBUSMENU_MENUITEM_PROP_TYPE, DBUSMENU_CLIENT_TYPES_SEPARATOR)
        dbusmenu_menuitem_property_set_bool(updateSep, DBUSMENU_MENUITEM_PROP_VISIBLE, 0)
        dbusmenu_menuitem_child_append(root, updateSep)
        self.updateSepItem = updateSep

        let statusItem = dbusmenu_menuitem_new()!
        dbusmenu_menuitem_property_set(statusItem, DBUSMENU_MENUITEM_PROP_LABEL, "Show Status")
        dbusmenu_menuitem_child_append(root, statusItem)
        connectItemActivated(statusItem) { [weak self] in self?.onTogglePopup?() }

        let refreshItem = dbusmenu_menuitem_new()!
        dbusmenu_menuitem_property_set(refreshItem, DBUSMENU_MENUITEM_PROP_LABEL, "Refresh Now")
        dbusmenu_menuitem_child_append(root, refreshItem)
        connectItemActivated(refreshItem) { [weak self] in
            guard let monitor = self?.monitor else { return }
            Task { @MainActor in await monitor.refreshNow() }
        }

        let settingsItem = dbusmenu_menuitem_new()!
        dbusmenu_menuitem_property_set(settingsItem, DBUSMENU_MENUITEM_PROP_LABEL, "Open Settings")
        dbusmenu_menuitem_child_append(root, settingsItem)
        connectItemActivated(settingsItem) { [weak self] in self?.onOpenSettings?() }

        let sep = dbusmenu_menuitem_new()!
        dbusmenu_menuitem_property_set(sep, DBUSMENU_MENUITEM_PROP_TYPE, DBUSMENU_CLIENT_TYPES_SEPARATOR)
        dbusmenu_menuitem_child_append(root, sep)

        let quitItem = dbusmenu_menuitem_new()!
        dbusmenu_menuitem_property_set(quitItem, DBUSMENU_MENUITEM_PROP_LABEL, "Quit")
        dbusmenu_menuitem_child_append(root, quitItem)
        connectItemActivated(quitItem) {
            g_main_loop_quit(mainLoop)
        }

        dbusmenu_server_set_root(menuServer, root)
    }

    /// Connects the "item-activated" signal on a DbusmenuMenuitem.
    private func connectItemActivated(_ item: UnsafeMutablePointer<DbusmenuMenuitem>, _ action: @escaping () -> Void) {
        let cb = GtkCallback(action)
        let raw: gpointer = UnsafeMutableRawPointer(item)
        g_signal_connect_data(
            raw, "item-activated",
            unsafeBitCast(dbusmenuActivatedTrampoline, to: GCallback.self),
            cb.retained(), nil, GConnectFlags(rawValue: 0)
        )
    }

    // MARK: - Icon rendering

    // SVG canvas size — SNI hosts (KDE Plasma) render at panel height, so we
    // use a large canvas and let SVG scale down cleanly.
    private let iconSize = 128

    /// Writes a 128×128 SVG icon with glucose value, trend arrow, and delta.
    private func setIconReading(_ value: String, arrow: String, delta: String?, color: String) {
        iconCounter += 1
        let iconName = "dexbar-\(iconCounter)"
        let svgFile  = iconDir.appendingPathComponent("\(iconName).svg")
        let sz = iconSize

        // Shrink font for long mmol/L values like "22.2"
        let valueFontSize = value.count >= 4 ? 46 : 58

        let svg: String
        if arrow.isEmpty {
            // Error / idle / loading: single centered line in muted color
            svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="\(sz)" height="\(sz)">
              <text x="64" y="80" font-family="sans-serif" font-size="58"
                    font-weight="bold" fill="\(color)" text-anchor="middle">\(value)</text>
            </svg>
            """
        } else if let delta, !delta.isEmpty {
            // Full display: value on top, arrow to the right, delta below
            let arrowSVG = arrowPath(for: arrow, color: color, x: 108, y: 14)
            svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="\(sz)" height="\(sz)">
              <text x="40" y="66" font-family="sans-serif" font-size="\(valueFontSize)"
                    font-weight="bold" fill="\(color)" text-anchor="middle">\(value)</text>
              \(arrowSVG)
              <text x="64" y="118" font-family="sans-serif" font-size="44"
                    fill="\(color)" fill-opacity="0.8" text-anchor="middle">\(delta)</text>
            </svg>
            """
        } else {
            // No delta yet: centered value with arrow
            let arrowSVG = arrowPath(for: arrow, color: color, x: 108, y: 30)
            svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="\(sz)" height="\(sz)">
              <text x="40" y="84" font-family="sans-serif" font-size="\(valueFontSize)"
                    font-weight="bold" fill="\(color)" text-anchor="middle">\(value)</text>
              \(arrowSVG)
            </svg>
            """
        }

        try? svg.write(to: svgFile, atomically: true, encoding: .utf8)

        currentIconName = iconName
        emitNewIcon()

        if iconCounter > 1 {
            let oldFile = iconDir.appendingPathComponent("dexbar-\(iconCounter - 1).svg")
            try? FileManager.default.removeItem(at: oldFile)
        }
    }

    /// SVG path arrow scaled for 128×128 canvas, positioned at (x, y).
    private func arrowPath(for arrow: String, color: String, x: Int, y: Int) -> String {
        // Arrow body is roughly 35×52 pixels
        switch arrow {
        case "⇈":
            return "<g transform=\"translate(\(x-17),\(y))\" fill=\"\(color)\"><polygon points=\"17,0 0,23 11,23 11,40 23,40 23,23 34,23\"/><polygon points=\"17,17 0,40 11,40 11,57 23,57 23,40 34,40\" opacity=\"0.5\"/></g>"
        case "↑":
            return "<polygon points=\"\(x),\(y) \(x-17),\(y+29) \(x-6),\(y+29) \(x-6),\(y+52) \(x+6),\(y+52) \(x+6),\(y+29) \(x+17),\(y+29)\" fill=\"\(color)\"/>"
        case "↗":
            return "<polygon points=\"\(x+17),\(y) \(x-12),\(y) \(x-0),\(y+12) \(x-17),\(y+29) \(x-6),\(y+40) \(x+12),\(y+23) \(x+17),\(y+29)\" fill=\"\(color)\"/>"
        case "→":
            return "<polygon points=\"\(x+17),\(y+23) \(x-6),\(y+6) \(x-6),\(y+17) \(x-23),\(y+17) \(x-23),\(y+29) \(x-6),\(y+29) \(x-6),\(y+40)\" fill=\"\(color)\"/>"
        case "↘":
            return "<polygon points=\"\(x+17),\(y+40) \(x-12),\(y+40) \(x-0),\(y+29) \(x-17),\(y+12) \(x-6),\(y) \(x+12),\(y+17) \(x+17),\(y+12)\" fill=\"\(color)\"/>"
        case "↓":
            return "<polygon points=\"\(x),\(y+52) \(x-17),\(y+23) \(x-6),\(y+23) \(x-6),\(y) \(x+6),\(y) \(x+6),\(y+23) \(x+17),\(y+23)\" fill=\"\(color)\"/>"
        case "⇊":
            return "<g transform=\"translate(\(x-17),\(y))\" fill=\"\(color)\"><polygon points=\"17,57 0,34 11,34 11,17 23,17 23,34 34,34\"/><polygon points=\"17,40 0,17 11,17 11,0 23,0 23,17 34,17\" opacity=\"0.5\"/></g>"
        default:
            return ""
        }
    }

    // MARK: - Update menu items

    /// Reveals the "Install Update" menu item.
    func showUpdateAvailable(version: String, onInstall: @escaping () -> Void) {
        guard let item = updateMenuItem, let sep = updateSepItem else { return }
        dbusmenu_menuitem_property_set(item, DBUSMENU_MENUITEM_PROP_LABEL, "⬆ Install Update: v\(version)")
        dbusmenu_menuitem_property_set_bool(item, DBUSMENU_MENUITEM_PROP_VISIBLE, 1)
        dbusmenu_menuitem_property_set_bool(sep, DBUSMENU_MENUITEM_PROP_VISIBLE, 1)
        connectItemActivated(item) { onInstall() }
    }

    /// Updates the label of the update menu item.
    func setUpdateStatus(_ text: String) {
        guard let item = updateMenuItem else { return }
        dbusmenu_menuitem_property_set(item, DBUSMENU_MENUITEM_PROP_LABEL, text)
    }
}

private let dbusmenuActivatedTrampoline: @convention(c) (OpaquePointer?, guint, gpointer?) -> Void = { _, _, userData in
    guard let ptr = userData else { return }
    Unmanaged<GtkCallback>.fromOpaque(ptr).takeUnretainedValue().action()
}
#endif
