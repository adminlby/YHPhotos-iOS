import Foundation

enum APIRequestFactory {
    static func make(
        url: URL,
        method: String,
        body: Data? = nil,
        contentType: String? = nil,
        userAgent: String
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let language = AppLanguage.selected
        request.setValue(language.apiValue, forHTTPHeaderField: "X-YHPhotos-Language")
        request.setValue(language.httpLanguageTag, forHTTPHeaderField: "Accept-Language")
        return request
    }
}
