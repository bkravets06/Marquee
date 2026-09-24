import UIKit
import UserNotifications

// MARK: - AppDelegate

/// Handles launch-time registration (background refresh, notification
/// delegate) and routes notification taps into the app.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // MARK: UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefresh.register(container: AppModelContainer.shared, environment: AppEnvironment.shared)
        return true
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show reminders as banners even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Open the tapped item in the Library tab.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let rawID = userInfo["itemID"] as? String,
              let itemID = UUID(uuidString: rawID) else {
            return
        }
        Navigator.shared.open(itemID: itemID)
    }
}
