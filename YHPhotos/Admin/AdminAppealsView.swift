import SwiftUI

struct AdminAppealsView: View {
    let identity: AdminIdentity

    @State private var status = "open"
    @State private var searchText = ""
    @State private var submittedQuery = ""
    @State private var response: AdminAppealsResponse?
    @State private var reasons: [AdminRejectionReason] = []
    @State private var selected: AdminAppeal?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $status) {
                    Text("待处理").tag("open")
                    Text("已通过").tag("approved")
                    Text("已驳回").tag("rejected")
                    Text("全部").tag("all")
                }
                .pickerStyle(.segmented)
            }

            if let response {
                Section("共 \(response.total) 条") {
                    ForEach(response.items) { appeal in
                        Button { selected = appeal } label: {
                            AdminAppealRow(appeal: appeal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let errorMessage {
                EmptyStateView("申诉加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else if response?.items.isEmpty == true {
                EmptyStateView("没有匹配的申诉", systemImage: "scale.3d")
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("申诉处理")
        .searchable(text: $searchText, prompt: "标题、申诉人、理由或 ID")
        .onSubmit(of: .search) {
            submittedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .onChange(of: searchText) { value in
            if value.isEmpty { submittedQuery = "" }
        }
        .task(id: status + "|" + submittedQuery) { await load() }
        .refreshable { await load() }
        .sheet(item: $selected, onDismiss: { Task { await load() } }) { appeal in
            NavigationStack {
                AdminAppealDetailView(appeal: appeal, reasons: reasons)
            }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            var query = [
                URLQueryItem(name: "status", value: status),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "offset", value: "0"),
            ]
            if !submittedQuery.isEmpty { query.append(URLQueryItem(name: "q", value: submittedQuery)) }
            let requestQuery = query
            async let appeals: AdminAppealsResponse = APIClient.shared.get("api/admin/appeals", query: requestQuery)
            async let presets: AdminRejectionReasonsResponse = APIClient.shared.get(
                "api/admin/review/rejection-reasons",
                query: [URLQueryItem(name: "scope", value: "appeal")]
            )
            response = try await appeals
            let presetResponse = try? await presets
            reasons = presetResponse?.items ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct AdminAppealRow: View {
    let appeal: AdminAppeal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(urlString: appeal.photo.thumb)
                .frame(width: 86, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(appeal.photo.title.isEmpty ? "（无标题）" : appeal.photo.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    AdminStatusBadge(status: appeal.status)
                }
                Text("\(domainName(appeal.photo.domain)) · \(appeal.appellant.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appeal.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let lock = appeal.lock, !lock.byMe {
                    Label("由 \(lock.byName ?? "他人") 处理中", systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct AdminAppealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let appeal: AdminAppeal
    let reasons: [AdminRejectionReason]

    @State private var reply = ""
    @State private var claimed = false
    @State private var resolved = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmDecision: String?

    private var isOpen: Bool { appeal.status == "pending" || appeal.status == "reviewing" }
    private var lockedByOther: Bool { appeal.lock != nil && appeal.lock?.byMe != true }

    var body: some View {
        Form {
            Section("作品") {
                RemoteImage(urlString: appeal.photo.thumb, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                LabeledContent("标题", value: appeal.photo.title)
                LabeledContent("领域", value: domainName(appeal.photo.domain))
                LabeledContent("申诉人", value: appeal.appellant.displayName)
                if let moderator = appeal.photo.moderator { LabeledContent("原审核员", value: moderator) }
                if let reason = appeal.photo.rejectionReason {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("原驳回理由").font(.caption).foregroundStyle(.secondary)
                        Text(reason)
                    }
                }
            }

            Section("申诉理由") { Text(appeal.reason) }

            if let handler = appeal.handler {
                Section("处理结果") {
                    LabeledContent("处理人", value: handler.displayName)
                    if let value = appeal.handlerReply { Text(value) }
                }
            }

            if isOpen {
                if lockedByOther {
                    Section {
                        Label("该申诉正由 \(appeal.lock?.byName ?? "他人") 处理", systemImage: "lock.fill")
                            .foregroundStyle(.red)
                    }
                } else if !claimed {
                    Section {
                        Button("处理此申诉", systemImage: "lock.fill") { Task { await claim() } }
                            .disabled(busy)
                    } footer: {
                        Text("服务端会加处理锁，避免多人重复处置。")
                    }
                } else {
                    Section("预设回复") {
                        ForEach(reasons) { reason in
                            Button {
                                toggle(reason)
                            } label: {
                                Label(reason.title, systemImage: replyContains(reason) ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                    Section("给申诉人的回复") {
                        TextEditor(text: $reply).frame(minHeight: 90)
                    }
                    Section {
                        Button("通过申诉", systemImage: "checkmark.circle.fill") { confirmDecision = "approve" }
                            .foregroundStyle(.green)
                        Button("驳回申诉", systemImage: "xmark.circle.fill", role: .destructive) { confirmDecision = "reject" }
                        Button("释放处理锁", systemImage: "lock.open.fill") { Task { await release() } }
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("申诉 #\(appeal.id)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
        }
        .confirmationDialog(
            confirmDecision == "approve" ? "确认通过申诉并重新发布图片？" : "确认驳回申诉？上传者将不能再次申诉。",
            isPresented: Binding(get: { confirmDecision != nil }, set: { if !$0 { confirmDecision = nil } }),
            titleVisibility: .visible
        ) {
            Button(confirmDecision == "approve" ? "通过申诉" : "驳回申诉", role: confirmDecision == "approve" ? nil : .destructive) {
                guard let decision = confirmDecision else { return }
                Task { await resolve(decision) }
            }
            Button("取消", role: .cancel) { confirmDecision = nil }
        }
        .task {
            if appeal.lock?.byMe == true { claimed = true }
        }
        .onDisappear {
            if claimed && !resolved { Task { await releaseSilently() } }
        }
    }

    @MainActor private func claim() async {
        busy = true
        defer { busy = false }
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/appeals/\(appeal.id)/claim", method: "POST")
            claimed = true
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func release() async {
        busy = true
        defer { busy = false }
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/appeals/\(appeal.id)/release", method: "POST")
            claimed = false
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func resolve(_ decision: String) async {
        busy = true
        defer { busy = false }
        do {
            let body = AdminAppealResolveBody(
                decision: decision,
                reply: reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reply
            )
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/appeals/\(appeal.id)/resolve", body: body)
            resolved = true
            claimed = false
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func releaseSilently() async {
        let _: AdminActionResponse? = try? await APIClient.shared.send("api/admin/appeals/\(appeal.id)/release", method: "POST")
    }

    private func replyContains(_ reason: AdminRejectionReason) -> Bool {
        let value = reason.content ?? reason.title
        return reply.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == value }
    }

    private func toggle(_ reason: AdminRejectionReason) {
        let value = reason.content ?? reason.title
        var lines = reply.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == value }) {
            lines.remove(at: index)
        } else {
            lines.append(value)
        }
        reply = lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

private struct AdminStatusBadge: View {
    let status: String
    var body: some View {
        Text(label).font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
    private var label: String {
        switch status { case "pending", "reviewing": "待处理"; case "approved": "已通过"; case "rejected": "已驳回"; default: status }
    }
    private var color: Color {
        switch status { case "approved": .green; case "rejected": .red; default: .orange }
    }
}

func domainName(_ domain: String) -> String {
    switch domain { case "aviation": "航空"; case "railway": "铁路"; case "flight_sim": "模拟飞行"; default: domain }
}
