import Foundation

/// Manages the ~/.config/autostart/dexbar.desktop file for launch-at-login.
enum AutoStart {
    private static let desktopFileName = "dexbar.desktop"

    private static var desktopFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/autostart/\(desktopFileName)")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: desktopFileURL.path)
    }

    static func enable() {
        let dir = desktopFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let execPath = CommandLine.arguments[0]
        let content = """
            [Desktop Entry]
            Type=Application
            Name=DexBar
            Comment=Dexcom glucose readings in your system tray
            Exec=\(execPath)
            Icon=dialog-information
            Hidden=false
            X-GNOME-Autostart-enabled=true
            """
        try? content.write(to: desktopFileURL, atomically: true, encoding: .utf8)
    }

    static func disable() {
        try? FileManager.default.removeItem(at: desktopFileURL)
    }
}
