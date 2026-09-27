import SwiftUI
import UIKit

enum MediaURL {
    private static var apiBase: URL {
        (Bundle.main.object(forInfoDictionaryKey: "YHPhotosAPIBaseURL") as? String)
            .flatMap(URL.init(string:))
            ?? URL(string: "https://www.yhphotos.top")!
    }

    private static var imagesBase: URL {
        let host = apiBase.host ?? "www.yhphotos.top"
        if host == "www.yhphotos.top" || host == "dev.yhphotos.top" || host.hasSuffix(".yhphotos.top") {
            return URL(string: "https://images.yhphotos.top")!
        }
        if host.hasPrefix("www.") {
            return URL(string: "https://images.\(host.dropFirst(4))") ?? apiBase
        }
        return apiBase
    }

    /// Resolve absolute/relative/filename media references from the API.
    static func resolve(_ raw: String?) -> URL? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let url = URL(string: value), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return preferImagesCDN(url)
        }

        // Bare filename → avatar object key (same as web `mediaUrl("avatars", filename)`).
        if !value.contains("/") {
            value = "uploads/avatars/\(value)"
        } else if value.hasPrefix("avatars/") {
            value = "uploads/\(value)"
        }
        if value.hasPrefix("/") { value.removeFirst() }

        return URL(string: value, relativeTo: imagesBase)?.absoluteURL
    }

    /// Prefer `avatar` URL, then build from `avatar_filename` like the website.
    static func avatar(urlString: String?, filename: String?) -> URL? {
        resolve(urlString) ?? resolve(filename)
    }

    /// Site photos live on images.*; some API payloads still point at www/dev.
    private static func preferImagesCDN(_ url: URL) -> URL {
        guard let host = url.host?.lowercased() else { return url }
        let shouldRewrite = host == "www.yhphotos.top" || host == "dev.yhphotos.top"
            || host == apiBase.host?.lowercased()
        guard shouldRewrite else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = imagesBase.host
        components?.scheme = "https"
        return components?.url ?? url
    }
}

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    init(urlString: String?, contentMode: ContentMode = .fill) {
        self.url = MediaURL.resolve(urlString)
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
                            .overlay { Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary) }
                    case .empty:
                        placeholder.overlay { ProgressView().tint(.secondary) }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.primary.opacity(0.09), Color.primary.opacity(0.025)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Avatar loader uses URLSession instead of AsyncImage — AsyncImage often stays on the
/// placeholder when nested in toolbars / clipped circles.
struct AvatarView: View {
    let urlString: String?
    let name: String
    var size: CGFloat = 36
    var filename: String? = nil

    @State private var image: UIImage?
    @State private var failed = false
    @State private var loading = false

    private var url: URL? { MediaURL.avatar(urlString: urlString, filename: filename) }

    var body: some View {
        ZStack {
            Circle().fill(AppTheme.accent.opacity(0.18))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else if loading {
                ProgressView()
                    .controlSize(.small)
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.14), lineWidth: 0.75))
        .accessibilityLabel(name)
        .task(id: url?.absoluteString) { await load() }
    }

    private var initialsView: some View {
        Group {
            if let initial = name.trimmingCharacters(in: .whitespacesAndNewlines).first {
                Text(String(initial))
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    @MainActor
    private func load() async {
        image = nil
        failed = false
        guard let url else {
            failed = true
            return
        }
        loading = true
        defer { loading = false }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("YHPhotos-iOS/0.1 (native; iOS)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data) else {
                failed = true
                return
            }
            image = decoded
        } catch {
            failed = true
        }
    }
}
