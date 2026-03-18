#if canImport(CGtk4)
import CGtk4
import DexBarCore
import Foundation

/// A popup window matching the macOS DexBar dropdown: glucose reading, chart,
/// time-in-range bar, stats, and action buttons. Rendered with GTK4 + Cairo.
@MainActor
final class PopupWindow {
    private var window: GWidget?
    private weak var monitor: GlucoseMonitorLinux?

    // Header labels
    private var staleBar: GWidget?
    private var valueLabel: GWidget?
    private var trendLabel: GWidget?
    private var statusBadge: GWidget?
    private var updatedLabel: GWidget?
    private var nextLabel: GWidget?

    // Chart
    private var chartArea: GWidget?
    private var chartRangeButtons: [TimeRange: GWidget] = [:]

    // TiR
    private var tirHeaderLabel: GWidget?
    private var tirBar: GWidget?
    private var tirLowLabel: GWidget?
    private var tirInRangeLabel: GWidget?
    private var tirHighLabel: GWidget?
    private var statsRangeButtons: [StatsTimeRange: GWidget] = [:]
    private var gmiLabel: GWidget?
    private var spanWarningLabel: GWidget?

    // Chart hover state
    private var hoveredReading: GlucoseReading?
    private var hoverX: Double = 0
    private var hoverY: Double = 0

    // Action callbacks
    var onOpenSettings: (() -> Void)?
    var onCheckUpdates: (() -> Void)?

    private static var cssApplied = false
    private var tickTimerId: guint = 0

    init(monitor: GlucoseMonitorLinux) {
        self.monitor = monitor
        if !Self.cssApplied {
            applyPopupCSS()
            Self.cssApplied = true
        }
        buildWindow()
    }

    // MARK: - Public

    func toggle() {
        guard let win = window else { return }
        if gtk_widget_is_visible(win) != 0 {
            gtk_widget_set_visible(win, 0)
            stopTick()
        } else {
            update()
            gtk_widget_set_visible(win, 1)
            // Hide conditional elements after making visible
            updateStaleBar()
            updateSpanWarning()
            gtk_window_present(asWindow(win))
            startTick()
        }
    }

    func update() {
        guard let _ = monitor else { return }
        // Allow update even when hidden so data is ready when toggled open
        updateHeader()
        updateChart()
        updateTiR()
    }

    // MARK: - Tick timer (updates countdown every second while visible)

    private func startTick() {
        guard tickTimerId == 0 else { return }
        let cb: @convention(c) (gpointer?) -> gboolean = { userData in
            guard let ptr = userData else { return 0 }
            let popup = Unmanaged<PopupWindow>.fromOpaque(ptr).takeUnretainedValue()
            popup.updateHeader()
            return 1 // continue
        }
        let raw = Unmanaged.passUnretained(self).toOpaque()
        tickTimerId = g_timeout_add(1000, cb, raw)
    }

    private func stopTick() {
        if tickTimerId != 0 {
            g_source_remove(tickTimerId)
            tickTimerId = 0
        }
    }

    // MARK: - Build Window

    private func buildWindow() {
        window = gtk_window_new()
        guard let win = window else { return }
        gtk_window_set_title(asWindow(win), "DexBar")
        gtkSetAppIcon(win)
        gtk_window_set_default_size(asWindow(win), 310, -1)
        gtk_window_set_resizable(asWindow(win), 0)
        gtkAddClass(win, "dexbar-popup")

        gtkConnectDeleteHide(win) { [weak self] in
            if let w = self?.window { gtk_widget_set_visible(w, 0) }
        }

        let vbox = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)
        gtk_window_set_child(asWindow(win), vbox)

