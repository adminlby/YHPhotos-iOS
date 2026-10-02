import SwiftUI

struct AccountDeletionView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirming = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                warningCard
                deletionScopeCard

                Button(role: .destructive) {
                    isConfirming = true
                } label: {
                    HStack(spacing: 10) {
                        if isDeleting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "trash.fill")
                        }
                        Text(L10n.string(isDeleting ? "正在删除账号…" : "永久删除账号"))
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.red)
                .disabled(isDeleting)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .navigationTitle(L10n.string("删除账号"))
        .navigationBarTitleDisplayMode(.inline)
        .appScreenBackground()
        .interactiveDismissDisabled(isDeleting)
        .confirmationDialog(
            L10n.string("确认永久删除账号？"),
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button(L10n.string("永久删除账号"), role: .destructive) {
                Task { await deleteAccount() }
            }
            Button(L10n.string("取消"), role: .cancel) { }
        } message: {
            Text(L10n.string("删除后无法恢复。YHPhotos 会立即停用账号并退出所有设备，随后在后台永久清除账号和相关内容。SSO 账号不会被删除。"))
        }
    }

    private var warningCard: some View {
        GlassPanel(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.red)
                Text(L10n.string("此操作无法撤销"))
                    .font(.title3.bold())
                Text(L10n.string("提交后，账号会立即停用并退出所有设备。系统随后自动永久删除，无需前往 SSO 或再次操作。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    private var deletionScopeCard: some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 13) {
                Text(L10n.string("将被永久删除"))
                    .font(.headline)
                scopeRow("person.crop.circle", "YHPhotos 账号与个人资料")
                scopeRow("photo.on.rectangle.angled", "上传的照片及存储文件")
                scopeRow("text.bubble", "评论、消息、小组帖子和工单内容")

                Divider().overlay(AppTheme.divider)

                Label(L10n.string("Casdoor SSO 账号及其他产品不受影响"), systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }

    private func scopeRow(_ icon: String, _ title: String) -> some View {
        Label(L10n.string(title), systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.primary)
    }

    @MainActor
    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await appModel.deleteAccount()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
