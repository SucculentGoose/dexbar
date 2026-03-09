#if canImport(CLibNotify)
import CLibNotify
import Foundation

/// Sends desktop notifications via libnotify (D-Bus org.freedesktop.Notifications).
/// Mirrors the cooldown behaviour of the macOS NotificationManager.
final class LinuxNotificationManager: @unchecked Sendable {
    static let shared = LinuxNotificationManager()

    enum AlertType: String {
        case urgentHigh, high, urgentLow, low, risingFast, droppingFast, staleData
    }

    private let lock = NSLock()
    private var lastNotified: [String: Date] = [:]
    private let cooldown: TimeInterval = 15 * 60

    private init() {}

    func send(type: AlertType, title: String, body: String, urgent: Bool = false) {
        lock.lock()
        let now = Date()
        if let last = lastNotified[type.rawValue], now.timeIntervalSince(last) < cooldown {
            lock.unlock()
            return
        }
        lastNotified[type.rawValue] = now
        lock.unlock()

        let notification = notify_notification_new(title, body, urgent ? "dialog-warning" : "dialog-information")
        if urgent {
            notify_notification_set_urgency(notification, NOTIFY_URGENCY_CRITICAL)
        }
        var gerror: UnsafeMutablePointer<GError>? = nil
        notify_notification_show(notification, &gerror)
        if let err = gerror {
            fputs("Notification error: \(String(cString: err.pointee.message))\n", stderr)
            g_error_free(err)
        }
        g_object_unref(notification)
    }

    func resetCooldowns() {
        lock.lock()
        lastNotified.removeAll()
        lock.unlock()
    }
}
#endif
