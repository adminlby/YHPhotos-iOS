import SwiftUI

struct AdminPriorityView: View {
    @State private var status = "open"
    @State private var response: AdminPriorityResponse?
    @State private var selected: AdminPriorityApplication?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section { Picker("状态", selection: $status) { Text("待处理").tag("open"); Text("已通过").tag("approved"); Text("已驳回").tag("rejected"); Text("全部").tag("all") }.pickerStyle(.segmented) }
            if let response {
                Section("共 \(response.total) 条") {
                    ForEach(response.items) { application in
                        Button { selected = application } label: {
                            HStack(alignment: .top, spacing: 12) {
                                AvatarView(urlString: application.applicant.avatar, name: application.applicant.displayName, size: 44)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(application.applicant.displayName).font(.subheadline.weight(.semibold)); Spacer(); PriorityStatusBadge(status: application.status) }
                                    Text("@\(application.applicant.username) · 申请 \(application.amount) 张").font(.caption).foregroundStyle(.secondary)
                                    Text("余额 \(application.balance) · 累计获得 \(application.totalGranted) · 使用 \(application.totalUsed)").font(.caption2).foregroundStyle(.secondary)
                                    if let reason = application.reason { Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                }
                            }.padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            else if let errorMessage { EmptyStateView("申请加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent) }.listRowBackground(Color.clear) }
            else if response?.items.isEmpty == true { EmptyStateView("没有匹配的申请", systemImage: "bolt.slash").listRowBackground(Color.clear) }
        }
        .navigationTitle("优先队列")
        .task(id: status) { await load() }
        .refreshable { await load() }
        .sheet(item: $selected, onDismiss: { Task { await load() } }) { application in NavigationStack { AdminPriorityDetail(application: application) } }
    }
    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { response = try await APIClient.shared.get("api/admin/priority/applications", query: [URLQueryItem(name: "status", value: status), URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: "0")]) }
        catch { errorMessage = error.localizedDescription }; isLoading = false
    }
}

private struct AdminPriorityDetail: View {
    @Environment(\.dismiss) private var dismiss
    let application: AdminPriorityApplication
    @State private var amount: String
    @State private var note = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var decision: String?

    init(application: AdminPriorityApplication) { self.application = application; _amount = State(initialValue: String(application.amount)) }
    var body: some View {
        Form {
            Section("申请人") {
                HStack { AvatarView(urlString: application.applicant.avatar, name: application.applicant.displayName, size: 52); VStack(alignment: .leading) { Text(application.applicant.displayName).font(.headline); Text("@\(application.applicant.username)").foregroundStyle(.secondary) } }
                LabeledContent("申请额度", value: "\(application.amount) 张")
                LabeledContent("当前余额", value: "\(application.balance) 张")
                LabeledContent("累计获得 / 使用", value: "\(application.totalGranted) / \(application.totalUsed)")
            }
            if let reason = application.reason { Section("申请理由") { Text(reason) } }
            if application.status == "pending" {
                Section("处理") {
                    TextField("批准张数", text: $amount).keyboardType(.numberPad)
                    TextField("处理说明（选填）", text: $note, axis: .vertical).lineLimit(3...6)
                    Button("通过并发放额度", systemImage: "checkmark.circle.fill") { decision = "approve" }.foregroundStyle(.green)
                    Button("驳回申请", systemImage: "xmark.circle.fill", role: .destructive) { decision = "reject" }
                }.disabled(busy)
            } else {
                Section("处理结果") {
                    PriorityStatusBadge(status: application.status)
                    if let granted = application.grantedAmount { LabeledContent("发放额度", value: "\(granted) 张") }
                    if let handler = application.handler { LabeledContent("处理人", value: handler) }
                    if let note = application.handlerNote { Text(note) }
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("额度申请 #\(application.id)").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        .confirmationDialog(decision == "approve" ? "确认通过并即时发放额度？" : "确认驳回申请？", isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }), titleVisibility: .visible) {
            Button(decision == "approve" ? "通过并发放" : "驳回", role: decision == "reject" ? .destructive : nil) { if let decision { Task { await resolve(decision) } } }
            Button("取消", role: .cancel) { decision = nil }
        }
    }
    @MainActor private func resolve(_ decision: String) async {
        guard decision == "reject" || (Int(amount) ?? 0) >= 1 else { errorMessage = "批准张数至少为 1"; return }
        busy = true; defer { busy = false }
        do {
            let body = AdminPriorityResolveBody(decision: decision, amount: decision == "approve" ? Int(amount) : nil, note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note)
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/priority/applications/\(application.id)/resolve", body: body); dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct PriorityStatusBadge: View {
    let status: String
    var body: some View { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule()) }
    private var label: String { switch status { case "pending": "待审批"; case "approved": "已通过"; case "rejected": "已驳回"; default: status } }
    private var color: Color { switch status { case "approved": .green; case "rejected": .red; default: .orange } }
}
private struct AdminPriorityApplication: Codable, Identifiable, Sendable {
    struct Applicant: Codable, Sendable { let id: Int; let displayName: String; let username: String; let avatar: String? }
    let id: Int; let amount: Int; let reason: String?; let status: String; let grantedAmount: Int?; let handlerNote: String?; let handler: String?; let createdAt: String?; let handledAt: String?
    let applicant: Applicant; let balance: Int; let totalGranted: Int; let totalUsed: Int
}
private struct AdminPriorityResponse: Codable, Sendable { let items: [AdminPriorityApplication]; let total: Int }
private struct AdminPriorityResolveBody: Encodable, Sendable { let decision: String; let amount: Int?; let note: String? }
