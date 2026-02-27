import SwiftUI
import Charts

struct GlucoseChartView: View {
    @Environment(GlucoseMonitor.self) private var monitor
    @State private var hoveredReading: GlucoseReading?

    var body: some View {
        @Bindable var monitor = monitor
        VStack(alignment: .leading, spacing: 6) {
            Picker("Range", selection: $monitor.selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            let readings = monitor.chartReadings
            if readings.isEmpty {
                Text("No readings for this period")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 130)
                    .multilineTextAlignment(.center)
            } else {
                chart(readings: readings)
                    .frame(height: 130)
                    .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Chart

    private func chart(readings: [GlucoseReading]) -> some View {
        Chart {
            // Threshold reference lines
            if monitor.alertHighEnabled {
                RuleMark(y: .value("High", threshold(monitor.alertHighThresholdMgdL)))
                    .foregroundStyle(.red.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if monitor.alertLowEnabled {
                RuleMark(y: .value("Low", threshold(monitor.alertLowThresholdMgdL)))
                    .foregroundStyle(.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            // Glucose line
            ForEach(readings) { reading in
                LineMark(
                    x: .value("Time", reading.date),
                    y: .value("Glucose", displayValue(reading))
                )
                .foregroundStyle(Color.accentColor.opacity(0.8))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            // Data points
            ForEach(readings) { reading in
                PointMark(
                    x: .value("Time", reading.date),
                    y: .value("Glucose", displayValue(reading))
                )
                .symbolSize(18)
                .foregroundStyle(colorFor(reading))
            }

            // Hover callout
            if let hovered = hoveredReading {
                PointMark(
                    x: .value("Time", hovered.date),
                    y: .value("Glucose", displayValue(hovered))
                )
                .symbolSize(55)
                .foregroundStyle(.white.opacity(0.9))
                .annotation(position: .top, spacing: 4) {
                    hoverLabel(hovered)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: xAxisStride)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(monitor.unit == .mmolL ? String(format: "%.1f", v) : "\(Int(v))")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: yDomain(readings: readings))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotAreaFrame].origin
                            let adjustedX = location.x - origin.x
                            guard let date: Date = proxy.value(atX: adjustedX) else {
                                hoveredReading = nil
                                return
                            }
                            hoveredReading = readings.min {
                                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                            }
                        case .ended:
                            hoveredReading = nil
                        }
                    }
            }
        }
    }

    // MARK: - Helpers

    private func hoverLabel(_ reading: GlucoseReading) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Text("\(reading.displayValue(unit: monitor.unit)) \(reading.trend.arrow)")
                    .font(.caption2.bold())
                if let d = deltaFromPrevious(for: reading) {
                    Text(d)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(reading.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
    }

    /// Change between this reading and the one immediately before it (older).
    private func deltaFromPrevious(for reading: GlucoseReading) -> String? {
        let all = monitor.recentReadings  // sorted newest first
        guard let idx = all.firstIndex(where: { $0.id == reading.id }),
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

    private func displayValue(_ reading: GlucoseReading) -> Double {
        monitor.unit == .mgdL ? Double(reading.value) : reading.mmolL
    }

    private func threshold(_ mgdL: Double) -> Double {
        monitor.unit == .mgdL ? mgdL : mgdL / 18.0
    }

    private func colorFor(_ reading: GlucoseReading) -> Color {
        let v = Double(reading.value)
        if v < monitor.alertLowThresholdMgdL || v > monitor.alertHighThresholdMgdL { return .red }
        let warnLow = monitor.alertLowThresholdMgdL + 20
        let warnHigh = monitor.alertHighThresholdMgdL - 20
        if v < warnLow || v > warnHigh { return .yellow }
        return .green
    }

    private var xAxisStride: Int {
        switch monitor.selectedTimeRange {
        case .threeHours:  1
        case .sixHours:    2
        case .twelveHours: 3
        case .day:         6
        }
    }

    private func yDomain(readings: [GlucoseReading]) -> ClosedRange<Double> {
        let padding: Double = monitor.unit == .mgdL ? 15 : 0.8
        let lo = threshold(monitor.alertLowThresholdMgdL)
        let hi = threshold(monitor.alertHighThresholdMgdL)
        let values = readings.map { displayValue($0) }
        let minV = min(values.min() ?? lo, lo) - padding
        let maxV = max(values.max() ?? hi, hi) + padding
        return minV...maxV
    }
}
