import QuickLook
import SwiftUI
import UIKit

// MARK: - Tickets

struct AdminTicketsView: View {
    let identity: AdminIdentity
    @State private var status = "open"
    @State private var assignee = "all"
    @State private var response: AdminTicketsResponse?
    @State private var selectedID: Int?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $status) { Text("未结").tag("open"); Text("待用户").tag("pending"); Text("处理中").tag("in_progress"); Text("已解决").tag("resolved"); Text("已关闭").tag("closed"); Text("全部").tag("all") }
                Picker("处理人", selection: $assignee) { Text("全部").tag("all"); Text("我的").tag("me"); Text("未认领").tag("unassigned") }
            }
            if let response {
                Section("共 \(response.total) 个") {
                    ForEach(response.items) { ticket in
                        Button { selectedID = ticket.id } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(ticket.subject).font(.subheadline.weight(.semibold)).lineLimit(2); Spacer(); TicketStatusBadge(status: ticket.status) }
                                Text("\(ticket.ticketNo) · \(ticket.user.displayName) · \(ticket.category)").font(.caption).foregroundStyle(.secondary)
                                HStack { TicketPriorityBadge(priority: ticket.priority); Text(ticket.assignee.map { "处理人：\($0)" } ?? "未认领").font(.caption2).foregroundStyle(.secondary) }
                            }.padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            SupportLoading(isLoading: isLoading, errorMessage: errorMessage, empty: response?.items.isEmpty == true, title: "没有匹配的工单") { await load() }
        }
        .navigationTitle("工单")
        .task(id: "\(status)|\(assignee)") { await load() }
        .refreshable { await load() }
        .sheet(isPresented: Binding(get: { selectedID != nil }, set: { if !$0 { selectedID = nil } }), onDismiss: { Task { await load() } }) {
            if let selectedID { AdminTicketDetailLoader(ticketID: selectedID, identity: identity) }
        }
    }
    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { var q = [URLQueryItem(name: "status", value: status), URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: "0")]; if assignee != "all" { q.append(URLQueryItem(name: "assignee", value: assignee)) }; response = try await APIClient.shared.get("api/admin/tickets", query: q) }
        catch { errorMessage = error.localizedDescription }; isLoading = false
    }
}

