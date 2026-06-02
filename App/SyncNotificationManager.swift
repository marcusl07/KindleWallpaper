import Foundation
import UserNotifications

@MainActor
final class SyncNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SyncNotificationManager()
    
    private override init() {
        super.init()
        #if !TESTING
        UNUserNotificationCenter.current().delegate = self
        #endif
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    
    // Present notification banner even when the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
