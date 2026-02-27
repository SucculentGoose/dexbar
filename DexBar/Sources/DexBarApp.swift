import SwiftUI
import AppKit

@main
struct DexBarApp: App {
    @State private var monitor = GlucoseMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(monitor)
        } label: {
            MenuBarLabel()
                .environment(monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(monitor)
        }
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
                Text(reading.menuBarLabel(unit: monitor.unit) + delta)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
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
