import SwiftUI

enum AppBuildInfo {
    /// Prefer marketing version + short git SHA injected at build time; fall back to version (build).
    static var identity: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let git = (Bundle.main.object(forInfoDictionaryKey: "YHPhotosGitCommit") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !git.isEmpty, git != "local", !git.hasPrefix("$(") {
            return "\(version)+\(git)"
        }
        return "\(version) (\(build))"
    }

    static var siteOrigin: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "YHPhotosAPIBaseURL") as? String,
           let url = URL(string: raw),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.path = ""
            components.query = nil
            components.fragment = nil
            if let origin = components.url { return origin }
        }
        return URL(string: "https://www.yhphotos.top")!
    }

    static var privacyPolicyURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "YHPhotosPrivacyPolicyURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return siteOrigin.appending(path: "privacy")
    }
}

/// Shared public legal footer matching the website bottom strip.
struct SiteLegalFooter: View {
    @Environment(\.openURL) private var openURL
    @State private var selectedDocument: LegalDocument?
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            HStack(spacing: 0) {
                legalLink(.terms)
                separator
                legalLink(.privacy)
                separator
                footerLink(L10n.string("系统状态"), URL(string: "https://status.yhphotos.top")!)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)

            Text(secondaryLine)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openURL(URL(string: "https://beian.miit.gov.cn/")!)
            } label: {
                Text(L10n.string("京ICP备2025139513号"))
                    .underline(false)
            }
            .buttonStyle(.plain)

            Text(L10n.format("构建 %@", AppBuildInfo.identity))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, compact ? 8 : 4)
        .padding(.vertical, compact ? 8 : 12)
        .sheet(item: $selectedDocument) { document in
            LegalDocumentView(document: document)
        }
    }

    private var secondaryLine: String {
        [
            L10n.string("版权所有 @lbynb_awa · 仿冒必究"),
            L10n.string("软著登字第16725856号"),
        ].joined(separator: " · ")
    }

    private var separator: some View {
        Text(" · ").foregroundStyle(.tertiary)
    }

    private func footerLink(_ title: String, _ url: URL) -> some View {
        Button(title) { openURL(url) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }

    private func legalLink(_ document: LegalDocument) -> some View {
        Button(document.title) { selectedDocument = document }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }
}
