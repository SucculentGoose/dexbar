import SwiftUI
import AppKit
import Sparkle

@main
struct DexBarApp: App {
    @State private var monitor = GlucoseMonitor()
    private let sparkle = SparkleController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(monitor)
                .environmentObject(sparkle)
        } label: {
            MenuBarLabel()
                .environment(monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(monitor)
                .environmentObject(sparkle)
        }
    }
}

/// Holds the Sparkle updater controller for the lifetime of the app.
final class SparkleController: ObservableObject {
    let controller: SPUStandardUpdaterController
    var updater: SPUUpdater { controller.updater }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}

struct MenuBarLabel: View {
    @Environment(GlucoseMonitor.self) private var monitor

    var body: some View {
        if let reading = monitor.currentReading {
            HStack(spacing: 4) {
                if monitor.coloredMenuBar {
                    Image(nsImage: colorDot(nsColor: NSColor(monitor.readingColor), diameter: 7))
                }
                let delta = (monitor.showDelta ? monitor.formattedDelta(unit: monitor.unit) : nil).map { " \($0)" } ?? ""
                let stale = monitor.isStale ? " ⚠" : ""
                Text(reading.menuBarLabel(unit: monitor.unit) + delta + stale)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(monitor.isStale ? .secondary : .primary)
            }
        } else if monitor.state == .loading {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "waveform.path.ecg")
        }
    }

    private func colorDot(nsColor: NSColor, diameter: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            nsColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
