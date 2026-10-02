import SwiftUI

enum ReportTarget: Identifiable {
    case photo(Int)
    case user(Int)

    var id: String {
        switch self {
        case let .photo(id): "photo-\(id)"
        case let .user(id): "user-\(id)"
        }
    }

    var title: String {
        switch self {
        case .photo: L10n.string("举报图片")
        case .user: L10n.string("举报用户")
        }
    }

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
    @State private var detail: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingSuccess = false

    init(target: ReportTarget, initialDetail: String = "") {
        self.target = target
        _detail = State(initialValue: initialDetail)
    }

    var body: some View {
        Form {
            Section(L10n.string("举报原因")) {
                Picker(L10n.string("原因"), selection: $reasonType) {
                    Text(L10n.string("请选择")).tag("")
                    ForEach(target.reasons, id: \.self) { Text(L10n.string($0)).tag($0) }
                }
                TextField(L10n.string("补充说明（可选）"), text: $detail, axis: .vertical).lineLimit(3...8)
            }
            Section {
                Label(
                    L10n.string("请勿恶意或重复举报。举报会进入人工审核，处理进度可在“设置 → 社区安全 → 我的举报”中查看。"),
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle(target.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L10n.string("取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.string("提交")) { Task { await submit() } }.disabled(reasonType.isEmpty || isSubmitting)
            }
        }
        .alert(L10n.string("举报已提交"), isPresented: $showingSuccess) {
            Button(L10n.string("完成")) { dismiss() }
        } message: {
            Text(L10n.string("我们会尽快审核并处理。你可以在“我的举报”中查看进度。"))
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
            showingSuccess = true
        } catch { errorMessage = error.localizedDescription }
    }
}
