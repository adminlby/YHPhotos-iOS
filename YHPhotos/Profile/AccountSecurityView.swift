import SwiftUI

struct AccountSecurityView: View {
    @Environment(\.openURL) private var openURL
    @State private var settings: PublicSettings?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let fallbackAccountURL = URL(string: "https://auth.yhphotos.top/account")!

    private var accountURL: URL {
        guard let value = settings?.ssoAccountURL,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" else {
            return fallbackAccountURL
        }
        return url
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                identityCard
                automaticBindingCard
                privacyCard
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .padding(.bottom, 24)
        }
        .navigationTitle("账号与安全")
        .navigationBarTitleDisplayMode(.inline)
        .appScreenBackground()
        .task { await loadSettings() }
    }

    private var identityCard: some View {
        GlassPanel(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(Color.primary.opacity(0.08), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple 登录").font(.title3.bold())
                        Text("由 Casdoor 统一身份中心安全管理")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider().overlay(AppTheme.divider)

                Button {
                    openURL(accountURL)
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                        }
                        Text("绑定或管理 Apple 登录")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 50)
                    .background(AppTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(18)
        }
    }

    private var automaticBindingCard: some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Label("自动绑定规则", systemImage: "link.badge.plus")
                    .font(.headline)
                ruleRow(
                    icon: "envelope.badge.fill",
                    title: L10n.string("已验证邮箱匹配"),
                    detail: L10n.string("首次使用 Apple 登录时，仅当邮箱已验证且本站账号尚未绑定统一身份，才会自动合并。")
                )
                ruleRow(
                    icon: "lock.shield.fill",
                    title: L10n.string("已有绑定不会被覆盖"),
                    detail: L10n.string("同邮箱的新身份不能替换已有绑定，需在账号中心明确操作。")
                )
            }
            .padding(18)
        }
    }

    private var privacyCard: some View {
        GlassPanel(cornerRadius: 22) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "eye.slash.fill")
                    .foregroundStyle(.purple)
                    .frame(width: 34, height: 34)
                    .background(Color.purple.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("使用“隐藏我的邮箱”？").font(.subheadline.bold())
                    Text("Apple 的中继邮箱可能与原账号邮箱不同，届时不会自动合并。请先登录原账号，再从上方账号中心手动绑定。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
    }

    private func ruleRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @MainActor
    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try await APIClient.shared.get("api/settings/public")
            errorMessage = nil
        } catch {
            errorMessage = L10n.string("暂时无法读取服务端配置，将打开默认账号中心。")
        }
    }
}
