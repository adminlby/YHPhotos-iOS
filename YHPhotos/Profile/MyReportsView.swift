import SwiftUI

private struct MyReportsResponse: Decodable, Sendable {
    let photo: [MyReport]
    let user: [MyReport]
    let total: Int
}

private struct MyReport: Decodable, Identifiable, Sendable {
    let reportID: Int
    let targetType: String
    let targetID: Int
    let target: String?
    let reasonType: String?
    let reason: String?
    let status: String
    let resolution: String?
    let createdAt: String?
    let thumb: String?
    let domain: String?
    let avatar: String?

    var id: String { "\(targetType)-\(reportID)" }

    enum CodingKeys: String, CodingKey {
        case reportID = "id"
        case targetType
        case targetID = "targetId"
        case target, reasonType, reason, status, resolution, createdAt, thumb, domain, avatar
    }
}

struct MyReportsView: View {
    @State private var reports: [MyReport] = []
    @State private var isLoading = true
    @State private var withdrawingID: String?
    @State private var pendingWithdrawal: MyReport?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label(
                    L10n.string("每一项举报都会进入人工审核。处理结果和说明会显示在这里。"),
                    systemImage: "checkmark.shield.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            ForEach(reports) { report in
                ReportHistoryRow(
                    report: report,
                    isWithdrawing: withdrawingID == report.id,
                    onWithdraw: { pendingWithdrawal = report }
                )
            }

            if reports.isEmpty && !isLoading && errorMessage == nil {
                EmptyStateView(
                    L10n.string("你还没有提交过举报"),
                    systemImage: "flag",
                    description: L10n.string("在图片、评论、私信或用户主页的菜单中可以提交举报。")
                )
                .listRowBackground(Color.clear)
            }

            LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
                .listRowBackground(Color.clear)
        }
        .navigationTitle(L10n.string("我的举报"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            L10n.string("撤回这项举报？"),
            isPresented: Binding(
                get: { pendingWithdrawal != nil },
                set: { if !$0 { pendingWithdrawal = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("撤回举报"), role: .destructive) {
                if let report = pendingWithdrawal { Task { await withdraw(report) } }
            }
            Button(L10n.string("取消"), role: .cancel) { pendingWithdrawal = nil }
        } message: {
            Text(L10n.string("只有仍在待处理状态的举报可以撤回。"))
        }
    }

    private func reload() { Task { await load() } }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: MyReportsResponse = try await APIClient.shared.get("api/me/reports")
            reports = (response.photo + response.user).sorted {
                ($0.createdAt ?? "") > ($1.createdAt ?? "")
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func withdraw(_ report: MyReport) async {
        guard report.status == "pending", withdrawingID == nil else { return }
        withdrawingID = report.id
        defer {
            withdrawingID = nil
            pendingWithdrawal = nil
        }
        do {
            let _: APIClient.EmptyResponse = try await APIClient.shared.send(
                "api/me/reports/\(report.targetType)/\(report.reportID)",
                method: "DELETE"
            )
            reports.removeAll { $0.id == report.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReportHistoryRow: View {
    let report: MyReport
    let isWithdrawing: Bool
    let onWithdraw: () -> Void
    @State private var revealsThumbnail = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            media

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(targetTitle, systemImage: report.targetType == "photo" ? "photo" : "person")
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text(statusTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.12), in: Capsule())
                }

                if let reasonType = report.reasonType, !reasonType.isEmpty {
                    Text(L10n.string(reasonType))
                        .font(.caption.weight(.semibold))
                }
                if let reason = report.reason, !reason.isEmpty {
                    Text(reason).font(.subheadline).foregroundStyle(.secondary)
                }
                if let resolution = report.resolution, !resolution.isEmpty {
                    Label(L10n.format("处理说明：%@", resolution), systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                HStack {
                    if let createdAt = report.createdAt {
                        Text(String(createdAt.prefix(16)).replacingOccurrences(of: "T", with: " "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if report.status == "pending" {
                        Button(role: .destructive, action: onWithdraw) {
                            if isWithdrawing {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(L10n.string("撤回举报"))
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .disabled(isWithdrawing)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var media: some View {
        if report.targetType == "photo" {
            Button { revealsThumbnail.toggle() } label: {
                ZStack {
                    RemoteImage(urlString: report.thumb)
                        .frame(width: 54, height: 54)
                        .blur(radius: revealsThumbnail ? 0 : 7)
                    if !revealsThumbnail {
                        Image(systemName: "eye.slash.fill")
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string(revealsThumbnail ? "隐藏被举报图片" : "显示被举报图片"))
        } else {
            AvatarView(urlString: report.avatar, name: report.target ?? "?", size: 54)
                .blur(radius: 4)
                .accessibilityLabel(L10n.string("被举报用户"))
        }
    }

    private var targetTitle: String {
        if let target = report.target, !target.isEmpty { return target }
        return report.targetType == "photo"
            ? L10n.format("图片 #%d", report.targetID)
            : L10n.format("用户 #%d", report.targetID)
    }

    private var statusTitle: String {
        switch report.status {
        case "pending": L10n.string("待处理")
        case "reviewing": L10n.string("处理中")
        case "resolved": L10n.string("已处理")
        case "rejected": L10n.string("未采纳")
        default: report.status
        }
    }

    private var statusColor: Color {
        switch report.status {
        case "pending": .orange
        case "reviewing": AppTheme.accent
        case "resolved": .green
        case "rejected": .red
        default: .secondary
        }
    }
}
