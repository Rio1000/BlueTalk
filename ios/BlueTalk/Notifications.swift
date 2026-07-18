import UserNotifications

/// Local notifications for messages that arrive while their conversation is
/// off screen. There is no server in BlueTalk, so these are local
/// notifications posted by the app itself, not remote push.
enum LocalNotifications {

    /// Presents banners even while the app is in the foreground (e.g. the
    /// user is on the conversation list when a message lands in another chat).
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .sound])
        }
    }

    private static let delegate = Delegate()

    /// Call once at launch so foreground banners work.
    static func configure() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(title: String, body: String, threadId: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = threadId
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
