// DexBar Linux — main entry point
// Requires: GTK3, libayatana-appindicator3, libsecret, libnotify

#if canImport(CGtk3) && canImport(CAppIndicator)
import CGtk3
import CAppIndicator
import DexBarCore
import Foundation

#if canImport(CLibNotify)
import CLibNotify
#endif

// MARK: - Bootstrap

gtk_init(nil, nil)

#if canImport(CLibNotify)
notify_init("DexBar")
#endif

// MARK: - Application components
// We know we're on the main thread (GLib single-threaded loop), so it's
// safe to use MainActor.assumeIsolated here.

MainActor.assumeIsolated {
    let monitor  = GlucoseMonitorLinux()
    let popup    = PopupWindow(monitor: monitor)
    let settings = SettingsWindow(monitor: monitor)
    let overlay  = StatusOverlay(monitor: monitor)
    let updater  = LinuxUpdater()

    let tray = TrayIcon(
        monitor: monitor,
        onTogglePopup: { popup.toggle() },
        onOpenSettings: { settings.show() },
        onToggleOverlay: { overlay.toggle() }
    )

    monitor.onUpdate = {
        tray.update()
        popup.update()
        settings.updateStatus()
        overlay.update()
    }

    updater.onUpdateAvailable = { version, install in
        tray.showUpdateAvailable(version: version, onInstall: install)
#if canImport(CLibNotify)
        let body = "Version \(version) is available. Click 'Install Update' in the tray menu."
        let n = notify_notification_new("DexBar Update Available", body, "software-update-available")
        notify_notification_show(n, nil)
#endif
    }
    updater.onStatusChange = { text in
        tray.setUpdateStatus(text)
    }

    // Check for updates shortly after launch, then once every 24 hours
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
        updater.checkForUpdates()
    }
    let updateTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
        Task { @MainActor in updater.checkForUpdates() }
    }
    _ = updateTimer // retain

    // MARK: - SIGTERM / SIGINT handler

    signal(SIGTERM) { _ in UserDefaults.standard.synchronize(); gtk_main_quit() }
    signal(SIGINT)  { _ in UserDefaults.standard.synchronize(); gtk_main_quit() }

    // MARK: - Run main loop

    // gtk_main() drives GLib's event loop but doesn't drain Swift's RunLoop.main,
    // which is needed by Task { @MainActor in ... } and Foundation.Timer.
    // This 10 ms GLib timer bridges the two, so async tasks actually execute.
    let drainRunLoop: @convention(c) (gpointer?) -> gboolean = { _ in
        RunLoop.main.run(until: Date())
        return 1  // G_SOURCE_CONTINUE
    }
    g_timeout_add(10, drainRunLoop, nil)

    // Flush UserDefaults to disk every 5 seconds — swift-foundation on Linux does not
    // auto-sync on every set(), so without this the plist is never written.
    let syncDefaults: @convention(c) (gpointer?) -> gboolean = { _ in
        UserDefaults.standard.synchronize()
        return 1  // G_SOURCE_CONTINUE
    }
    g_timeout_add(5000, syncDefaults, nil)

    gtk_main()

    UserDefaults.standard.synchronize()

#if canImport(CLibNotify)
    notify_uninit()
#endif
}

#else
import Foundation
fputs("DexBarLinux requires GTK3 and libayatana-appindicator3. Build on Linux only.\n", stderr)
exit(1)
#endif
