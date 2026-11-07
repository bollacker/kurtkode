import AppKit
import UserNotifications

/// Desktop notifications when a run finishes, stops, or waits for an approval while kurtkode isn't the front app.
/// Clicking one brings the app forward on that session. Settings → Generation → "Notify me…" (on by default).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    /// Set by the app: opens a session (the main window's selection).
    var open: ((UUID) -> Void)?
    private var asked = false

    private var enabled: Bool {
        #if DEBUG
        // Test instances run in the background: they'd notify on the user's screen.
        if ProcessInfo.processInfo.environment["KURTKODE_NO_NOTIFY"] == "1" { return false }
        #endif
        return Pref.d.object(forKey: Pref.notify) as? Bool ?? true
    }

    /// Posts unless kurtkode is the front app (the user is looking) or notifications are off.
    func post(title: String, body: String, session: UUID) {
        guard enabled, !NSApp.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task {
            if !asked {
                asked = true
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["session": session.uuidString]
            // One per session: a newer one replaces the older (a run that asked, then finished).
            try? await center.add(UNNotificationRequest(identifier: session.uuidString, content: content, trigger: nil))
        }
    }

    /// The user looked at the session: its notification is no longer news.
    func clear(session: UUID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [session.uuidString])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = (response.notification.request.content.userInfo["session"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run {
            NSApp.activate()
            if let id { open?(id) }
        }
    }
}
