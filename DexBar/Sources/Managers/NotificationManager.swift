import UserNotifications
import Foundation

actor NotificationManager {
    static let shared = NotificationManager()

    // Track last notification time per alert type to avoid spamming
    private var lastNotified: [AlertType: Date] = [:]
    private let cooldown: TimeInterval = 15 * 60 // 15 minutes between same-type alerts

    enum AlertType: String {
        case high, low, risingFast, droppingFast
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func send(type: AlertType, title: String, body: String) async {
        let now = Date()
        if let last = lastNotified[type], now.timeIntervalSince(last) < cooldown {
            return // still in cooldown
        }
        lastNotified[type] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(type.rawValue)-\(now.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func resetCooldowns() {
        lastNotified.removeAll()
    }
}
