#if canImport(CGtk3)
import CGtk3
import DexBarCore
import Foundation

/// A popup window showing the current glucose status.
@MainActor
final class PopupWindow {
    private var window: GWidget?
    private weak var monitor: GlucoseMonitorLinux?

    private var valueLabel: GWidget?
    private var trendLabel: GWidget?
    private var deltaLabel: GWidget?
    private var timestampLabel: GWidget?
    private var statusLabel: GWidget?
    private var tirLowLabel: GWidget?
    private var tirInRangeLabel: GWidget?
    private var tirHighLabel: GWidget?

    init(monitor: GlucoseMonitorLinux) {
        self.monitor = monitor
        buildWindow()
    }

    // MARK: - Public

    func toggle() {
        guard let win = window else { return }
        if gtk_widget_is_visible(win) != 0 {
            gtk_widget_hide(win)
        } else {
            update()
            gtk_widget_show_all(win)
            gtk_window_present(asWindow(win))
        }
    }

    func update() {
        guard let monitor else { return }

        if let reading = monitor.currentReading {
            let val = reading.displayValue(unit: monitor.unit)
            let unitStr = monitor.unit.rawValue
            let prefix = monitor.isStale ? "⚠ " : ""
            gtk_label_set_text(asLabel(valueLabel), "\(prefix)\(val) \(unitStr)")
            gtk_label_set_text(asLabel(trendLabel), reading.trend.arrow)
            gtk_label_set_text(asLabel(deltaLabel), monitor.formattedDelta(unit: monitor.unit) ?? "—")
            let age = Int(Date().timeIntervalSince(reading.date) / 60)
            gtk_label_set_text(asLabel(timestampLabel), "\(age) min ago")
        } else {
            gtk_label_set_text(asLabel(valueLabel), "---")
            gtk_label_set_text(asLabel(trendLabel), "")
            gtk_label_set_text(asLabel(deltaLabel), "")
            gtk_label_set_text(asLabel(timestampLabel), "")
        }

        gtk_label_set_text(asLabel(statusLabel), monitor.state.statusText)

        let tir = monitor.tirStats
        if tir.total > 0 {
            gtk_label_set_text(asLabel(tirLowLabel),     String(format: "Low:      %.0f%%", tir.lowPct))
            gtk_label_set_text(asLabel(tirInRangeLabel), String(format: "In Range: %.0f%%", tir.inRangePct))
            gtk_label_set_text(asLabel(tirHighLabel),    String(format: "High:     %.0f%%", tir.highPct))
        } else {
            gtk_label_set_text(asLabel(tirLowLabel),     "Low:      —")
            gtk_label_set_text(asLabel(tirInRangeLabel), "In Range: —")
            gtk_label_set_text(asLabel(tirHighLabel),    "High:     —")
        }
    }

    // MARK: - Private

    private func buildWindow() {
        window = gtk_window_new(GTK_WINDOW_TOPLEVEL)
        gtk_window_set_title(asWindow(window), "DexBar")
        gtkSetAppIcon(window)
        gtk_window_set_default_size(asWindow(window), 220, 240)
        gtk_window_set_resizable(asWindow(window), 0)
        gtkConnectDeleteHide(window) { [weak self] in
            if let win = self?.window { gtk_widget_hide(win) }
        }

        let vbox = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 8)
        gtk_widget_set_margin_start(vbox, 12)
        gtk_widget_set_margin_end(vbox, 12)
        gtk_widget_set_margin_top(vbox, 12)
        gtk_widget_set_margin_bottom(vbox, 12)
        containerAdd(window, vbox)

        // Reading row
        let readingBox = gtkBox(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        valueLabel = gtkLabel("---")
        trendLabel = gtkLabel("")
        deltaLabel = gtkLabel("")
        packStart(readingBox, valueLabel)
        packStart(readingBox, trendLabel)
        packStart(readingBox, deltaLabel)
        packStart(vbox, readingBox)

        // Timestamp
        timestampLabel = gtkLabel("")
        gtk_label_set_xalign(asLabel(timestampLabel), 0)
        packStart(vbox, timestampLabel)

        packStart(vbox, gtkSeparator())

        // TiR
        let tirTitle = gtkLabel("Time in Range")
        gtk_label_set_xalign(asLabel(tirTitle), 0)
        packStart(vbox, tirTitle)

        tirLowLabel     = gtkLabel("Low:      —")
        tirInRangeLabel = gtkLabel("In Range: —")
        tirHighLabel    = gtkLabel("High:     —")
        for lbl in [tirLowLabel, tirInRangeLabel, tirHighLabel] {
            gtk_label_set_xalign(asLabel(lbl), 0)
            packStart(vbox, lbl)
        }

        packStart(vbox, gtkSeparator())

        statusLabel = gtkLabel("Not connected")
        gtk_label_set_xalign(asLabel(statusLabel), 0)
        packStart(vbox, statusLabel)
    }
}
#endif
