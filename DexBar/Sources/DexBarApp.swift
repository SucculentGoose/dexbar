import SwiftUI
import AppKit

@main
struct DexBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor = GlucoseMonitor()
    @AppStorage("dexcomUsername") private var username = ""
    @AppStorage("dexcomRegion") private var regionRaw = DexcomRegion.us.rawValue

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(monitor)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(monitor)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if let reading = monitor.currentReading {
            Text(reading.menuBarLabel(unit: monitor.unit))
                .font(.system(size: 12, weight: .medium, design: .rounded))
        } else if monitor.state == .loading {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "waveform.path.ecg")
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let username = UserDefaults.standard.string(forKey: "dexcomUsername") ?? ""
        let regionRaw = UserDefaults.standard.string(forKey: "dexcomRegion") ?? DexcomRegion.us.rawValue
        guard !username.isEmpty,
              let password = try? KeychainService.load(key: "password"),
              !password.isEmpty else { return }
        let region = DexcomRegion(rawValue: regionRaw) ?? .us
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .autoConnect,
                object: nil,
                userInfo: ["username": username, "password": password, "region": region]
            )
        }
    }
}

extension Notification.Name {
    static let autoConnect = Notification.Name("DexBarAutoConnect")
}
