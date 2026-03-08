import SwiftUI

struct MenuBarView: View {
    @Environment(GlucoseMonitor.self) private var monitor
    @EnvironmentObject private var sparkle: SparkleController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current reading header
            currentReadingSection
            Divider()
            // Chart
            chartSection
            Divider()
            // Time in Range
            tirSection
            Divider()
            // Actions
            actionsSection
        }
        .frame(minWidth: 300)
        .padding(.vertical, 4)
    }

    // MARK: - Sections

    private var currentReadingSection: some View {
        VStack(spacing: 0) {
            if monitor.isStale {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("No new readings for 20+ min")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.12))
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mainValueText)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(readingColor)
                    Text(trendText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    statusBadge
                    if let updated = monitor.lastUpdated {
                        Text(updated, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let next = monitor.nextRefreshDate {
                        Text("Next: \(next, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var chartSection: some View {
        GlucoseChartView()
            .environment(monitor)
            .padding(.vertical, 8)
    }

    private var tirSection: some View {
        @Bindable var monitor = monitor
        let stats = monitor.tirStats
        return VStack(spacing: 6) {
            HStack {
                Text("Time in Range")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Stats range", selection: $monitor.selectedStatsRange) {
                    ForEach(StatsTimeRange.allCases, id: \.self) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 180)
            }
            if let gmi = monitor.gmi {
                let span = monitor.statsDataSpanDays
                let insufficient = span < 14
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        HStack(spacing: 4) {
                            Label(String(format: "GMI %.1f%%", gmi), systemImage: "waveform.path.ecg")
                            if insufficient {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .foregroundStyle(insufficient ? .secondary : .primary)
                        Spacer()
                        Text("\(stats.total) readings")
                            .foregroundStyle(.tertiary)
                    }
                    if insufficient {
                        Text(String(format: "Based on %.1fd of data — 14d+ recommended", span))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
            } else {
                HStack {
                    Spacer()
                    Text("\(stats.total) readings")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if stats.total > 0 {
                // Stacked bar
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        monitor.colorLow
                            .frame(width: geo.size.width * stats.lowPct / 100)
                        monitor.colorInRange
                            .frame(width: geo.size.width * stats.inRangePct / 100)
                        monitor.colorHigh
                            .frame(maxWidth: .infinity)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 8)

                // Labels
                HStack {
                    Label(String(format: "%.0f%%", stats.lowPct), systemImage: "arrow.down")
                        .foregroundStyle(monitor.colorLow)
                    Spacer()
                    Label(String(format: "%.0f%%", stats.inRangePct), systemImage: "checkmark")
                        .foregroundStyle(monitor.colorInRange)
                    Spacer()
                    Label(String(format: "%.0f%%", stats.highPct), systemImage: "arrow.up")
                        .foregroundStyle(monitor.colorHigh)
                }
                .font(.caption2)
            } else {
                Text("No readings in this period")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var actionsSection: some View {
        VStack(spacing: 0) {
            Button(action: {
                Task { await monitor.refreshNow() }
            }) {
                Label("Refresh Now", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            Button {
                sparkle.updater.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .disabled(!sparkle.updater.canCheckForUpdates)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            Button {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Label("Settings…", systemImage: "gear")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            Button(role: .destructive, action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit DexBar", systemImage: "power")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private var mainValueText: String {
        guard let reading = monitor.currentReading else {
            return monitor.state == .loading ? "…" : "--"
        }
        return "\(reading.displayValue(unit: monitor.unit)) \(reading.trend.arrow)"
    }

    private var trendText: String {
        guard let reading = monitor.currentReading else {
            return monitor.state.statusText
        }
        var parts = [reading.trend.description, monitor.unit.rawValue]
        if monitor.showDelta, let delta = monitor.formattedDelta(unit: monitor.unit) {
            parts.insert(delta, at: 1)
        }
        return parts.joined(separator: " · ")
    }

    private var readingColor: Color {
        monitor.readingColor
    }

    private var statusBadge: some View {
        Group {
            switch monitor.state {
            case .connected:
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
            case .loading:
                Label("Updating", systemImage: "arrow.clockwise")
                    .foregroundStyle(.blue)
            case .error:
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .idle:
                Label("Disconnected", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .labelStyle(.titleAndIcon)
    }
}
