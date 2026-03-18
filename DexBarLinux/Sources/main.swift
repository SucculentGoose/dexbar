// DexBar Linux — main entry point
// Requires: GTK4, libdbusmenu-glib, libsecret, libnotify

#if canImport(CGtk4) && canImport(CDbusmenu)
import CGtk4
import CDbusmenu
import DexBarCore
import Foundation

#if canImport(CLibNotify)
import CLibNotify
#endif

// MARK: - Bootstrap

gtk_init()

#if canImport(CLibNotify)
notify_init("DexBar")
#endif

// MARK: - GLib main loop (replaces gtk_main in GTK4)

let mainLoop = g_main_loop_new(nil, 0)!

// MARK: - Application components
// We know we're on the main thread (GLib single-threaded loop), so it's
// safe to use MainActor.assumeIsolated here.

MainActor.assumeIsolated {
    let monitor  = GlucoseMonitorLinux()
    let popup    = PopupWindow(monitor: monitor)
    let settings = SettingsWindow(monitor: monitor)
    let overlay  = StatusOverlay(monitor: monitor)
    let updater  = LinuxUpdater()

    popup.onOpenSettings = { settings.show() }
    popup.onCheckUpdates = { updater.checkForUpdates() }

    let tray = TrayIcon(
        monitor: monitor,
        onTogglePopup: { popup.toggle() },
        onOpenSettings: { settings.show() }
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

    signal(SIGTERM) { _ in UserDefaults.standard.synchronize(); g_main_loop_quit(mainLoop) }
    signal(SIGINT)  { _ in UserDefaults.standard.synchronize(); g_main_loop_quit(mainLoop) }

    // MARK: - Run main loop

    // g_main_loop_run() drives GLib's event loop but doesn't drain Swift's RunLoop.main,
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

    g_main_loop_run(mainLoop)

    UserDefaults.standard.synchronize()

#if canImport(CLibNotify)
    notify_uninit()
#endif
}

#else
import Foundation
fputs("DexBarLinux requires GTK4 and libdbusmenu-glib. Build on Linux only.\n", stderr)
exit(1)
#endif
