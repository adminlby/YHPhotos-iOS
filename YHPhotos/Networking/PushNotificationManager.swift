import Combine
import UIKit
import UserNotifications

@MainActor
final class PushNotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()
    private static let preferenceCacheKey = "YHPhotosPushPreferencesEnabled"

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var shouldOfferSystemSettings = false
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

    /// Keeps the system permission in sync with App push switches stored by the website.
    /// iOS only shows the authorization sheet while the state is `notDetermined`;
    /// a previously denied permission can only be changed by the user in Settings.
    func synchronizeAuthorization(for preferences: [String: Bool]) async {
        let pushEnabled = preferences.contains { key, value in
            key.hasPrefix("push_") && value
        }
        UserDefaults.standard.set(pushEnabled, forKey: Self.preferenceCacheKey)
        guard pushEnabled else {
            shouldOfferSystemSettings = false
            return
        }

        await refreshAuthorizationStatus()
        switch authorizationStatus {
        case .notDetermined:
            shouldOfferSystemSettings = false
            _ = await requestAuthorizationAndRegister()
        case .authorized, .provisional, .ephemeral:
            shouldOfferSystemSettings = false
            UIApplication.shared.registerForRemoteNotifications()
            await registerCurrentDevice()
        case .denied:
            shouldOfferSystemSettings = true
        @unknown default:
            shouldOfferSystemSettings = false
            break
        }
    }

    func dismissSystemSettingsOffer() {
        shouldOfferSystemSettings = false
    }

    func updateApplicationBadge(_ count: Int) {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(max(0, count))
        }
    }

    /// Called after session restoration/login so website changes take effect on
    /// the next App launch even when the notification settings screen is never opened.
    func synchronizeAuthorizationWithServerPreferences(using api: APIClient = .shared) async {
        do {
            let preferences: [String: Bool] = try await api.get("api/me/notification-preferences")
            await synchronizeAuthorization(for: preferences)
        } catch {
            // A last known enabled App preference still warrants presenting the
            // one-time system prompt when the preference endpoint is temporarily unavailable.
            guard UserDefaults.standard.bool(forKey: Self.preferenceCacheKey) else { return }
            await synchronizeAuthorization(for: ["push_cached": true])
        }
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
        await MainActor.run {
            NotificationCenter.default.post(name: .yhUnreadCountsShouldRefresh, object: nil)
        }
        return [.banner, .list, .sound]
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
    static let yhUnreadCountsShouldRefresh = Notification.Name("YHPhotosUnreadCountsShouldRefresh")
}
