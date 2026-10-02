import SwiftUI

struct AccountSecurityView: View {
    @State private var webAuthentication = SSOWebAuthentication()
    @State private var isOpening = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                identityCard
                commonOperationsCard
                sourceOfTruthCard
                accountDeletionLink
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .padding(.bottom, 24)
        }
        .navigationTitle("账号与安全")
        .navigationBarTitleDisplayMode(.inline)
        .appScreenBackground()
    }

    private var identityCard: some View {
        GlassPanel(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(Color.primary.opacity(0.08), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("SSO 登录与安全")).font(.title3.bold())
                        Text(L10n.string("登录凭据由统一身份中心管理"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider().overlay(AppTheme.divider)

                Button {
                    Task { await openAccountCenter() }
                } label: {
                    HStack {
                        if isOpening {
                            ProgressView()
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                        }
                        Text("打开 SSO 账号中心")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(isOpening)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(18)
        }
    }

    private var commonOperationsCard: some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Label("常用账号操作", systemImage: "key.horizontal.fill")
                    .font(.headline)
                operation("修改密码", "key.fill", "修改 SSO 密码或恢复凭据")
                operation("第三方账号", "link", "查看和管理 Apple 等登录方式")
                operation("双重验证", "lock.shield.fill", "管理验证器与恢复方式")
                operation("个人资料", "person.text.rectangle", "修改统一身份资料")
            }
            .padding(18)
        }
    }

    private var sourceOfTruthCard: some View {
        GlassPanel(cornerRadius: 22) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accent.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.string("SSO 管理登录凭据")).font(.subheadline.bold())
                    Text(L10n.string("密码、第三方登录和双重验证由 SSO 管理；删除 YHPhotos 账号可直接在 App 内完成。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
    }

    private var accountDeletionLink: some View {
        NavigationLink {
            AccountDeletionView()
        } label: {
            GlassPanel(cornerRadius: 22) {
                HStack(spacing: 13) {
                    Image(systemName: "person.crop.circle.badge.minus")
                        .foregroundStyle(.red)
                        .frame(width: 34, height: 34)
                        .background(Color.red.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("删除账号"))
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                        Text(L10n.string("在 App 内永久删除 YHPhotos 账号和相关数据"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(18)
            }
        }
        .buttonStyle(.plain)
    }

    private func operation(_ title: String, _ icon: String, _ detail: String) -> some View {
        Button { Task { await openAccountCenter() } } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string(title)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(L10n.string(detail)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
    }

    @MainActor
    private func openAccountCenter() async {
        guard !isOpening else { return }
        isOpening = true
        errorMessage = nil
        defer { isOpening = false }
        do {
            let preparation = try await APIClient.shared.prepareAccountManagement()
            let callbackURL = try await webAuthentication.authenticate(
                startURL: preparation.url,
                callbackScheme: preparation.callbackScheme
            )
            guard callbackURL.host == "account-callback" else {
                throw APIClientError.invalidResponse
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
               nsError.code == 1 {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}
