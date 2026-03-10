import Foundation
import Glibc
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let feedURL = URL(string:
    "https://raw.githubusercontent.com/SucculentGoose/dexbar/main/appcast-linux.xml")!

/// Checks appcast-linux.xml for a newer version, then downloads and installs it in-place.
/// Calls back to the tray for status updates, then re-execs the new binary to restart.
@MainActor
final class LinuxUpdater {
    /// Called when a newer version is found. Provides the version string and a closure to trigger install.
    var onUpdateAvailable: ((_ version: String, _ install: @escaping () -> Void) -> Void)?

    /// Called during download/install to update the tray menu item label.
    var onStatusChange: ((_ text: String) -> Void)?

    func checkForUpdates() {
        Task { @MainActor in
            guard let (version, url) = await fetchLatest() else { return }
            if isNewer(version, than: AppVersion.current) {
                onUpdateAvailable?(version) { [weak self] in
                    Task { @MainActor in
                        await self?.downloadAndInstall(version: version, from: url)
                    }
                }
            }
        }
    }

    // MARK: - Private: version check

    private func fetchLatest() async -> (String, URL)? {
        guard let (data, _) = try? await URLSession.shared.data(from: feedURL),
              let xml = String(data: data, encoding: .utf8) else { return nil }
        return parseLatest(from: xml)
    }

    private func parseLatest(from xml: String) -> (String, URL)? {
        let versionPattern = #"<sparkle:version>([^<]+)</sparkle:version>"#
        let urlPattern     = #"url="(https://[^"]+\.tar\.gz)""#
        guard let versionRegex = try? NSRegularExpression(pattern: versionPattern),
              let urlRegex     = try? NSRegularExpression(pattern: urlPattern) else { return nil }
        let range    = NSRange(xml.startIndex..., in: xml)
        let versions = versionRegex.matches(in: xml, range: range)
        let urls     = urlRegex.matches(in: xml, range: range)
        guard let lastVersion = versions.last, let lastURL = urls.last,
              let vRange = Range(lastVersion.range(at: 1), in: xml),
              let uRange = Range(lastURL.range(at: 1), in: xml) else { return nil }
        let version = String(xml[vRange])
        guard let url = URL(string: String(xml[uRange])) else { return nil }
        return (version, url)
    }

    // MARK: - Private: download + install + restart

    private func downloadAndInstall(version: String, from url: URL) async {
        onStatusChange?("Downloading v\(version)…")

        // Download tar.gz into memory (binary is ~1 MB)
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            onStatusChange?("⚠ Download failed")
            return
        }

        onStatusChange?("Installing v\(version)…")

        // Write tar.gz to a temp file
        let tmpDir   = FileManager.default.temporaryDirectory
            .appendingPathComponent("dexbar-update-\(version)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tarFile  = tmpDir.appendingPathComponent("dexbar.tar.gz")
        do {
            try data.write(to: tarFile)
        } catch {
            onStatusChange?("⚠ Write failed")
            return
        }

        // Extract with /usr/bin/tar
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments     = ["-xzf", tarFile.path, "-C", tmpDir.path]
        do { try tar.run(); tar.waitUntilExit() } catch {
            onStatusChange?("⚠ Extract failed")
            return
        }
        guard tar.terminationStatus == 0 else {
            onStatusChange?("⚠ Extract failed (\(tar.terminationStatus))")
            return
        }

        let newBinary = tmpDir.appendingPathComponent("dexbar")
        guard FileManager.default.fileExists(atPath: newBinary.path) else {
            onStatusChange?("⚠ Binary not found in archive")
            return
        }

        // chmod +x
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                ofItemAtPath: newBinary.path)

        // Atomically replace: stage next to current, then rename
        let currentPath = Self.currentBinaryPath()
        let stagePath   = currentPath + ".new"
        let mv = Process()
        mv.executableURL = URL(fileURLWithPath: "/bin/mv")
        mv.arguments     = ["-f", newBinary.path, stagePath]
        do { try mv.run(); mv.waitUntilExit() } catch {
            onStatusChange?("⚠ Install failed")
            return
        }
        // rename() is atomic on the same filesystem
        guard rename(stagePath, currentPath) == 0 else {
            onStatusChange?("⚠ Install failed (rename errno \(errno))")
            return
        }

        onStatusChange?("Restarting…")

        // Flush any pending notifications, then re-exec the new binary
        try? await Task.sleep(nanoseconds: 500_000_000)
        Self.restartApp(path: currentPath)
    }

    // MARK: - Helpers

    private static func currentBinaryPath() -> String {
        // /proc/self/exe resolves to the real path of the running binary on Linux
        var buf = [CChar](repeating: 0, count: 4096)
        let len = readlink("/proc/self/exe", &buf, buf.count - 1)
        if len > 0 { return String(cString: buf) }
        return ProcessInfo.processInfo.arguments[0]
    }

    private static func restartApp(path: String) {
        // execv replaces the current process image — the new binary starts fresh
        execv(path, CommandLine.unsafeArgv)
        // execv only returns on failure
        exit(0)
    }
}

/// Returns true if `candidate` is a higher semantic version than `current`.
func isNewer(_ candidate: String, than current: String) -> Bool {
    let a = candidate.split(separator: ".").compactMap { Int($0) }
    let b = current.split(separator: ".").compactMap { Int($0) }
    guard a.count == 3, b.count == 3 else { return false }
    return (a[0], a[1], a[2]) > (b[0], b[1], b[2])
}
