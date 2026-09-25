import SwiftUI

enum ReportTarget {
    case photo(Int)
    case user(Int)

    var endpoint: String {
        switch self { case let .photo(id): "api/photos/\(id)/report"; case let .user(id): "api/users/\(id)/report" }
    }
    var reasons: [String] {
        switch self {
        case .photo: ["盗图", "虚假信息", "违规内容", "垃圾广告", "其他"]
        case .user: ["骚扰辱骂", "垃圾广告", "冒充他人", "不当资料", "其他"]
        }
    }
}

struct ReportView: View {
    @Environment(\.dismiss) private var dismiss
    let target: ReportTarget
    @State private var reasonType = ""
    @State private var detail = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(L10n.string("举报原因")) {
                Picker(L10n.string("原因"), selection: $reasonType) {
                    Text(L10n.string("请选择")).tag("")
                    ForEach(target.reasons, id: \.self) { Text(L10n.string($0)).tag($0) }
                }
                TextField(L10n.string("补充说明（可选）"), text: $detail, axis: .vertical).lineLimit(3...8)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle(L10n.string("举报"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L10n.string("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.string("提交")) { Task { await submit() } }.disabled(reasonType.isEmpty || isSubmitting)
            }
        }
    }

    @MainActor private func submit() async {
        struct Body: Encodable, Sendable { let reason_type: String; let reason: String? }
        isSubmitting = true; defer { isSubmitting = false }
        do {
            let _: APIClient.EmptyResponse = try await APIClient.shared.send(
                target.endpoint,
                body: Body(reason_type: reasonType, reason: detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : detail)
            )
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
