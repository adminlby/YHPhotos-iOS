import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 58))
                    .foregroundStyle(AppTheme.accent)
                VStack(spacing: 8) {
                    Text("登录 YHPhotos").font(.title2.bold())
                    Text("使用 YHPhotos 统一身份认证。账号与密码只在 SSO 安全页面中输入，App 不会读取。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                GlassPanel(cornerRadius: 22) {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView() }
                            else { Label("使用统一身份认证继续", systemImage: "safari.fill") }
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                    }
                    .disabled(isSubmitting)
                }
                Text("登录将在系统浏览器会话中打开，并安全回到此 App。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                SiteLegalFooter(compact: true)
            }
            .padding(28)
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await appModel.loginWithSSO()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