        buildStaleBar(into: vbox)
        buildCurrentReading(into: vbox)
        gtkBoxAppend(vbox, gtkSeparator())
        buildChartSection(into: vbox)
        gtkBoxAppend(vbox, gtkSeparator())
        buildTiRSection(into: vbox)
        gtkBoxAppend(vbox, gtkSeparator())
        buildActionsSection(into: vbox)
    }

    // MARK: - Stale Warning Bar

    private func buildStaleBar(into vbox: GWidget) {
        staleBar = gtkBox(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 6)
        gtkAddClass(staleBar, "stale-bar")
        let icon = gtkLabel("⚠")
        let text = gtkLabel("No new readings for 20+ min")
        gtkBoxAppend(staleBar, icon)
        gtkBoxAppend(staleBar, text)
        gtk_widget_set_margin_start(staleBar, 12)
        gtk_widget_set_margin_end(staleBar, 12)
        gtk_widget_set_margin_top(staleBar, 6)
        gtk_widget_set_margin_bottom(staleBar, 6)
        gtkBoxAppend(vbox, staleBar)
    }

    private func updateStaleBar() {
        guard let monitor, let bar = staleBar else { return }
        if monitor.isStale {
            gtk_widget_set_visible(bar, 1)
        } else {
            gtk_widget_set_visible(bar, 0)
        }
    }

    // MARK: - Current Reading Header

    private func buildCurrentReading(into vbox: GWidget) {
        let hbox = gtkBox(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        gtk_widget_set_margin_start(hbox, 16)
        gtk_widget_set_margin_end(hbox, 16)
        gtk_widget_set_margin_top(hbox, 10)
        gtk_widget_set_margin_bottom(hbox, 10)

        // Left side: value + trend
        let leftBox = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 2)
        valueLabel = gtkLabel("")
        gtk_label_set_xalign(asLabel(valueLabel), 0)
        trendLabel = gtkLabel("")
        gtk_label_set_xalign(asLabel(trendLabel), 0)
        gtkBoxAppend(leftBox, valueLabel)
        gtkBoxAppend(leftBox, trendLabel)
        gtkBoxAppend(hbox, leftBox, expand: true, fill: true)

        // Right side: status, updated, next
        let rightBox = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 2)
        statusBadge = gtkLabel("")
        gtk_label_set_xalign(asLabel(statusBadge), 1)
        updatedLabel = gtkLabel("")
        gtk_label_set_xalign(asLabel(updatedLabel), 1)
        nextLabel = gtkLabel("")
        gtk_label_set_xalign(asLabel(nextLabel), 1)
        gtkBoxAppend(rightBox, statusBadge)
        gtkBoxAppend(rightBox, updatedLabel)
        gtkBoxAppend(rightBox, nextLabel)
        gtkBoxAppend(hbox, rightBox)

        gtkBoxAppend(vbox, hbox)
    }

    private func updateHeader() {
        guard let monitor else { return }

        // Value
        let valueText: String
        let color: String
        if let reading = monitor.currentReading {
            let val = reading.displayValue(unit: monitor.unit)
            valueText = "\(val) \(reading.trend.arrow)"
            color = monitor.readingColor
        } else {
            valueText = monitor.state == .loading ? "…" : "--"
            color = "#888888"
        }
        let valueMarkup = "<span font='28' weight='bold' color='\(color)'>\(valueText)</span>"
        gtk_label_set_markup(asLabel(valueLabel), valueMarkup)

        // Trend description line
        if let reading = monitor.currentReading {
            var parts = [reading.trend.description]
            if let delta = monitor.formattedDelta(unit: monitor.unit) {
                parts.append(delta)
            }
            parts.append(monitor.unit.rawValue)
            let trendText = parts.joined(separator: " · ")
            let trendMarkup = "<span font='10' color='#aaaaaa'>\(trendText)</span>"
            gtk_label_set_markup(asLabel(trendLabel), trendMarkup)
        } else {
            let trendMarkup = "<span font='10' color='#aaaaaa'>\(monitor.state.statusText)</span>"
            gtk_label_set_markup(asLabel(trendLabel), trendMarkup)
        }

        // Status badge
        let badgeText: String
        let badgeColor: String
        let badgeIcon: String
        switch monitor.state {
        case .connected:
            badgeIcon = "⦿"; badgeText = "Live"; badgeColor = "#34C759"
        case .loading:
            badgeIcon = "↻"; badgeText = "Updating"; badgeColor = "#0A84FF"
        case .error:
            badgeIcon = "⚠"; badgeText = "Error"; badgeColor = "#FF3B30"
        case .idle:
            badgeIcon = "○"; badgeText = "Disconnected"; badgeColor = "#888888"
        }
        let badgeMarkup = "<span font='9' color='\(badgeColor)'>\(badgeIcon) \(badgeText)</span>"
        gtk_label_set_markup(asLabel(statusBadge), badgeMarkup)

        // Updated time
        if let updated = monitor.lastUpdated {
            let ago = Int(Date().timeIntervalSince(updated) / 60)
            let agoText = ago < 1 ? "just now" : "\(ago) min ago"
            let markup = "<span font='9' color='#666666'>\(agoText)</span>"
            gtk_label_set_markup(asLabel(updatedLabel), markup)
        } else {
            gtk_label_set_text(asLabel(updatedLabel), "")
        }

        // Next refresh
        if let next = monitor.nextRefreshDate {
            let secs = max(0, Int(next.timeIntervalSinceNow))
            let m = secs / 60
            let s = secs % 60
            let nextText = m > 0 ? "Next: \(m) min, \(s) sec" : "Next: \(s) sec"
            let markup = "<span font='9' color='#666666'>\(nextText)</span>"
            gtk_label_set_markup(asLabel(nextLabel), markup)
        } else {
            gtk_label_set_text(asLabel(nextLabel), "")
        }

        updateStaleBar()
    }

    // MARK: - Chart Section

    private func buildChartSection(into vbox: GWidget) {
        let section = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
        gtk_widget_set_margin_start(section, 12)
        gtk_widget_set_margin_end(section, 12)
        gtk_widget_set_margin_top(section, 8)
        gtk_widget_set_margin_bottom(section, 8)

        // Range selector
        let rangeBox = gtkBox(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        let ranges: [TimeRange] = [.threeHours, .sixHours, .twelveHours, .day]
        for range in ranges {
            let btn = gtk_toggle_button_new_with_label(range.rawValue)!
            gtkAddClass(btn, "range-btn")
            gtk_widget_set_size_request(btn, 50, 28)
            chartRangeButtons[range] = btn
            gtkBoxAppend(rangeBox, btn, expand: true, fill: true)

            gtkConnect(btn, signal: "toggled") { [weak self] in
                guard let self, let monitor = self.monitor else { return }
                let isActive = gtk_toggle_button_get_active(asToggle(btn)) != 0
                if isActive {
                    monitor.selectedTimeRange = range
                    self.syncChartRangeButtons()
                    self.updateChart()
                }
            }
        }
        gtkBoxAppend(section, rangeBox)

        // Chart drawing area
        chartArea = gtk_drawing_area_new()
        gtk_widget_set_size_request(chartArea, 280, 140)
        gtkSetDrawFunc(chartArea) { [weak self] cr in
            self?.drawChart(cr: cr)
        }

        // Hover tracking for tooltip
        let motionCtrl = gtkConnectMotion(chartArea) { [weak self] x, y in
            self?.handleChartHover(x: x, y: y)
        }
        gtkConnectLeave(motionCtrl) { [weak self] in
            self?.hoveredReading = nil
            if let area = self?.chartArea {
                gtk_widget_queue_draw(area)
            }
        }

        gtkBoxAppend(section, chartArea)

        gtkBoxAppend(vbox, section)

        syncChartRangeButtons()
    }

    private func syncChartRangeButtons() {
        guard let monitor else { return }
        for (range, btn) in chartRangeButtons {
            let active = range == monitor.selectedTimeRange
            gtk_toggle_button_set_active(asToggle(btn), active ? 1 : 0)
            if active {
                gtkAddClass(btn, "active-range")
            } else {
                gtkRemoveClass(btn, "active-range")
            }
        }
    }

    private func updateChart() {
        guard let area = chartArea else { return }
        gtk_widget_queue_draw(area)
    }

    // MARK: - Chart Drawing (Cairo)

    private func drawChart(cr: OpaquePointer) {
        guard let monitor else { return }
        let readings = monitor.chartReadings.sorted { $0.date < $1.date }
        let w = Double(gtk_widget_get_width(chartArea))
        let h = Double(gtk_widget_get_height(chartArea))

        let margin = (top: 10.0, right: 40.0, bottom: 20.0, left: 8.0)
        let plotW = w - margin.left - margin.right
        let plotH = h - margin.top - margin.bottom

        // Y-axis domain
        let unit = monitor.unit
        let lowThresh = unit == .mgdL ? monitor.alertLowThresholdMgdL : monitor.alertLowThresholdMgdL / 18.0
        let highThresh = unit == .mgdL ? monitor.alertHighThresholdMgdL : monitor.alertHighThresholdMgdL / 18.0
        let padding = unit == .mgdL ? 15.0 : 0.8

        let values = readings.map { unit == .mgdL ? Double($0.value) : $0.mmolL }
        let minY = min(values.min() ?? lowThresh, lowThresh) - padding
        let maxY = max(values.max() ?? highThresh, highThresh) + padding
        let rangeY = maxY - minY

        guard plotW > 0, plotH > 0, rangeY > 0, !readings.isEmpty else {
            // "No readings" text
            cairo_set_source_rgba(cr, 0.5, 0.5, 0.5, 0.7)
            cairo_select_font_face(cr, "sans-serif", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
            cairo_set_font_size(cr, 11)
            cairo_move_to(cr, w / 2 - 50, h / 2)
            cairo_show_text(cr, "No readings for this period")
            return
        }

        // Time domain
        let now = Date()
        let timeStart = now.addingTimeInterval(-monitor.selectedTimeRange.interval)
        let timeRange = now.timeIntervalSince(timeStart)

        func xFor(_ date: Date) -> Double {
            let t = date.timeIntervalSince(timeStart) / timeRange
            return margin.left + t * plotW
        }
        func yFor(_ value: Double) -> Double {
            let t = (value - minY) / rangeY
            return margin.top + plotH - t * plotH
        }

        // --- In-range band ---
        let irColor = hexToRGB(monitor.colorInRange)
        cairo_set_source_rgba(cr, irColor.r, irColor.g, irColor.b, 0.08)
        cairo_rectangle(cr, margin.left, yFor(highThresh), plotW, yFor(lowThresh) - yFor(highThresh))
        cairo_fill(cr)

        // --- Threshold lines (dashed) ---
        let dashPattern: [Double] = [4, 3]
        if monitor.alertHighEnabled {
            cairo_set_source_rgba(cr, 1.0, 0.2, 0.2, 0.35)
            cairo_set_line_width(cr, 1)
            cairo_set_dash(cr, dashPattern, Int32(dashPattern.count), 0)
            cairo_move_to(cr, margin.left, yFor(highThresh))
            cairo_line_to(cr, margin.left + plotW, yFor(highThresh))
            cairo_stroke(cr)
        }
        if monitor.alertLowEnabled {
            cairo_set_source_rgba(cr, 1.0, 0.55, 0.0, 0.5)
            cairo_set_line_width(cr, 1)
            cairo_set_dash(cr, dashPattern, Int32(dashPattern.count), 0)
            cairo_move_to(cr, margin.left, yFor(lowThresh))
            cairo_line_to(cr, margin.left + plotW, yFor(lowThresh))
            cairo_stroke(cr)
        }
        // Reset dash
        cairo_set_dash(cr, nil, 0, 0)

        // --- Glucose line ---
        cairo_set_source_rgba(cr, 0.04, 0.52, 1.0, 0.8)
        cairo_set_line_width(cr, 2)
        for (i, reading) in readings.enumerated() {
            let val = unit == .mgdL ? Double(reading.value) : reading.mmolL
            let x = xFor(reading.date)
            let y = yFor(val)
            if i == 0 {
                cairo_move_to(cr, x, y)
            } else {
                cairo_line_to(cr, x, y)
            }
        }
        cairo_stroke(cr)

        // --- Data points ---
        for reading in readings {
            let val = unit == .mgdL ? Double(reading.value) : reading.mmolL
            let x = xFor(reading.date)
            let y = yFor(val)
            let c = hexToRGB(monitor.colorForReading(reading))
            cairo_set_source_rgba(cr, c.r, c.g, c.b, 1.0)
            cairo_arc(cr, x, y, 2.5, 0, 2.0 * Double.pi)
            cairo_fill(cr)
        }

        // --- Y-axis labels ---
        cairo_select_font_face(cr, "sans-serif", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
        cairo_set_font_size(cr, 9)
        cairo_set_source_rgba(cr, 0.5, 0.5, 0.5, 0.8)
        let ySteps = 4
        for i in 0...ySteps {
            let val = minY + Double(i) * rangeY / Double(ySteps)
            let y = yFor(val)
            let text = unit == .mgdL ? "\(Int(val))" : String(format: "%.1f", val)
            cairo_move_to(cr, margin.left + plotW + 4, y + 3)
            cairo_show_text(cr, text)
        }

        // --- X-axis labels ---
        let stride = xAxisStride(for: monitor.selectedTimeRange)
        let calendar = Calendar.current
        // Find first whole-hour after timeStart
        var comp = calendar.dateComponents([.year, .month, .day, .hour], from: timeStart)
        comp.hour = (comp.hour ?? 0) + 1
        comp.minute = 0
        comp.second = 0
        var labelDate = calendar.date(from: comp) ?? timeStart

        let formatter = DateFormatter()
        formatter.dateFormat = "ha"

        while labelDate < now {
            let hour = calendar.component(.hour, from: labelDate)
            if hour % stride == 0 {
                let x = xFor(labelDate)
                if x >= margin.left && x <= margin.left + plotW {
                    let text = formatter.string(from: labelDate).lowercased()
                    cairo_move_to(cr, x - 8, h - 3)
                    cairo_show_text(cr, text)
                }
            }
            labelDate = labelDate.addingTimeInterval(3600)
        }

        // --- Hover tooltip ---
        if let hovered = hoveredReading {
            let val = unit == .mgdL ? Double(hovered.value) : hovered.mmolL
            let px = xFor(hovered.date)
            let py = yFor(val)

            // Large highlighted circle
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.9)
            cairo_arc(cr, px, py, 5.0, 0, 2.0 * Double.pi)
            cairo_fill(cr)

            // Colored ring
            let hc = hexToRGB(monitor.colorForReading(hovered))
            cairo_set_source_rgba(cr, hc.r, hc.g, hc.b, 1.0)
            cairo_arc(cr, px, py, 5.0, 0, 2.0 * Double.pi)
            cairo_set_line_width(cr, 1.5)
            cairo_stroke(cr)

            // Build tooltip text
            let valText = "\(hovered.displayValue(unit: unit)) \(hovered.trend.arrow)"
            let deltaText = deltaFromPrevious(for: hovered) ?? ""
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            let timeText = timeFormatter.string(from: hovered.date)

            // Use Pango for Unicode arrow support
            let pangoLayout = pango_cairo_create_layout(cr)
            defer { g_object_unref(gpointer(pangoLayout)) }

            // Measure line 1: value + delta
            let line1: String
            if deltaText.isEmpty {
                line1 = "<b>\(valText)</b>"
            } else {
                line1 = "<b>\(valText)</b>  <span color='#aaaaaa'>\(deltaText)</span>"
            }
            let fullMarkup = "<span font='9'>\(line1)\n<span color='#999999'>\(timeText)</span></span>"
            pango_layout_set_markup(pangoLayout, fullMarkup, -1)

            var textW: Int32 = 0, textH: Int32 = 0
            pango_layout_get_pixel_size(pangoLayout, &textW, &textH)

            let tooltipPad = 8.0
            let tooltipW = Double(textW) + tooltipPad * 2
            let tooltipH = Double(textH) + tooltipPad * 2
            let tooltipGap = 6.0

            // Position tooltip above point, clamped to chart bounds
            var tx = px - tooltipW / 2
            var ty = py - tooltipH - tooltipGap
            tx = max(margin.left, min(tx, margin.left + plotW - tooltipW))
            if ty < margin.top {
                ty = py + tooltipGap
            }

            // Tooltip background (rounded rect)
            let cr2r = 4.0
            cairo_new_sub_path(cr)
            cairo_arc(cr, tx + tooltipW - cr2r, ty + cr2r, cr2r, -Double.pi / 2, 0)
            cairo_arc(cr, tx + tooltipW - cr2r, ty + tooltipH - cr2r, cr2r, 0, Double.pi / 2)
            cairo_arc(cr, tx + cr2r, ty + tooltipH - cr2r, cr2r, Double.pi / 2, Double.pi)
            cairo_arc(cr, tx + cr2r, ty + cr2r, cr2r, Double.pi, 3 * Double.pi / 2)
            cairo_close_path(cr)
            cairo_set_source_rgba(cr, 0.22, 0.22, 0.22, 0.95)
            cairo_fill(cr)

            // Render text with Pango
            cairo_move_to(cr, tx + tooltipPad, ty + tooltipPad)
            cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 1.0)
            pango_cairo_show_layout(cr, pangoLayout)
        }
    }

    private func xAxisStride(for range: TimeRange) -> Int {
        switch range {
        case .threeHours:  return 1
        case .sixHours:    return 2
        case .twelveHours: return 3
        case .day:         return 6
        }
    }

    // MARK: - Chart Hover

    private func handleChartHover(x: Double, y: Double) {
        guard let monitor else { return }
        let readings = monitor.chartReadings.sorted { $0.date < $1.date }
        guard !readings.isEmpty else { return }

        let w = Double(gtk_widget_get_width(chartArea))
        let margin = (left: 8.0, right: 40.0)
        let plotW = w - margin.left - margin.right

        let now = Date()
        let timeStart = now.addingTimeInterval(-monitor.selectedTimeRange.interval)
        let timeRange = now.timeIntervalSince(timeStart)

        // Convert x pixel to time, find nearest reading
        let t = (x - margin.left) / plotW
        let hoverDate = timeStart.addingTimeInterval(t * timeRange)

        let nearest = readings.min { a, b in
            abs(a.date.timeIntervalSince(hoverDate)) < abs(b.date.timeIntervalSince(hoverDate))
        }

        if hoveredReading?.date != nearest?.date {
            hoveredReading = nearest
            hoverX = x
            hoverY = y
            if let area = chartArea {
                gtk_widget_queue_draw(area)
            }
        }
    }

    /// Calculates the delta between a reading and the one immediately before it.
    private func deltaFromPrevious(for reading: GlucoseReading) -> String? {
        guard let monitor else { return nil }
        let all = monitor.recentReadings // sorted newest-first
        guard let idx = all.firstIndex(where: { $0.date == reading.date }),
              idx + 1 < all.count else { return nil }
        let diff = reading.value - all[idx + 1].value
        switch monitor.unit {
        case .mgdL:
            return diff >= 0 ? "+\(diff)" : "\(diff)"
        case .mmolL:
            let d = Double(diff) / 18.0
            return d >= 0 ? String(format: "+%.1f", d) : String(format: "%.1f", d)
        }
    }

    // MARK: - Time in Range Section

    private func buildTiRSection(into vbox: GWidget) {
        let section = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 6)
        gtk_widget_set_margin_start(section, 16)
        gtk_widget_set_margin_end(section, 16)
        gtk_widget_set_margin_top(section, 8)
        gtk_widget_set_margin_bottom(section, 8)

        // Header: "Time in Range: 75%"
        tirHeaderLabel = gtkLabel("")
        gtk_label_set_xalign(asLabel(tirHeaderLabel), 0)
        gtkBoxAppend(section, tirHeaderLabel)

        // Stats range selector
        let rangeBox = gtkBox(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 4)
        let ranges: [StatsTimeRange] = StatsTimeRange.allCases
        for range in ranges {
            let btn = gtk_toggle_button_new_with_label(range.rawValue)!
            gtkAddClass(btn, "range-btn")
            gtk_widget_set_size_request(btn, -1, 26)
            statsRangeButtons[range] = btn
            gtkBoxAppend(rangeBox, btn, expand: true, fill: true)

            gtkConnect(btn, signal: "toggled") { [weak self] in
                guard let self, let monitor = self.monitor else { return }
                let isActive = gtk_toggle_button_get_active(asToggle(btn)) != 0
                if isActive {
                    monitor.statsTimeRange = range
                    self.syncStatsRangeButtons()
                    self.updateTiR()
                }
            }
        }
        gtkBoxAppend(section, rangeBox)

        // TiR colored bar (drawn with Cairo)
        tirBar = gtk_drawing_area_new()
        gtk_widget_set_size_request(tirBar, -1, 10)
        gtkSetDrawFunc(tirBar) { [weak self] cr in
            self?.drawTiRBar(cr: cr)
        }
        gtkBoxAppend(section, tirBar)

        // Low / In Range / High labels
        let pctBox = gtkBox(orientation: GTK_ORIENTATION_HORIZONTAL, spacing: 0)
        tirLowLabel = gtkLabel("")
        tirInRangeLabel = gtkLabel("")
        tirHighLabel = gtkLabel("")
        gtk_label_set_xalign(asLabel(tirLowLabel), 0)
        gtk_label_set_xalign(asLabel(tirInRangeLabel), 0.5)
        gtk_label_set_xalign(asLabel(tirHighLabel), 1)
        gtkBoxAppend(pctBox, tirLowLabel, expand: true, fill: true)
        gtkBoxAppend(pctBox, tirInRangeLabel, expand: true, fill: true)
        gtkBoxAppend(pctBox, tirHighLabel, expand: true, fill: true)
        gtkBoxAppend(section, pctBox)

        // GMI + reading count
        gmiLabel = gtkLabel("")
        gtk_label_set_xalign(asLabel(gmiLabel), 0)
        gtkBoxAppend(section, gmiLabel)

        // Span warning (hidden unless <14d)
        spanWarningLabel = gtkLabel("")
        gtk_label_set_xalign(asLabel(spanWarningLabel), 0)
        gtkBoxAppend(section, spanWarningLabel)

        gtkBoxAppend(vbox, section)

        syncStatsRangeButtons()
    }

    private func syncStatsRangeButtons() {
        guard let monitor else { return }
        for (range, btn) in statsRangeButtons {
            let active = range == monitor.statsTimeRange
            gtk_toggle_button_set_active(asToggle(btn), active ? 1 : 0)
            if active {
                gtkAddClass(btn, "active-range")
            } else {
                gtkRemoveClass(btn, "active-range")
            }
        }
    }

    private func updateTiR() {
        guard let monitor else { return }
        let stats = monitor.tirStats

        // Header
        if stats.total > 0 {
            let irColor = monitor.colorInRange
            let markup = "<span font='10' weight='bold' color='#aaaaaa'>Time in Range: </span>" +
                         "<span font='10' weight='bold' color='\(irColor)'>\(String(format: "%.0f%%", stats.inRangePct))</span>"
            gtk_label_set_markup(asLabel(tirHeaderLabel), markup)
        } else {
            let markup = "<span font='10' weight='bold' color='#aaaaaa'>Time in Range:</span>"
            gtk_label_set_markup(asLabel(tirHeaderLabel), markup)
        }

        // Redraw the bar
        if let bar = tirBar {
            gtk_widget_queue_draw(bar)
        }

        if stats.total > 0 {
            // Percentage labels
            let lowColor = monitor.colorLow
            let irColor = monitor.colorInRange
            let highColor = monitor.colorHigh
            gtk_label_set_markup(asLabel(tirLowLabel),
                "<span font='9' color='\(lowColor)'>↓ \(String(format: "%.0f%%", stats.lowPct))</span>")
            gtk_label_set_markup(asLabel(tirInRangeLabel),
                "<span font='9' color='\(irColor)'>✓ \(String(format: "%.0f%%", stats.inRangePct))</span>")
            gtk_label_set_markup(asLabel(tirHighLabel),
                "<span font='9' color='\(highColor)'>↑ \(String(format: "%.0f%%", stats.highPct))</span>")
        } else {
            let markup = "<span font='9' color='#666666'>No readings in this period</span>"
            gtk_label_set_markup(asLabel(tirLowLabel), markup)
            gtk_label_set_text(asLabel(tirInRangeLabel), "")
            gtk_label_set_text(asLabel(tirHighLabel), "")
        }

        // GMI
        if let gmi = monitor.gmi, stats.total > 0 {
            let span = monitor.statsDataSpanDays
            let insufficient = span < 14
            let gmiColor = insufficient ? "#666666" : "#aaaaaa"
            let warn = insufficient ? " ⚠" : ""
            let gmiText = String(format: "GMI %.1f%%", gmi)
            let markup = "<span font='9' color='\(gmiColor)'>↳ \(gmiText)\(warn)</span>" +
                         "<span font='9' color='#666666'>  \(stats.total) readings</span>"
            gtk_label_set_markup(asLabel(gmiLabel), markup)

            if insufficient {
                let warnMarkup = "<span font='8' color='#666666'>Based on \(String(format: "%.1fd", span)) of data — 14d+ recommended</span>"
                gtk_label_set_markup(asLabel(spanWarningLabel), warnMarkup)
                gtk_widget_set_visible(spanWarningLabel, 1)
            } else {
                gtk_widget_set_visible(spanWarningLabel, 0)
            }
        } else {
            gtk_label_set_text(asLabel(gmiLabel), "")
            gtk_widget_set_visible(spanWarningLabel, 0)
        }
    }

    private func updateSpanWarning() {
        guard let monitor else { return }
        let stats = monitor.tirStats
        if let _ = monitor.gmi, stats.total > 0, monitor.statsDataSpanDays < 14 {
            gtk_widget_set_visible(spanWarningLabel, 1)
        } else {
            gtk_widget_set_visible(spanWarningLabel, 0)
        }
    }

    // MARK: - TiR Bar Drawing

    private func drawTiRBar(cr: OpaquePointer) {
        guard let monitor else { return }
        let stats = monitor.tirStats
        let w = Double(gtk_widget_get_width(tirBar))
        let h = Double(gtk_widget_get_height(tirBar))
        let radius = 4.0

        guard stats.total > 0 else {
            // Empty bar
            cairo_set_source_rgba(cr, 0.3, 0.3, 0.3, 0.5)
            drawRoundedRect(cr, x: 0, y: 0, w: w, h: h, r: radius)
            cairo_fill(cr)
            return
        }

        let lowW = w * stats.lowPct / 100.0
        let irW = w * stats.inRangePct / 100.0
        let highW = w - lowW - irW

        // Clip to rounded rect
        drawRoundedRect(cr, x: 0, y: 0, w: w, h: h, r: radius)
        cairo_clip(cr)

        // Low segment
        let lc = hexToRGB(monitor.colorLow)
        cairo_set_source_rgba(cr, lc.r, lc.g, lc.b, 1.0)
        cairo_rectangle(cr, 0, 0, lowW, h)
        cairo_fill(cr)

        // In-range segment
        let ic = hexToRGB(monitor.colorInRange)
        cairo_set_source_rgba(cr, ic.r, ic.g, ic.b, 1.0)
        cairo_rectangle(cr, lowW + 1, 0, irW - 1, h)
        cairo_fill(cr)

        // High segment
        let hc = hexToRGB(monitor.colorHigh)
        cairo_set_source_rgba(cr, hc.r, hc.g, hc.b, 1.0)
        cairo_rectangle(cr, lowW + irW + 1, 0, highW, h)
        cairo_fill(cr)

        cairo_reset_clip(cr)
    }

    private func drawRoundedRect(_ cr: OpaquePointer, x: Double, y: Double, w: Double, h: Double, r: Double) {
        let r = min(r, min(w, h) / 2)
        cairo_new_sub_path(cr)
        cairo_arc(cr, x + w - r, y + r, r, -Double.pi / 2, 0)
        cairo_arc(cr, x + w - r, y + h - r, r, 0, Double.pi / 2)
        cairo_arc(cr, x + r, y + h - r, r, Double.pi / 2, Double.pi)
        cairo_arc(cr, x + r, y + r, r, Double.pi, 3 * Double.pi / 2)
        cairo_close_path(cr)
    }

    // MARK: - Actions Section

    private func buildActionsSection(into vbox: GWidget) {
        let section = gtkBox(orientation: GTK_ORIENTATION_VERTICAL, spacing: 0)

        let refreshBtn = makeActionButton("↻  Refresh Now")
        gtkConnect(refreshBtn, signal: "clicked") { [weak self] in
            guard let monitor = self?.monitor else { return }
            Task { @MainActor in await monitor.refreshNow() }
        }
        gtkBoxAppend(section, refreshBtn, expand: true, fill: true)
        gtkBoxAppend(section, gtkSeparator())

        let updateBtn = makeActionButton("⬇  Check for Updates…")
        gtkConnect(updateBtn, signal: "clicked") { [weak self] in
            self?.onCheckUpdates?()
        }
        gtkBoxAppend(section, updateBtn, expand: true, fill: true)
        gtkBoxAppend(section, gtkSeparator())

        let settingsBtn = makeActionButton("⚙  Settings…")
        gtkConnect(settingsBtn, signal: "clicked") { [weak self] in
            self?.onOpenSettings?()
        }
        gtkBoxAppend(section, settingsBtn, expand: true, fill: true)
        gtkBoxAppend(section, gtkSeparator())

        let quitBtn = makeActionButton("⏻  Quit DexBar")
        gtkAddClass(quitBtn, "quit-btn")
        gtkConnect(quitBtn, signal: "clicked") {
            g_main_loop_quit(mainLoop)
        }
        gtkBoxAppend(section, quitBtn, expand: true, fill: true)

        gtkBoxAppend(vbox, section)
    }

    private func makeActionButton(_ label: String) -> GWidget {
        let btn = gtk_button_new_with_label(label)!
        gtkAddClass(btn, "action-btn")
        gtk_widget_set_size_request(btn, -1, 36)
        return btn
    }

    // MARK: - CSS

    private func applyPopupCSS() {
        let css = """
        .dexbar-popup {
            background-color: #2b2b2b;
        }
        .dexbar-popup label {
            color: #e0e0e0;
        }
        .dexbar-popup separator {
            background-color: #444444;
            min-height: 1px;
        }
        .stale-bar {
            background-color: rgba(255, 165, 0, 0.12);
        }
        .stale-bar label {
            color: #FFA500;
        }
        .range-btn {
            background: #3a3a3a;
            color: #cccccc;
            border: 1px solid #555555;
            border-radius: 4px;
            padding: 2px 6px;
            font-size: 11px;
            min-height: 0;
            min-width: 0;
        }
        .range-btn:hover {
            background: #4a4a4a;
        }
        .active-range {
            background: #0A84FF;
            color: #ffffff;
            border-color: #0A84FF;
        }
        .active-range:hover {
            background: #3399FF;
        }
        .action-btn {
            background: transparent;
            border: none;
            border-radius: 0;
            color: #e0e0e0;
            padding: 8px 16px;
            font-size: 13px;
        }
        .action-btn:hover {
            background: #3a3a3a;
        }
        .quit-btn {
            color: #FF453A;
        }
        """
        gtkApplyCSS(css)
    }
}
#endif
