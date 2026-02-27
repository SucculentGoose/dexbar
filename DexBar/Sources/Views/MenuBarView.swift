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
            // Actions
            actionsSection
        }
        .frame(minWidth: 300)
        .padding(.vertical, 4)
    }

    // MARK: - Sections

    private var currentReadingSection: some View {
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

    private var chartSection: some View {
        GlucoseChartView()
            .environment(monitor)
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
