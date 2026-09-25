import Combine
import UIKit
import UserNotifications

@MainActor
final class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var deviceToken: String?

    private override init() {
        super.init()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        Task {
            await refreshAuthorizationStatus()
            if authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    @discardableResult
    func requestAuthorizationAndRegister() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await registerCurrentDevice() }
    }

    func registerCurrentDevice() async {
        guard SessionCredentialStore.token != nil, let deviceToken else { return }
        try? await APIClient.shared.registerPushDevice(
            token: deviceToken,
            environment: Bundle.main.object(forInfoDictionaryKey: "YHPhotosAPNSEnvironment") as? String ?? "production",
            bundleID: Bundle.main.bundleIdentifier ?? "com.yhphotos.app"
        )
    }

    func unregisterCurrentDevice() async {
        guard let deviceToken else { return }
        _ = try? await APIClient.shared.unregisterPushDevice(token: deviceToken)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let category = response.notification.request.content.userInfo["category"] as? String
        await MainActor.run {
            NotificationCenter.default.post(
                name: .yhPushNotificationOpened,
                object: nil,
                userInfo: category.map { ["category": $0] }
            )
        }
    }
}

final class YHPhotosAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PushNotificationManager.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushNotificationManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in await PushNotificationManager.shared.refreshAuthorizationStatus() }
    }
}

extension Notification.Name {
    static let yhPushNotificationOpened = Notification.Name("YHPhotosPushNotificationOpened")
}
