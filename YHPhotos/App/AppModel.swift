import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case discover
    case tools
    case upload
    case messages
    case profile

    var id: String { rawValue }
    var title: String {
        switch self {
        case .discover: L10n.string("发现")
        case .tools: L10n.string("工具")
        case .upload: L10n.string("上传")
        case .messages: L10n.string("消息")
        case .profile: L10n.string("我的")
        }
    }
    var icon: String {
        switch self {
        case .discover: "safari.fill"
        case .tools: "wrench.and.screwdriver.fill"
        case .upload: "plus"
        case .messages: "bubble.left.fill"
        case .profile: "person.fill"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .discover
    @Published var sessionUser: SessionUser?
    @Published private(set) var adminIdentity: AdminIdentity?
    @Published var showingUpload = false
    @Published var showingLogin = false
    @Published private(set) var unreadDirectMessages = 0
    @Published private(set) var unreadSiteNotifications = 0
    @Published private(set) var unreadMessages = 0
    @Published private(set) var hasRestoredSession = false
    @Published private(set) var sessionRestoreError: String?

    private let api: APIClient
    private let ssoWebAuthentication = SSOWebAuthentication()
    private var unreadMutationGeneration = 0

    init(api: APIClient = .shared) {
        self.api = api
#if DEBUG
        if AppStoreDemo.isEnabled {
            sessionUser = AppStoreDemo.sessionUser
            if AppStoreDemo.screen == .tools || AppStoreDemo.screen == .inspector {
                selectedSection = .tools
            }
        } else if let data = UserDefaults.standard.data(forKey: "sessionUser"),
                  let cached = try? JSONDecoder().decode(SessionUser.self, from: data) {
            sessionUser = cached
        }
#else
        if let data = UserDefaults.standard.data(forKey: "sessionUser"),
           let cached = try? JSONDecoder().decode(SessionUser.self, from: data) {
            sessionUser = cached
        }
#endif
        NotificationCenter.default.addObserver(
            forName: .yhPushNotificationOpened,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self else { return }
                self.openPushNotification(category: note.userInfo?["category"] as? String)
                await self.refreshUnreadCount()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .yhUnreadCountsShouldRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshUnreadCount() }
        }
    }

    func select(_ section: AppSection) {
        if section == .upload {
            if sessionUser == nil { showingLogin = true } else { showingUpload = true }
        } else {
            selectedSection = section
        }
    }

    func restoreSession() async {
        hasRestoredSession = false
        sessionRestoreError = nil
        defer { hasRestoredSession = true }
#if DEBUG
        if AppStoreDemo.isEnabled {
            sessionUser = AppStoreDemo.sessionUser
            unreadMutationGeneration &+= 1
            applyUnreadCounts(direct: 1, site: 1)
            return
        }
#endif
        do {
            let envelope: SessionEnvelope = try await api.get("api/auth/me")
            setSession(envelope.user)
            await refreshAdminAccess()
            await PushNotificationManager.shared.synchronizeAuthorizationWithServerPreferences(using: api)
            await refreshUnreadCount()
        } catch let error as APIClientError {
            if case let .server(_, _, status) = error, status == 401 {
                clearSession()
            } else if sessionUser != nil {
                // A cached authenticated session must not bypass a newly
                // required legal version when the authoritative check fails.
                sessionRestoreError = error.localizedDescription
            }
        } catch {
            if sessionUser != nil {
                sessionRestoreError = error.localizedDescription
            }
        }
    }

    var requiresLegalAcceptance: Bool {
        sessionUser?.legal?.required == true
    }

    var requiredLegalVersion: String? {
        sessionUser?.legal?.currentVersion
    }

    func acceptRequiredLegalTerms() async throws {
        guard let version = requiredLegalVersion, !version.isEmpty else {
            throw APIClientError.invalidResponse
        }
        let envelope = try await api.acceptLegalTerms(version: version)
        setSession(envelope.user)
    }

    func loginWithSSO() async throws {
        let preparation = try await api.prepareSSO()
        let callbackURL = try await ssoWebAuthentication.authenticate(
            startURL: preparation.url,
            callbackScheme: preparation.callbackScheme
        )
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              components.host == "sso-callback",
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw APIClientError.invalidResponse
        }
        let response = try await api.exchangeSSO(code: code)
        SessionCredentialStore.save(response.sessionToken)
        setSession(response.user)
        await refreshAdminAccess()
        await PushNotificationManager.shared.synchronizeAuthorizationWithServerPreferences(using: api)
        await refreshUnreadCount()
    }

    func logout() async {
        await PushNotificationManager.shared.unregisterCurrentDevice()
        _ = try? await api.send("api/auth/logout", method: "POST", as: APIClient.EmptyResponse.self)
        SessionCredentialStore.clear()
        clearSession()
        selectedSection = .discover
    }

    func deleteAccount() async throws {
        try await api.deleteAccount()
        SessionCredentialStore.clear()
        clearSession()
        selectedSection = .discover
    }

    private func openPushNotification(category: String?) {
        switch category {
        case "message", "comment", "follow", "like", "review", "photo", "saved_search", "newsletter", "security", .none:
            selectedSection = .messages
        default:
            selectedSection = .messages
        }
    }

    func refreshUnreadCount() async {
        struct Unread: Decodable, Sendable { let unread: Int }
        guard sessionUser != nil else {
            unreadMutationGeneration &+= 1
            applyUnreadCounts(direct: 0, site: 0)
            return
        }
        let generation = unreadMutationGeneration
        async let directRequest: Unread? = try? await api.get("api/messages/unread-count")
        async let siteRequest: Unread? = try? await api.get("api/me/notifications/unread-count")
        let (direct, site) = await (directRequest, siteRequest)
        guard generation == unreadMutationGeneration else { return }
        applyUnreadCounts(direct: direct?.unread, site: site?.unread)
    }

    func setUnreadDirectMessages(_ count: Int) {
        unreadMutationGeneration &+= 1
        applyUnreadCounts(direct: count)
    }

    func setUnreadSiteNotifications(_ count: Int) {
        unreadMutationGeneration &+= 1
        applyUnreadCounts(site: count)
    }

    private func applyUnreadCounts(direct: Int? = nil, site: Int? = nil) {
        if let direct { unreadDirectMessages = max(0, direct) }
        if let site { unreadSiteNotifications = max(0, site) }
        unreadMessages = unreadDirectMessages + unreadSiteNotifications
        PushNotificationManager.shared.updateApplicationBadge(unreadMessages)
    }

    /// Checks the real RBAC entry point instead of inferring access from a role
    /// name. Custom permission groups and user-level grants/denies are therefore
    /// reflected exactly as they are in the website administration console.
    func refreshAdminAccess() async {
        guard sessionUser != nil else {
            adminIdentity = nil
            return
        }
        do {
            adminIdentity = try await api.get("api/admin/me")
        } catch let error as APIClientError {
            // A transient refresh failure must not make the admin entry vanish.
            // Clear it only when the server explicitly rejects the permission.
            if case let .server(_, _, status) = error, status == 401 || status == 403 {
                adminIdentity = nil
            }
        } catch {
            // Preserve the last verified identity while temporarily offline.
        }
    }

    private func setSession(_ user: SessionUser) {
        sessionUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "sessionUser")
        }
    }

    private func clearSession() {
        sessionUser = nil
        adminIdentity = nil
        unreadMutationGeneration &+= 1
        applyUnreadCounts(direct: 0, site: 0)
        UserDefaults.standard.removeObject(forKey: "sessionUser")
        SessionCredentialStore.clear()
    }
}
