#if canImport(CGtk4)
import CGtk4
import DexBarCore
import Foundation

#if canImport(CGtk4LayerShell)
import CGtk4LayerShell
#endif

/// A small borderless always-on-top floating window showing the current glucose
/// reading in large text. Persists on screen like a HUD overlay.
@MainActor
final class StatusOverlay {
    private var window: GWidget?
    private var valueLabel: GWidget?
    private var deltaLabel: GWidget?
    private weak var monitor: GlucoseMonitorLinux?

    private let defaults = UserDefaults.standard
    private var isVisible: Bool {
        get { defaults.bool(forKey: "overlayVisible") }
        set { defaults.set(newValue, forKey: "overlayVisible") }
    }

    init(monitor: GlucoseMonitorLinux) {
        self.monitor = monitor
        buildWindow()
        if isVisible { show() }
    }

    // MARK: - Public

    func toggle() {
        guard let win = window else { return }
        if gtk_widget_is_visible(win) != 0 {
            gtk_widget_set_visible(win, 0)
            isVisible = false
        } else {
            show()
        }
    }

    var isShowing: Bool {
        guard let win = window else { return false }
        return gtk_widget_is_visible(win) != 0
    }

    func update() {
        guard let monitor, let win = window, gtk_widget_is_visible(win) != 0 else { return }

        let valueText: String
        let deltaText: String
        let color: String

        if let reading = monitor.currentReading {
            let value = reading.displayValue(unit: monitor.unit)
            let arrow = reading.trend.arrow
            valueText = "\(value) \(arrow)"

            if let delta = monitor.formattedDelta(unit: monitor.unit) {
                deltaText = delta
            } else {
                deltaText = ""
            }

            // Color based on range (uses monitor's configurable colors)
            color = monitor.readingColor
        } else {
            switch monitor.state {
            case .idle:      valueText = "---"; color = "#888888"
            case .loading:   valueText = "…";   color = "#888888"
            case .connected: valueText = "---"; color = "#888888"
            case .error:     valueText = "!";   color = "#ff4444"
            }
            deltaText = ""
        }

        let markup = "<span font='24' weight='bold' color='\(color)'>\(valueText)</span>"
        gtk_label_set_markup(asLabel(valueLabel), markup)

        if deltaText.isEmpty {
            gtk_widget_set_visible(deltaLabel, 0)
        } else {
            let deltaMarkup = "<span font='11' color='#aaaaaa'>\(deltaText)</span>"
            gtk_label_set_markup(asLabel(deltaLabel), deltaMarkup)
            gtk_widget_set_visible(deltaLabel, 1)
        }
    }

    // MARK: - Private

    private func show() {
        guard let win = window else { return }
        update()
        gtk_widget_set_visible(win, 1)
        isVisible = true
    }

    private func buildWindow() {
        window = gtk_window_new()
        guard let win = window else { return }

        gtk_window_set_decorated(asWindow(win), 0)
        gtk_window_set_resizable(asWindow(win), 0)
        gtk_window_set_title(asWindow(win), "DexBar Overlay")
        gtkSetAppIcon(win)

        // Transparent-ish dark background via opacity
        gtk_widget_set_opacity(win, 0.85)

#if canImport(CGtk4LayerShell)
        // Use layer shell for proper overlay positioning on Wayland
        gtk_layer_init_for_window(asWindow(win))
        gtk_layer_set_layer(asWindow(win), GTK_LAYER_SHELL_LAYER_OVERLAY)
        gtk_layer_set_anchor(asWindow(win), GTK_LAYER_SHELL_EDGE_TOP, 1)
        gtk_layer_set_anchor(asWindow(win), GTK_LAYER_SHELL_EDGE_RIGHT, 1)
        gtk_layer_set_margin(asWindow(win), GTK_LAYER_SHELL_EDGE_TOP, 38)
        gtk_layer_set_margin(asWindow(win), GTK_LAYER_SHELL_EDGE_RIGHT, 8)
#endif

        let vbox = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 2)
        gtk_widget_set_margin_start(vbox, 10)
        gtk_widget_set_margin_end(vbox, 10)
        gtk_widget_set_margin_top(vbox, 6)
        gtk_widget_set_margin_bottom(vbox, 6)
        gtk_window_set_child(asWindow(win), vbox)

        valueLabel = gtk_label_new("---")
        gtk_label_set_markup(asLabel(valueLabel),
            "<span font='24' weight='bold' color='#888888'>---</span>")
        gtkBoxAppend(vbox, valueLabel)

        deltaLabel = gtk_label_new("")
        gtkBoxAppend(vbox, deltaLabel)
        gtk_widget_set_visible(deltaLabel, 0)

        // Click anywhere to dismiss — use GtkGestureClick event controller
        let clickCtrl = gtk_gesture_click_new()
        gtk_widget_add_controller(win, clickCtrl)

        gtkConnectDeleteHide(win) { [weak self] in
            self?.isVisible = false
            if let w = self?.window { gtk_widget_set_visible(w, 0) }
        }
    }
}
#endif
