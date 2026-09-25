import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case discover
    case wiki
    case upload
    case messages
    case profile

    var id: String { rawValue }
    var title: String {
        switch self {
        case .discover: L10n.string("发现")
        case .wiki: L10n.string("百科")
        case .upload: L10n.string("上传")
        case .messages: L10n.string("消息")
        case .profile: L10n.string("我的")
        }
    }
    var icon: String {
        switch self {
        case .discover: "safari.fill"
        case .wiki: "book.fill"
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
    @Published var showingUpload = false
    @Published var showingLogin = false
    @Published var unreadMessages = 0

    private let api: APIClient
    private let ssoWebAuthentication = SSOWebAuthentication()

    init(api: APIClient = .shared) {
        self.api = api
        if let data = UserDefaults.standard.data(forKey: "sessionUser"),
           let cached = try? JSONDecoder().decode(SessionUser.self, from: data) {
            sessionUser = cached
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
        do {
            let envelope: SessionEnvelope = try await api.get("api/auth/me")
            setSession(envelope.user)
            await refreshUnreadCount()
        } catch let error as APIClientError {
            if case let .server(_, _, status) = error, status == 401 {
                clearSession()
            }
        } catch { }
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
        await refreshUnreadCount()
    }

    func logout() async {
        _ = try? await api.send("api/auth/logout", method: "POST", as: APIClient.EmptyResponse.self)
        SessionCredentialStore.clear()
        clearSession()
        selectedSection = .discover
    }

    func refreshUnreadCount() async {
        struct Unread: Decodable, Sendable { let unread: Int }
        guard sessionUser != nil else { unreadMessages = 0; return }
        if let value: Unread = try? await api.get("api/messages/unread-count") {
            unreadMessages = value.unread
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
        unreadMessages = 0
        UserDefaults.standard.removeObject(forKey: "sessionUser")
        SessionCredentialStore.clear()
    }
}
