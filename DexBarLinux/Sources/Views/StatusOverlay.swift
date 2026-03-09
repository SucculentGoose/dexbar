#if canImport(CGtk3)
import CGtk3
import DexBarCore
import Foundation

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
            gtk_widget_hide(win)
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
            gtk_widget_hide(deltaLabel)
        } else {
            let deltaMarkup = "<span font='11' color='#aaaaaa'>\(deltaText)</span>"
            gtk_label_set_markup(asLabel(deltaLabel), deltaMarkup)
            gtk_widget_show(deltaLabel)
        }
    }

    // MARK: - Private

    private func show() {
        guard let win = window else { return }
        update()
        gtk_widget_show_all(win)
        positionWindow()
        isVisible = true
    }

    private func positionWindow() {
        guard let win = window else { return }
        // Position at top-right corner of primary screen with a small margin
        let screen = gdk_screen_get_default()
        let screenWidth  = gdk_screen_get_width(screen)
        let screenHeight = gdk_screen_get_height(screen)
        _ = screenHeight  // suppress unused warning

        var w: gint = 0, h: gint = 0
        gtk_window_get_size(asWindow(win), &w, &h)

        let margin: gint = 8
        let x = screenWidth - w - margin
        let y = margin + 30  // leave room for panel at top
        gtk_window_move(asWindow(win), x, y)
    }

    private func buildWindow() {
        window = gtk_window_new(GTK_WINDOW_TOPLEVEL)
        guard let win = window else { return }

        gtk_window_set_decorated(asWindow(win), 0)
        gtk_window_set_keep_above(asWindow(win), 1)
        gtk_window_set_skip_taskbar_hint(asWindow(win), 1)
        gtk_window_set_skip_pager_hint(asWindow(win), 1)
        gtk_window_set_resizable(asWindow(win), 0)
        gtk_window_set_title(asWindow(win), "DexBar Overlay")

        // Transparent-ish dark background via opacity
        gtk_widget_set_opacity(win, 0.85)

        let vbox = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 2)
        gtk_widget_set_margin_start(vbox, 10)
        gtk_widget_set_margin_end(vbox, 10)
        gtk_widget_set_margin_top(vbox, 6)
        gtk_widget_set_margin_bottom(vbox, 6)
        containerAdd(win, vbox)

        valueLabel = gtk_label_new("---")
        gtk_label_set_markup(asLabel(valueLabel),
            "<span font='24' weight='bold' color='#888888'>---</span>")
        packStart(vbox, valueLabel)

        deltaLabel = gtk_label_new("")
        packStart(vbox, deltaLabel)
        gtk_widget_hide(deltaLabel)

        // Click anywhere to toggle popup
        gtk_widget_add_events(win, gint(GDK_BUTTON_PRESS_MASK.rawValue))
        gtkConnectDeleteHide(win) { [weak self] in
            self?.isVisible = false
            if let w = self?.window { gtk_widget_hide(w) }
        }
    }
}
#endif
