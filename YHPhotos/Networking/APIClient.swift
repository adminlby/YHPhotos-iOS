import Foundation

enum APIClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case server(code: String, message: String, status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: L10n.string("API 地址配置无效")
        case .invalidResponse: L10n.string("服务器返回了无法识别的响应")
        case let .server(_, message, _): message
        }
    }
}

private struct APIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String?
        let message: String?
    }
    let error: Payload
}

/// App 来源 token 在有效期内可并发使用；只有凭据恢复由 AppAttestManager 合并为单任务。
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL? = nil) {
        let configured = Bundle.main.object(forInfoDictionaryKey: "YHPhotosAPIBaseURL") as? String
        self.baseURL = baseURL ?? URL(string: configured ?? "https://www.yhphotos.top")!

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Interactive loads (including pull-to-refresh) must finish instead of
        // holding SwiftUI's refresh control open while connectivity is absent.
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)
    }

    func get<Response: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        try await request(path, method: "GET", query: query, body: Optional<Data>.none, as: type)
    }

    func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        method: String = "POST",
        body: Body,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        return try await request(path, method: method, query: [], body: data, as: type)
    }

    func send<Response: Decodable & Sendable>(
        _ path: String,
        method: String,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        try await request(path, method: method, query: [], body: Optional<Data>.none, as: type)
    }

    func send<Response: Decodable & Sendable>(
        _ path: String,
        method: String,
        query: [URLQueryItem],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        try await request(path, method: method, query: query, body: Optional<Data>.none, as: type)
    }

    /// Loads authenticated binary content. Used for owner-only media such as
    /// the historical image attached to a moderation annotation.
    func data(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(normalizedPath),
            resolvingAgainstBaseURL: false
        ) else { throw APIClientError.invalidBaseURL }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIClientError.invalidBaseURL }

        func makeRequest(token: String) -> URLRequest {
            var request = APIRequestFactory.make(
                url: url,
                method: "GET",
                userAgent: "YHPhotos-iOS/0.1 (native; iOS)"
            )
            request.setValue("image/*, application/octet-stream", forHTTPHeaderField: "Accept")
            request.setValue(token, forHTTPHeaderField: "X-YH-App-Token")
            if let sessionToken = SessionCredentialStore.token {
                request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
            }
            return request
        }

        var token = try await AppAttestManager.shared.validToken(session: session, baseURL: baseURL)
        var (data, response) = try await session.data(for: makeRequest(token: token))
        guard var http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        await AppAttestManager.shared.acceptRotatedToken(
            http.value(forHTTPHeaderField: "X-YH-App-Token"),
            baseURL: baseURL
        )
        if http.statusCode == 403,
           let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           envelope.error.code?.hasPrefix("api_ios_app_token_") == true {
            await AppAttestManager.shared.invalidateToken(token, baseURL: baseURL)
            token = try await AppAttestManager.shared.validToken(session: session, baseURL: baseURL)
            (data, response) = try await session.data(for: makeRequest(token: token))
            guard let retriedHTTP = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
            http = retriedHTTP
            await AppAttestManager.shared.acceptRotatedToken(
                http.value(forHTTPHeaderField: "X-YH-App-Token"),
                baseURL: baseURL
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw APIClientError.server(
                code: envelope?.error.code ?? "http_\(http.statusCode)",
                message: envelope?.error.message ?? L10n.format("请求失败（%d）", http.statusCode),
                status: http.statusCode
            )
        }
        return data
    }

    func upload<Response: Decodable & Sendable>(
        _ path: String,
        imageData: Data,
        filename: String,
        mimeType: String,
        fields: [String: String],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let boundary = "YHPhotos-\(UUID().uuidString)"
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n")

        let url = baseURL.appendingPathComponent(path)
        var token = try await AppAttestManager.shared.validToken(session: session, baseURL: baseURL)
        func makeRequest(_ token: String) -> URLRequest {
            var request = APIRequestFactory.make(
                url: url,
                method: "POST",
                body: body,
                contentType: "multipart/form-data; boundary=\(boundary)",
                userAgent: "YHPhotos-iOS/0.1 (native; iOS)"
            )
            request.setValue(token, forHTTPHeaderField: "X-YH-App-Token")
            if let sessionToken = SessionCredentialStore.token {
                request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
            }
            return request
        }
        var (data, response) = try await session.data(for: makeRequest(token))
        guard var http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        await AppAttestManager.shared.acceptRotatedToken(
            http.value(forHTTPHeaderField: "X-YH-App-Token"),
            baseURL: baseURL
        )
        if http.statusCode == 403,
           let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           envelope.error.code?.hasPrefix("api_ios_app_token_") == true {
            await AppAttestManager.shared.invalidateToken(token, baseURL: baseURL)
            token = try await AppAttestManager.shared.validToken(session: session, baseURL: baseURL)
            (data, response) = try await session.data(for: makeRequest(token))
            guard let retriedHTTP = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
            http = retriedHTTP
            await AppAttestManager.shared.acceptRotatedToken(
                http.value(forHTTPHeaderField: "X-YH-App-Token"),
                baseURL: baseURL
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw APIClientError.server(
                code: envelope?.error.code ?? "http_\(http.statusCode)",
                message: envelope?.error.message ?? L10n.format("上传失败（%d）", http.statusCode),
                status: http.statusCode
            )
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw APIClientError.invalidResponse
        }
        return decoded
    }

    /// Uploads an arbitrary authenticated file using multipart/form-data.
    /// Admin rule PDFs use PUT rather than the image uploader's POST route.
    func uploadFile<Response: Decodable & Sendable>(
        _ path: String,
        method: String = "POST",
        data fileData: Data,
        filename: String,
        mimeType: String,
        fieldName: String = "file",
        fields: [String: String] = [:],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let boundary = "YHPhotos-\(UUID().uuidString)"
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename.replacingOccurrences(of: "\"", with: ""))\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appendingPathComponent(normalizedPath)
        var token = try await AppAttestManager.shared.validToken(session: session, baseURL: baseURL)

        func makeRequest(_ token: String) -> URLRequest {
            var request = APIRequestFactory.make(
                url: url,
                method: method,
                body: body,
                contentType: "multipart/form-data; boundary=\(boundary)",
                userAgent: "YHPhotos-iOS/0.1 (native; iOS)"
            )
            request.setValue(token, forHTTPHeaderField: "X-YH-App-Token")
            if let sessionToken = SessionCredentialStore.token {
                request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
            }
            return request
        }

        var (data, response) = try await session.data(for: makeRequest(token))
        guard var http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        await AppAttestManager.shared.acceptRotatedToken(
            http.value(forHTTPHeaderField: "X-YH-App-Token"),
            baseURL: baseURL
        )
        if http.statusCode == 403,
           let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           envelope.error.code?.hasPrefix("api_ios_app_token_") == true {
            await AppAttestManager.shared.invalidateToken(token, baseURL: baseURL)
            token = try await AppAttestManager.shared.validToken(session: session, baseURL: baseURL)
            (data, response) = try await session.data(for: makeRequest(token))
            guard let retriedHTTP = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
            http = retriedHTTP
            await AppAttestManager.shared.acceptRotatedToken(
                http.value(forHTTPHeaderField: "X-YH-App-Token"),
                baseURL: baseURL
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw APIClientError.server(
                code: envelope?.error.code ?? "http_\(http.statusCode)",
                message: envelope?.error.message ?? L10n.format("上传失败（%d）", http.statusCode),
                status: http.statusCode
            )
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { throw APIClientError.invalidResponse }
        return decoded
    }

    private func request<Response: Decodable & Sendable>(
        _ path: String,
        method: String,
        query: [URLQueryItem],
        body: Data?,
        as type: Response.Type
    ) async throws -> Response {
#if DEBUG
        if AppStoreDemo.isEnabled,
           let demoData = try AppStoreDemo.responseData(path: path, query: query) {
            return try JSONDecoder().decode(Response.self, from: demoData)
        }
#endif
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidBaseURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIClientError.invalidBaseURL }

        func makeRequest(token: String) -> URLRequest {
            var request = APIRequestFactory.make(
                url: url,
                method: method,
                body: body,
                contentType: body == nil ? nil : "application/json",
                userAgent: "YHPhotos-iOS/0.1 (native; iOS)"
            )
            request.setValue(token, forHTTPHeaderField: "X-YH-App-Token")
            if let sessionToken = SessionCredentialStore.token {
                request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
            }
            return request
        }

        var token = try await AppAttestManager.shared.validToken(session: session, baseURL: baseURL)
        var (data, response) = try await session.data(for: makeRequest(token: token))
        guard var http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        await AppAttestManager.shared.acceptRotatedToken(
            http.value(forHTTPHeaderField: "X-YH-App-Token"),
            baseURL: baseURL
        )

        if http.statusCode == 403,
           let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           envelope.error.code?.hasPrefix("api_ios_app_token_") == true {
            await AppAttestManager.shared.invalidateToken(token, baseURL: baseURL)
            token = try await AppAttestManager.shared.validToken(session: session, baseURL: baseURL)
            (data, response) = try await session.data(for: makeRequest(token: token))
            guard let retriedHTTP = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
            http = retriedHTTP
            await AppAttestManager.shared.acceptRotatedToken(
                http.value(forHTTPHeaderField: "X-YH-App-Token"),
                baseURL: baseURL
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw APIClientError.server(
                code: envelope?.error.code ?? "http_\(http.statusCode)",
                message: envelope?.error.message ?? L10n.format("请求失败（%d）", http.statusCode),
                status: http.statusCode
            )
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIClientError.server(
                code: "decode_error",
                message: L10n.string("服务器返回了无法识别的响应"),
                status: http.statusCode
            )
        }
    }
}

extension APIClient {
    struct LoginPasswordBody: Encodable, Sendable {
        let identifier: String
        let password: String
        let remember: Bool
    }

    struct ToggleBody: Encodable, Sendable { let enabled: Bool }
    struct CommentBody: Encodable, Sendable { let content: String }
    struct EmptyResponse: Decodable, Sendable { let ok: Bool? }
    struct EmptyBody: Encodable, Sendable { }
    struct AccountDeletionBody: Encodable, Sendable { let confirmation: String }

    struct SSOPreparation: Decodable, Sendable {
        let startPath: String
        let callbackScheme: String
    }

    struct AppSSOResponse: Decodable, Sendable {
        let sessionToken: String
        let user: SessionUser
    }

    struct SSOExchangeBody: Encodable, Sendable { let code: String }
    struct LegalAcceptanceBody: Encodable, Sendable {
        let version: String
        let accept_terms: Bool
    }
    struct PushDeviceBody: Encodable, Sendable {
        let deviceToken: String
        let environment: String
        let bundleId: String
    }

    func prepareSSO() async throws -> (url: URL, callbackScheme: String) {
        let value: SSOPreparation = try await send("api/auth/app/sso/prepare", body: EmptyBody())
        guard let url = URL(string: value.startPath, relativeTo: baseURL)?.absoluteURL else {
            throw APIClientError.invalidBaseURL
        }
        return (url, value.callbackScheme)
    }

    func prepareAccountManagement() async throws -> (url: URL, callbackScheme: String) {
        let value: SSOPreparation = try await send("api/auth/app/account/prepare", body: EmptyBody())
        guard let url = URL(string: value.startPath, relativeTo: baseURL)?.absoluteURL else {
            throw APIClientError.invalidBaseURL
        }
        return (url, value.callbackScheme)
    }

    func exchangeSSO(code: String) async throws -> AppSSOResponse {
        try await send("api/auth/app/sso/exchange", body: SSOExchangeBody(code: code))
    }

    func acceptLegalTerms(version: String) async throws -> SessionEnvelope {
        try await send(
            "api/auth/legal/accept",
            body: LegalAcceptanceBody(version: version, accept_terms: true)
        )
    }

    func registerPushDevice(token: String, environment: String, bundleID: String) async throws {
        let _: EmptyResponse = try await send(
            "api/me/push-devices",
            body: PushDeviceBody(deviceToken: token, environment: environment, bundleId: bundleID)
        )
    }

    func unregisterPushDevice(token: String) async throws {
        let escaped = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        let _: EmptyResponse = try await send("api/me/push-devices/\(escaped)", method: "DELETE")
    }

    func deleteAccount() async throws {
        let _: EmptyResponse = try await send(
            "api/me/account",
            method: "DELETE",
            body: AccountDeletionBody(confirmation: "DELETE")
        )
    }
}
