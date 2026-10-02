import SwiftUI
import WebKit

enum LegalDocument: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: L10n.string("服务协议")
        case .privacy: L10n.string("隐私政策")
        }
    }

    var systemImage: String {
        switch self {
        case .terms: "doc.text.fill"
        case .privacy: "hand.raised.fill"
        }
    }

    var url: URL {
        switch self {
        case .terms:
            AppBuildInfo.siteOrigin.appending(path: "terms")
        case .privacy:
            AppBuildInfo.privacyPolicyURL
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
                                "继续使用 YHPhotos 前，请阅读并同意当前版本（%@）的服务协议与隐私政策。",
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
                            documentButton(.privacy)
                        }
                        .padding(.horizontal, 16)
                    }

                    Button {
                        hasConfirmed.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: hasConfirmed ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundStyle(hasConfirmed ? AppTheme.accent : .secondary)
                            Text(L10n.string("我已阅读并同意服务协议与隐私政策"))
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