private struct AdminTicketDetailLoader: View {
    @Environment(\.dismiss) private var dismiss
    let ticketID: Int; let identity: AdminIdentity
    @State private var detail: AdminTicketDetail?
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Group { if let detail { AdminTicketDetailView(detail: detail, identity: identity) { await load() } } else if let errorMessage { EmptyStateView("工单加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await load() } } } } else { ProgressView("正在加载工单…") } }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }.task { await load() }
    }
    @MainActor private func load() async { do { detail = try await APIClient.shared.get("api/admin/tickets/\(ticketID)"); errorMessage = nil } catch { errorMessage = error.localizedDescription } }
}

private struct AdminTicketDetailView: View {
    let detail: AdminTicketDetail; let identity: AdminIdentity; let reload: @MainActor () async -> Void
    @State private var message = ""
    @State private var internalNote = false
    @State private var selectedStatus: String
    @State private var attachment: AdminTicketAttachment?
    @State private var busy = false
    @State private var errorMessage: String?
    init(detail: AdminTicketDetail, identity: AdminIdentity, reload: @escaping @MainActor () async -> Void) { self.detail = detail; self.identity = identity; self.reload = reload; _selectedStatus = State(initialValue: detail.status) }
    private var mine: Bool { detail.assignedTo == identity.id }
    var body: some View {
        Form {
            Section("工单信息") { LabeledContent("编号", value: detail.ticketNo); LabeledContent("主题", value: detail.subject); LabeledContent("用户", value: "\(detail.user.displayName) · \(detail.user.email)"); LabeledContent("分类", value: detail.category); HStack { TicketPriorityBadge(priority: detail.priority); TicketStatusBadge(status: detail.status) }; LabeledContent("处理人", value: detail.assignee ?? "未认领") }
            if let takeover = detail.takeoverRequest {
                Section("接管请求") {
                    Text(takeover.mine ? "你的接管请求正在等待原处理人审批；24 小时未响应会自动同意。" : "\(takeover.requester) 申请接管此工单。")
                    if mine && !takeover.mine { Button("同意接管") { Task { await takeoverDecision(takeover.id, "approve") } }; Button("拒绝接管", role: .destructive) { Task { await takeoverDecision(takeover.id, "reject") } } }
                }
            }
            Section("消息") {
                ForEach(detail.messages) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(item.sender ?? (item.senderType == "staff" ? "客服" : "用户")).font(.caption.weight(.semibold)); if item.isInternal { Text("内部备注").font(.caption2).foregroundStyle(.orange) }; Spacer(); Text(item.senderType == "staff" ? "客服" : "用户").font(.caption2).foregroundStyle(.secondary) }
                        Text(item.message)
                        ForEach(item.attachments) { file in Button { attachment = file } label: { Label("\(file.name) · \(ByteCountFormatter.string(fromByteCount: Int64(file.size ?? 0), countStyle: .file))", systemImage: "paperclip") }.font(.caption) }
                    }.padding(.vertical, 3)
                }
            }
            if detail.assignedTo == nil || !mine {
                Section { Button(detail.assignedTo == nil ? "认领工单" : "申请接管工单", systemImage: "person.crop.circle.badge.checkmark") { Task { await assign() } }.disabled(detail.takeoverRequest != nil || busy) }
            }
            if mine {
                Section("回复") { TextEditor(text: $message).frame(minHeight: 90); Toggle("仅内部可见", isOn: $internalNote); Button("发送回复", systemImage: "paperplane.fill") { Task { await reply() } }.disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                Section("工单状态") { Picker("状态", selection: $selectedStatus) { Text("开放").tag("open"); Text("等待用户").tag("pending"); Text("处理中").tag("in_progress"); Text("已解决").tag("resolved"); Text("已关闭").tag("closed") }; Button("更新状态") { Task { await setStatus() } }.disabled(selectedStatus == detail.status) }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("工单 \(detail.ticketNo)").navigationBarTitleDisplayMode(.inline).disabled(busy)
        .sheet(item: $attachment) { AdminTicketAttachmentView(ticketID: detail.id, attachment: $0) }
    }
    @MainActor private func action(_ block: () async throws -> Void) async { busy = true; defer { busy = false }; do { try await block(); errorMessage = nil; await reload() } catch { errorMessage = error.localizedDescription } }
    @MainActor private func assign() async { await action { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/tickets/\(detail.id)/assign", body: TicketAssignBody(assignee_id: nil)) } }
    @MainActor private func takeoverDecision(_ id: Int, _ decision: String) async { await action { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/tickets/\(detail.id)/takeover/\(id)/decision", body: TicketTakeoverBody(decision: decision)) } }
    @MainActor private func reply() async { let value = message; await action { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/tickets/\(detail.id)/reply", body: TicketReplyBody(message: value, is_internal: internalNote)) }; message = "" }
    @MainActor private func setStatus() async { await action { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/tickets/\(detail.id)/status", body: TicketStatusBody(status: selectedStatus)) } }
}

private struct AdminTicketAttachmentView: View {
    @Environment(\.dismiss) private var dismiss
    let ticketID: Int; let attachment: AdminTicketAttachment
    @State private var localURL: URL?
    @State private var image: UIImage?
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Group { if let image { ZoomableImageView(image: image).background(.black) } else if let localURL { QuickLookView(url: localURL) } else if let errorMessage { EmptyStateView("附件加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) } else { ProgressView("正在安全下载附件…") } }
                .navigationTitle(attachment.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }; if let localURL { ToolbarItem(placement: .primaryAction) { ShareLink(item: localURL) { Image(systemName: "square.and.arrow.up") } } } }
        }.task { await load() }
    }
    @MainActor private func load() async {
        do { let data = try await APIClient.shared.data(attachment.url); if let value = UIImage(data: data) { image = value } else { let safe = attachment.name.replacingOccurrences(of: "/", with: "-"); let url = FileManager.default.temporaryDirectory.appendingPathComponent("ticket-\(attachment.id)-\(safe)"); try data.write(to: url, options: .atomic); localURL = url } }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource { let url: URL; init(url: URL) { self.url = url }; func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }; func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL } }
}

// MARK: - Feedback

struct AdminFeedbackView: View {
    @State private var status = "all"; @State private var type = "all"; @State private var response: AdminFeedbackResponse?; @State private var selected: AdminFeedbackItem?; @State private var isLoading = true; @State private var errorMessage: String?
    var body: some View {
        List {
            Section { Picker("状态", selection: $status) { Text("全部").tag("all"); Text("新反馈").tag("new"); Text("已读").tag("read"); Text("已回复").tag("replied"); Text("已关闭").tag("closed") }; Picker("类型", selection: $type) { Text("全部类型").tag("all"); Text("问题").tag("bug"); Text("建议").tag("suggestion"); Text("投诉").tag("complaint"); Text("其他").tag("other") } }
            if let response { Section("共 \(response.total) 条") { ForEach(response.items) { item in Button { selected = item } label: { VStack(alignment: .leading, spacing: 5) { HStack { Text(item.displaySubject).font(.subheadline.weight(.semibold)); Spacer(); FeedbackStatusBadge(status: item.status) }; Text("\(feedbackType(item.type)) · \(item.user?.displayName ?? "匿名")").font(.caption).foregroundStyle(.secondary); Text(item.content).font(.caption).foregroundStyle(.secondary).lineLimit(2) }.padding(.vertical, 4).contentShape(Rectangle()) }.buttonStyle(.plain) } } }
            SupportLoading(isLoading: isLoading, errorMessage: errorMessage, empty: response?.items.isEmpty == true, title: "没有匹配的反馈") { await load() }
        }
        .navigationTitle("反馈")
        .task(id: "\(status)|\(type)") { await load() }
        .refreshable { await load() }
        .sheet(
            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
            onDismiss: { Task { await load() } }
        ) {
            if let selected { NavigationStack { AdminFeedbackDetail(item: selected) } }
        }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { var q = [URLQueryItem(name: "status", value: status), URLQueryItem(name: "limit", value: "100")]; if type != "all" { q.append(URLQueryItem(name: "type", value: type)) }; response = try await APIClient.shared.get("api/admin/feedback", query: q) } catch { errorMessage = error.localizedDescription }; isLoading = false }
}

private struct AdminFeedbackDetail: View {
    @Environment(\.dismiss) private var dismiss; let item: AdminFeedbackItem; @State private var reply = ""; @State private var busy = false; @State private var errorMessage: String?
    var body: some View { Form { Section("反馈") { LabeledContent("类型", value: feedbackType(item.type)); LabeledContent("状态", value: adminSystemLabel(item.status)); LabeledContent("提交人", value: item.user?.displayName ?? "匿名"); if let contact = item.contact { LabeledContent("联系方式", value: contact) }; Text(item.content) }; Section("回复") { TextEditor(text: $reply).frame(minHeight: 100); Button("发送回复", systemImage: "paperplane.fill") { Task { await sendReply() } }.disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); Button("标记已读") { Task { await noBody("read") } }; Button("关闭反馈", role: .destructive) { Task { await noBody("close") } } }; if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } } }.navigationTitle(item.displaySubject).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }.disabled(busy).task { if item.status == "new" { await noBody("read", dismissAfter: false) } } }
    @MainActor private func sendReply() async { busy = true; defer { busy = false }; do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/feedback/\(item.id)/reply", body: FeedbackReplyBody(reply: reply)); dismiss() } catch { errorMessage = error.localizedDescription } }
    @MainActor private func noBody(_ path: String, dismissAfter: Bool = true) async { busy = true; defer { busy = false }; do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/feedback/\(item.id)/\(path)", method: "POST"); if dismissAfter { dismiss() } } catch { errorMessage = error.localizedDescription } }
}

// MARK: - Corrections and license requests

struct AdminRequestsView: View {
    let identity: AdminIdentity
    @State private var tab: RequestTab
    init(identity: AdminIdentity) { self.identity = identity; _tab = State(initialValue: identity.can("correction.handle") ? .corrections : .licenses) }
    private var tabs: [RequestTab] { RequestTab.allCases.filter { $0 == .corrections ? identity.can("correction.handle") : identity.can("license.handle") } }
    var body: some View { VStack(spacing: 0) { if tabs.count > 1 { Picker("类型", selection: $tab) { ForEach(tabs) { Text($0.title).tag($0) } }.pickerStyle(.segmented).padding() }; if tab == .corrections { AdminCorrectionsView() } else { AdminLicenseRequestsView() } }.navigationTitle("纠错与授权").navigationBarTitleDisplayMode(.inline) }
}
private enum RequestTab: String, CaseIterable, Identifiable { case corrections, licenses; var id: String { rawValue }; var title: String { self == .corrections ? "信息纠错" : "授权申请" } }

private struct AdminCorrectionsView: View {
    @State private var status = "pending"; @State private var response: AdminCorrectionsResponse?; @State private var selected: AdminCorrection?; @State private var isLoading = true; @State private var errorMessage: String?
    var body: some View {
        List {
            Section { Picker("状态", selection: $status) { Text("待处理").tag("pending"); Text("已采纳").tag("accepted"); Text("已拒绝").tag("rejected"); Text("全部").tag("all") }.pickerStyle(.segmented) }
            if let response {
                Section("共 \(response.total) 条") {
                    ForEach(response.items) { item in
                        Button { selected = item } label: {
                            HStack(alignment: .top, spacing: 11) {
                                RemoteImage(urlString: item.photo.thumb).frame(width: 76, height: 57).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(item.photo.title ?? "#\(item.photo.id)").font(.subheadline.weight(.semibold)); Spacer(); FeedbackStatusBadge(status: item.status) }
                                    Text("\(item.fieldName)：\(item.currentValue ?? "—") → \(item.suggestedValue ?? "—")").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    Text("提交人：\(item.submitter ?? "匿名")").font(.caption2).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 3).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            SupportLoading(isLoading: isLoading, errorMessage: errorMessage, empty: response?.items.isEmpty == true, title: "没有纠错申请") { await load() }
        }
        .task(id: status) { await load() }
        .refreshable { await load() }
        .sheet(
            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
            onDismiss: { Task { await load() } }
        ) {
            if let selected { NavigationStack { AdminCorrectionDetail(item: selected) } }
        }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { response = try await APIClient.shared.get("api/admin/corrections", query: [URLQueryItem(name: "status", value: status), URLQueryItem(name: "limit", value: "100")]) } catch { errorMessage = error.localizedDescription }; isLoading = false }
}
private struct AdminCorrectionDetail: View {
    @Environment(\.dismiss) private var dismiss; let item: AdminCorrection; @State private var note = ""; @State private var errorMessage: String?; @State private var decision: String?
    var body: some View { Form { Section("图片") { RemoteImage(urlString: item.photo.thumb, contentMode: .fit).frame(maxWidth: .infinity).frame(height: 190); LabeledContent("标题", value: item.photo.title ?? "#\(item.photo.id)") }; Section("纠错内容") { LabeledContent("字段", value: item.fieldName); LabeledContent("当前值", value: item.currentValue ?? "—"); LabeledContent("建议值", value: item.suggestedValue ?? "—"); if let reason = item.reason { Text(reason) }; if !item.applicable { Label("该字段无法自动应用；采纳只会记录结果", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }; if item.status == "pending" { Section("处理") { TextField("拒绝说明（选填）", text: $note, axis: .vertical); Button("采纳并应用", systemImage: "checkmark.circle.fill") { decision = "accept" }.foregroundStyle(.green); Button("拒绝", role: .destructive) { decision = "reject" } } }; if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } } }.navigationTitle("纠错 #\(item.id)").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }.confirmationDialog(decision == "accept" ? "确认采纳并修改图片字段？" : "确认拒绝？", isPresented: Binding(get: { decision != nil }, set: { if !$0 { decision = nil } }), titleVisibility: .visible) { Button(decision == "accept" ? "采纳" : "拒绝", role: decision == "reject" ? .destructive : nil) { if let decision { Task { await resolve(decision) } } }; Button("取消", role: .cancel) { decision = nil } } }
    @MainActor private func resolve(_ value: String) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/corrections/\(item.id)/resolve", body: CorrectionBody(decision: value, note: note.isEmpty ? nil : note)); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminLicenseRequestsView: View {
    @State private var status = "pending"; @State private var response: AdminLicensesResponse?; @State private var isLoading = true; @State private var errorMessage: String?
    var body: some View { List { Section { Picker("状态", selection: $status) { Text("待处理").tag("pending"); Text("已批准").tag("approved"); Text("已拒绝").tag("rejected"); Text("已完成").tag("completed"); Text("全部").tag("all") } }; if let response { Section("共 \(response.total) 条") { ForEach(response.items) { item in VStack(alignment: .leading, spacing: 8) { HStack(alignment: .top, spacing: 11) { RemoteImage(urlString: item.photo.thumb).frame(width: 76, height: 57).clipShape(RoundedRectangle(cornerRadius: 8)); VStack(alignment: .leading, spacing: 4) { HStack { Text(item.photo.title ?? "#\(item.photo.id)").font(.subheadline.weight(.semibold)); Spacer(); FeedbackStatusBadge(status: item.status) }; Text("申请人：\(item.requester.name ?? "匿名") · 作者：\(item.photo.owner ?? "—")").font(.caption).foregroundStyle(.secondary); Text(item.intendedUse).font(.caption) } }; if let message = item.message { Text(message).font(.caption).foregroundStyle(.secondary) }; if let reply = item.reply { Label(reply, systemImage: "text.bubble.fill").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical, 4) } } }; SupportLoading(isLoading: isLoading, errorMessage: errorMessage, empty: response?.items.isEmpty == true, title: "没有授权申请") { await load() } }.task(id: status) { await load() }.refreshable { await load() } }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { response = try await APIClient.shared.get("api/admin/license-requests", query: [URLQueryItem(name: "status", value: status), URLQueryItem(name: "limit", value: "100")]) } catch { errorMessage = error.localizedDescription }; isLoading = false }
}

// MARK: - Shared support models

private struct SupportLoading: View { let isLoading: Bool; let errorMessage: String?; let empty: Bool; let title: String; let retry: @MainActor () async -> Void; var body: some View { if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) } else if let errorMessage { EmptyStateView("加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await retry() } } }.listRowBackground(Color.clear) } else if empty { EmptyStateView(title, systemImage: "tray").listRowBackground(Color.clear) } } }
private struct TicketStatusBadge: View { let status: String; var body: some View { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule()) }; private var label: String { switch status { case "open": "开放"; case "pending": "等待用户"; case "in_progress": "处理中"; case "resolved": "已解决"; case "closed": "已关闭"; default: status } }; private var color: Color { switch status { case "resolved": .green; case "closed": .secondary; case "in_progress": .blue; default: .orange } } }
private struct TicketPriorityBadge: View { let priority: String; var body: some View { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(priority == "urgent" ? .red : priority == "high" ? .orange : .secondary) }; private var label: String { switch priority { case "urgent": "紧急"; case "high": "高优先"; case "low": "低优先"; default: "普通" } } }
private struct FeedbackStatusBadge: View { let status: String; var body: some View { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.12), in: Capsule()) }; private var label: String { switch status { case "new": "新反馈"; case "read": "已读"; case "replied": "已回复"; case "closed": "已关闭"; case "pending": "待处理"; case "accepted": "已采纳"; case "approved": "已批准"; case "rejected": "已拒绝"; case "completed": "已完成"; default: status } }; private var color: Color { switch status { case "accepted", "approved", "completed", "replied": .green; case "rejected": .red; case "closed": .secondary; default: .orange } } }
private func feedbackType(_ type: String) -> String { switch type { case "bug": "问题"; case "suggestion": "建议"; case "complaint": "投诉"; default: "其他" } }

private struct AdminTicketRow: Codable, Identifiable, Sendable { struct User: Codable, Sendable { let id: Int; let displayName: String }; let id: Int; let ticketNo: String; let subject: String; let category: String; let status: String; let priority: String; let lastReplyAt: String?; let createdAt: String?; let user: User; let assignee: String? }
private struct AdminTicketsResponse: Codable, Sendable { let items: [AdminTicketRow]; let total: Int }
private struct AdminTicketAttachment: Codable, Identifiable, Sendable { let id: Int; let name: String; let mime: String?; let ext: String?; let size: Int?; let url: String }
private struct AdminTicketMessage: Codable, Identifiable, Sendable { let id: Int; let message: String; let senderType: String; let isInternal: Bool; let sender: String?; let createdAt: String?; let attachments: [AdminTicketAttachment] }
private struct AdminTakeoverRequest: Codable, Sendable { let id: Int; let requesterId: Int; let requester: String; let requestedAt: String?; let mine: Bool }
private struct AdminTicketDetail: Codable, Sendable { struct User: Codable, Sendable { let id: Int; let displayName: String; let email: String }; let id: Int; let ticketNo: String; let subject: String; let category: String; let status: String; let priority: String; let assignedTo: Int?; let assignee: String?; let createdAt: String?; let user: User; let messages: [AdminTicketMessage]; let takeoverRequest: AdminTakeoverRequest? }
private struct TicketAssignBody: Encodable, Sendable { let assignee_id: Int? }
private struct TicketTakeoverBody: Encodable, Sendable { let decision: String }
private struct TicketReplyBody: Encodable, Sendable { let message: String; let is_internal: Bool }
private struct TicketStatusBody: Encodable, Sendable { let status: String }
private struct AdminFeedbackItem: Codable, Identifiable, Sendable {
    struct User: Codable, Sendable { let id: Int; let displayName: String }
    let id: Int
    let type: String
    let subject: String?
    let content: String
    let contact: String?
    let status: String
    let createdAt: String?
    let user: User?

    var displaySubject: String {
        guard let subject = subject?.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty else {
            return "（无标题）"
        }
        return subject
    }
}
private struct AdminFeedbackResponse: Codable, Sendable { let items: [AdminFeedbackItem]; let total: Int }
private struct FeedbackReplyBody: Encodable, Sendable { let reply: String }
private struct AdminCorrection: Codable, Identifiable, Sendable { struct Photo: Codable, Sendable { let id: Int; let title: String?; let thumb: String?; let href: String? }; let id: Int; let fieldName: String; let currentValue: String?; let suggestedValue: String?; let reason: String?; let status: String; let createdAt: String?; let submitter: String?; let applicable: Bool; let photo: Photo }
private struct AdminCorrectionsResponse: Codable, Sendable { let items: [AdminCorrection]; let total: Int }
private struct CorrectionBody: Encodable, Sendable { let decision: String; let note: String? }
private struct AdminLicenseRequest: Codable, Identifiable, Sendable { struct Requester: Codable, Sendable { let id: Int?; let name: String?; let email: String? }; struct Photo: Codable, Sendable { let id: Int; let title: String?; let ownerId: Int?; let owner: String?; let thumb: String?; let href: String? }; let id: Int; let intendedUse: String; let message: String?; let status: String; let reply: String?; let createdAt: String?; let handledAt: String?; let requester: Requester; let photo: Photo }
private struct AdminLicensesResponse: Codable, Sendable { let items: [AdminLicenseRequest]; let total: Int }
