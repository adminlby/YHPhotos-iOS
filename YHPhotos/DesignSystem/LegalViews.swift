import SwiftUI
import WebKit

enum LegalDocument: String, Identifiable {
    case terms
    case eula
    case privacy
    case communityRules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: L10n.string("服务协议")
        case .eula: L10n.string("最终用户许可协议（EULA）")
        case .privacy: L10n.string("隐私政策")
        case .communityRules: L10n.string("社区规范")
        }
    }

    var systemImage: String {
        switch self {
        case .terms: "doc.text.fill"
        case .eula: "checkmark.seal.fill"
        case .privacy: "hand.raised.fill"
        case .communityRules: "person.2.badge.gearshape.fill"
        }
    }

    var url: URL {
        switch self {
        case .terms:
            return AppBuildInfo.siteOrigin.appending(path: "terms")
        case .eula:
            return URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
        case .privacy:
            return AppBuildInfo.privacyPolicyURL
        case .communityRules:
            var components = URLComponents(
                url: AppBuildInfo.siteOrigin.appending(path: "rules"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "section", value: "site")]
            return components?.url ?? AppBuildInfo.siteOrigin.appending(path: "rules")
        }
    }
}

struct LegalConsentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var hasConfirmed = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var selectedDocument: LegalDocument?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 12)

                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)

                    VStack(spacing: 9) {
                        Text(L10n.string("服务条款已更新"))
                            .font(.title2.bold())
                        Text(
                            L10n.format(
                                "继续使用 YHPhotos 前，请阅读并同意当前版本（%@）的服务协议、EULA、隐私政策与社区规范。",
                                appModel.requiredLegalVersion ?? L10n.string("当前版本")
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    GlassPanel(cornerRadius: 22) {
                        VStack(spacing: 0) {
                            documentButton(.terms)
                            Divider().overlay(AppTheme.divider)
                            documentButton(.eula)
                            Divider().overlay(AppTheme.divider)
                            documentButton(.privacy)
                            Divider().overlay(AppTheme.divider)
                            documentButton(.communityRules)
                        }
                        .padding(.horizontal, 16)
                    }

                    Label(
                        L10n.string("YHPhotos 对违规内容、骚扰和滥用行为实行零容忍。你可以在图片、评论、私信和用户主页中举报或屏蔽，并通过帮助与反馈联系我们。"),
                        systemImage: "person.2.badge.gearshape.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        hasConfirmed.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: hasConfirmed ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(hasConfirmed ? AppTheme.accent : .secondary)
                            Text(L10n.string("我已阅读并同意服务协议、最终用户许可协议（EULA）、隐私政策与社区规范"))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(hasConfirmed ? L10n.string("已勾选") : L10n.string("未勾选"))

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(spacing: 12) {
                        Button {
                            Task { await accept() }
                        } label: {
                            HStack(spacing: 9) {
                                if isSubmitting { ProgressView().tint(.white) }
                                Text(L10n.string("同意并继续"))
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .disabled(!hasConfirmed || isSubmitting)

                        Button(role: .destructive) {
                            Task { await appModel.logout() }
                        } label: {
                            Text(L10n.string("退出登录"))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(isSubmitting)
                    }

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("YHPhotos")
            .navigationBarTitleDisplayMode(.inline)
            .appScreenBackground()
        }
        .sheet(item: $selectedDocument) { document in
            LegalDocumentView(document: document)
        }
    }

    private func documentButton(_ document: LegalDocument) -> some View {
        Button {
            selectedDocument = document
        } label: {
            HStack(spacing: 12) {
                Image(systemName: document.systemImage)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28)
                Text(document.title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func accept() async {
        guard hasConfirmed, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await appModel.acceptRequiredLegalTerms()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: LegalDocument

    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LegalWebView(
                    url: document.url,
                    language: AppLanguage.resolved,
                    isLoading: $isLoading,
                    errorMessage: $errorMessage
                )

                if isLoading {
                    ProgressView(L10n.string("正在加载…"))
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                } else if let errorMessage {
                    EmptyStateView(
                        L10n.string("无法加载法律文档"),
                        systemImage: "wifi.exclamationmark",
                        description: errorMessage
                    )
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("完成")) { dismiss() }
                }
            }
        }
    }
}

struct CommunitySafetyInfoView: View {
    @State private var selectedDocument: LegalDocument?

    var body: some View {
        List {
            Section {
                safetyRow(
                    "上传前审核",
                    "用户上传的图片须经内容审核通过后才会公开展示。",
                    systemImage: "checkmark.shield.fill"
                )
                safetyRow(
                    "举报与人工处理",
                    "图片、评论、私信和用户主页均提供举报入口；举报会进入人工审核并显示处理进度。",
                    systemImage: "flag.fill"
                )
                safetyRow(
                    "屏蔽滥用用户",
                    "你可以屏蔽其他用户。屏蔽会解除双方关注、阻止双方私信，并在相关页面隐藏对方内容。",
                    systemImage: "person.crop.circle.badge.xmark"
                )
            } header: {
                Text(L10n.string("安全机制"))
            } footer: {
                Text(L10n.string("YHPhotos 对违规内容、骚扰、威胁与其他滥用行为实行零容忍，并会依据社区规范处置内容和账号。"))
            }

            Section(L10n.string("协议与规范")) {
                documentButton(.terms)
                documentButton(.eula)
                documentButton(.privacy)
                documentButton(.communityRules)
            }

            Section {
                Link(destination: URL(string: "mailto:support@yhphotos.top")!) {
                    Label("support@yhphotos.top", systemImage: "envelope.fill")
                }
                NavigationLink { SupportCenterView() } label: {
                    Label(L10n.string("帮助与反馈"), systemImage: "lifepreserver.fill")
                }
            } header: {
                Text(L10n.string("联系我们"))
            } footer: {
                Text(L10n.string("如遇到危险、威胁或其他紧急情况，请同时联系所在地的紧急服务机构。"))
            }
        }
        .navigationTitle(L10n.string("社区安全与内容规范"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDocument) { document in
            LegalDocumentView(document: document)
        }
    }

    private func safetyRow(_ title: String, _ description: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(title)).font(.headline)
                Text(L10n.string(description)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func documentButton(_ document: LegalDocument) -> some View {
        Button { selectedDocument = document } label: {
            Label(document.title, systemImage: document.systemImage)
                .foregroundStyle(.primary)
        }
    }
}

private struct LegalWebView: UIViewRepresentable {
    let url: URL
    let language: AppLanguage
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, errorMessage: $errorMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let languageCode = language.apiValue
        let htmlLanguage = language.httpLanguageTag
        let source = """
        try { window.localStorage.setItem('yh-lang', '\(languageCode)'); } catch (_) {}
        document.documentElement.setAttribute('lang', '\(htmlLanguage)');
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        var request = URLRequest(url: url)
        request.setValue(language.httpLanguageTag, forHTTPHeaderField: "Accept-Language")
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) { }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var isLoading: Bool
        @Binding private var errorMessage: String?

        init(isLoading: Binding<Bool>, errorMessage: Binding<String?>) {
            _isLoading = isLoading
            _errorMessage = errorMessage
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            errorMessage = nil
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            errorMessage = error.localizedDescription
            isLoading = false
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
