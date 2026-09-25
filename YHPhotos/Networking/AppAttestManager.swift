import CryptoKit
import DeviceCheck
import Foundation
import Security

enum AppOriginError: LocalizedError {
    case unsupported
    case invalidChallenge
    case invalidServerResponse
    case server(code: String, message: String, status: Int)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "此设备不支持 App Attest。请使用已签名的真机版本。"
        case .invalidChallenge:
            "服务器下发的 App Attest challenge 无效"
        case .invalidServerResponse:
            "App 鉴权服务返回了无法识别的数据"
        case let .server(_, message, _):
            message
        }
    }
}

private enum AppOriginKeychain {
    static let service = "com.yhphotos.app.app-origin"

    static func data(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func string(for account: String) -> String? {
        data(for: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func set(_ value: String, for account: String) {
        let encoded = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: encoded]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = encoded
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

actor AppAttestManager {
    static let shared = AppAttestManager()

    private struct Challenge: Decodable {
        let challengeId: String
        let challenge: String
    }

    private struct TokenEnvelope: Decodable {
        let apiToken: String
        let expiresIn: Int
    }

    private struct AttestationBody: Encodable {
        let challengeId: String
        let keyId: String
        let attestationObject: String
    }

    private struct AssertionBody: Encodable {
        let challengeId: String
        let keyId: String
        let assertion: String
    }

    private struct ServerErrorEnvelope: Decodable {
        struct Payload: Decodable {
            let code: String?
            let message: String?
        }
        let error: Payload
    }

    private let service = DCAppAttestService.shared
    private let keyIdAccount = "app-attest-key-id"
    private let tokenAccount = "api-origin-token"

    func validToken(session: URLSession, baseURL: URL) async throws -> String {
        if let token = AppOriginKeychain.string(for: tokenAccount), !token.isEmpty {
            return token
        }
        return try await bootstrap(session: session, baseURL: baseURL)
    }

    func acceptRotatedToken(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        AppOriginKeychain.set(token, for: tokenAccount)
    }

    func invalidateToken() {
        AppOriginKeychain.remove(tokenAccount)
    }

    private func bootstrap(session: URLSession, baseURL: URL) async throws -> String {
        guard service.isSupported else { throw AppOriginError.unsupported }
        let challenge = try await requestChallenge(session: session, baseURL: baseURL)
        guard let challengeData = Data(base64Encoded: challenge.challenge) else {
            throw AppOriginError.invalidChallenge
        }

        if let keyId = AppOriginKeychain.string(for: keyIdAccount) {
            do {
                let hash = Data(SHA256.hash(data: challengeData))
                let assertion = try await service.generateAssertion(keyId, clientDataHash: hash)
                let envelope: TokenEnvelope = try await post(
                    "api/auth/app/assert",
                    body: AssertionBody(
                        challengeId: challenge.challengeId,
                        keyId: keyId,
                        assertion: assertion.base64EncodedString()
                    ),
                    session: session,
                    baseURL: baseURL
                )
                AppOriginKeychain.set(envelope.apiToken, for: tokenAccount)
                return envelope.apiToken
            } catch let error as AppOriginError {
                if case let .server(code, _, _) = error, code == "ios_app_key_unknown" {
                    AppOriginKeychain.remove(keyIdAccount)
                } else {
                    throw error
                }
            } catch {
                let nsError = error as NSError
                guard nsError.domain == DCErrorDomain else { throw error }
                AppOriginKeychain.remove(keyIdAccount)
            }
            return try await attestNewKey(session: session, baseURL: baseURL)
        }
        return try await attestNewKey(
            challenge: challenge,
            challengeData: challengeData,
            session: session,
            baseURL: baseURL
        )
    }

    private func attestNewKey(session: URLSession, baseURL: URL) async throws -> String {
        let challenge = try await requestChallenge(session: session, baseURL: baseURL)
        guard let challengeData = Data(base64Encoded: challenge.challenge) else {
            throw AppOriginError.invalidChallenge
        }
        return try await attestNewKey(
            challenge: challenge,
            challengeData: challengeData,
            session: session,
            baseURL: baseURL
        )
    }

    private func attestNewKey(
        challenge: Challenge,
        challengeData: Data,
        session: URLSession,
        baseURL: URL
    ) async throws -> String {
        let keyId = try await service.generateKey()
        let hash = Data(SHA256.hash(data: challengeData))
        let attestation = try await service.attestKey(keyId, clientDataHash: hash)
        let envelope: TokenEnvelope = try await post(
            "api/auth/app/attest",
            body: AttestationBody(
                challengeId: challenge.challengeId,
                keyId: keyId,
                attestationObject: attestation.base64EncodedString()
            ),
            session: session,
            baseURL: baseURL
        )
        AppOriginKeychain.set(keyId, for: keyIdAccount)
        AppOriginKeychain.set(envelope.apiToken, for: tokenAccount)
        return envelope.apiToken
    }

    private func requestChallenge(session: URLSession, baseURL: URL) async throws -> Challenge {
        struct Empty: Encodable { }
        return try await post(
            "api/auth/app/challenge",
            body: Empty(),
            session: session,
            baseURL: baseURL
        )
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        session: URLSession,
        baseURL: URL
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("YHPhotos-iOS/0.1 (Apple App Attest)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppOriginError.invalidServerResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: data)
            throw AppOriginError.server(
                code: envelope?.error.code ?? "http_\(http.statusCode)",
                message: envelope?.error.message ?? "App 鉴权失败（\(http.statusCode)）",
                status: http.statusCode
            )
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AppOriginError.invalidServerResponse
        }
        return decoded
    }
}
