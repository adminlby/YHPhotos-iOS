import QuickLook
import SwiftUI
import UniformTypeIdentifiers

enum SupportCopy {
    static func text(_ simplified: String, _ traditional: String, _ english: String) -> String {
        // Keep support screens on the same language selected for the app. The
        // Traditional Chinese copy remains available for a future zh-Hant app
        // localization instead of overriding an English per-app selection.
        switch AppLanguage.resolved {
        case .simplifiedChinese:
            return simplified
        case .english, .system:
            return english
        }
    }
}

private func supportText(_ simplified: String, _ traditional: String, _ english: String) -> String {
    SupportCopy.text(simplified, traditional, english)
}

struct SupportCenterView: View {
    private enum SectionKind: String, CaseIterable, Identifiable {
        case tickets
        case feedback

        var id: String { rawValue }
        var title: String {
            switch self {
            case .tickets: supportText("工单", "支援單", "Tickets")
            case .feedback: supportText("意见反馈", "意見回饋", "Feedback")
            }
        }
    }

    @State private var selection = SectionKind.tickets

    var body: some View {
        VStack(spacing: 0) {
            Picker(supportText("支持类型", "支援類型", "Support type"), selection: $selection) {
                ForEach(SectionKind.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            switch selection {
            case .tickets: SupportTicketListView()
            case .feedback: SupportFeedbackListView()
            }
        }
        .navigationTitle(supportText("帮助与反馈", "支援與意見回饋", "Help & Feedback"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SupportTicketSummary: Decodable, Identifiable, Sendable {
    let id: Int
    let ticketNo: String
    let category: String
    let categoryLabel: String
    let subject: String
    let status: String
    let priority: String
    let lastReplyAt: String?
    let createdAt: String?
}

private struct SupportTicketDetail: Decodable, Sendable {
    let id: Int
    let ticketNo: String
    let category: String
    let categoryLabel: String
    let subject: String
    let status: String
    let priority: String
    let createdAt: String?
    let isStaff: Bool
    let messages: [SupportTicketMessage]
}

private struct SupportTicketMessage: Decodable, Identifiable, Sendable {
    let id: Int
    let message: String
    let senderType: String
    let mine: Bool
    let senderName: String?
    let createdAt: String?
    let attachments: [SupportTicketAttachment]
}

private struct SupportTicketAttachment: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let ext: String
    let mime: String?
    let size: Int
    let url: String
}

private struct SupportTicketListView: View {
    @State private var tickets: [SupportTicketSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingComposer = false

    var body: some View {
        List {
            ForEach(tickets) { ticket in
                NavigationLink {
                    SupportTicketDetailView(ticketID: ticket.id)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text(ticket.subject).font(.headline).lineLimit(2)
                            Spacer(minLength: 8)
                            SupportStatusBadge(status: ticket.status)
                        }
                        Text("\(ticket.ticketNo) · \(supportCategory(ticket.category))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let date = ticket.lastReplyAt ?? ticket.createdAt {
                            Text(supportDate(date))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if tickets.isEmpty && !isLoading && errorMessage == nil {
                EmptyStateView(
                    supportText("暂无工单", "暫無支援單", "No tickets yet"),
                    systemImage: "lifepreserver",
                    description: supportText("遇到账号、版权或技术问题时，可以创建工单。", "遇到帳號、版權或技術問題時，可以建立支援單。", "Create a ticket for account, copyright, or technical issues.")
                ) {
                    Button(supportText("创建工单", "建立支援單", "Create Ticket")) { showingComposer = true }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }

            LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingComposer = true } label: {
                    Label(supportText("创建工单", "建立支援單", "Create Ticket"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            SupportNewTicketView {
                Task { await load() }
            }
        }
        .task { await load() }
    }

    private func reload() { Task { await load() } }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tickets = try await APIClient.shared.get("api/tickets")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SupportNewTicketView: View {
    private struct TicketPayload: Encodable, Sendable {
        let category: String
        let subject: String
        let message: String
    }

    private struct Result: Decodable, Sendable {
        let id: Int
        let ticketNo: String
    }

    private let categories = ["account", "copyright", "technical", "report", "other"]
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category = "technical"
    @State private var subject = ""
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(supportText("问题类型", "問題類型", "Category"), selection: $category) {
                        ForEach(categories, id: \.self) { value in
                            Text(supportCategory(value)).tag(value)
                        }
                    }
                    TextField(supportText("主题", "主旨", "Subject"), text: $subject, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section(supportText("详细说明", "詳細說明", "Details")) {
                    TextEditor(text: $message)
                        .frame(minHeight: 150)
                }

                Section {
                    Text(supportText("请勿填写密码、验证码或支付信息。创建后可在工单中补充附件。", "請勿填寫密碼、驗證碼或付款資訊。建立後可在支援單中補充附件。", "Never include passwords, verification codes, or payment information. You can add attachments after creating the ticket."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(supportText("创建工单", "建立支援單", "Create Ticket"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(supportText("取消", "取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(supportText("提交", "提交", "Submit")) { Task { await submit() } }
                        .disabled(isSubmitting || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .disabled(isSubmitting)
            .overlay { if isSubmitting { ProgressView() } }
            .alert(supportText("提交失败", "提交失敗", "Submission Failed"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(supportText("好", "好", "OK"), role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let _: Result = try await APIClient.shared.send(
                "api/tickets",
                body: TicketPayload(
                    category: category,
                    subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SupportTicketDetailView: View {
    private struct ReplyBody: Encodable, Sendable {
        let message: String
        let is_internal = false
    }

    private struct MutationResult: Decodable, Sendable {
        let ok: Bool
        let status: String?
    }

    let ticketID: Int

    @State private var detail: SupportTicketDetail?
    @State private var reply = ""
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showingFileImporter = false
    @State private var showingCloseConfirmation = false
    @State private var previewFile: SupportPreviewFile?

    var body: some View {
        List {
            if let detail {
                Section(supportText("工单信息", "支援單資訊", "Ticket")) {
                    LabeledContent(supportText("编号", "編號", "Number"), value: detail.ticketNo)
                    LabeledContent(supportText("类型", "類型", "Category"), value: supportCategory(detail.category))
                    HStack {
                        Text(supportText("状态", "狀態", "Status"))
                        Spacer()
                        SupportStatusBadge(status: detail.status)
                    }
                }

                Section(supportText("沟通记录", "溝通記錄", "Conversation")) {
                    ForEach(detail.messages) { message in
                        SupportMessageView(message: message, openAttachment: showAttachment)
                    }
                }

                if detail.status != "closed" {
                    Section {
                        TextField(supportText("补充问题详情", "補充問題詳情", "Add more details"), text: $reply, axis: .vertical)
                            .lineLimit(3...8)
                        HStack {
                            Button { showingFileImporter = true } label: {
                                Label(supportText("添加附件", "加入附件", "Add Attachment"), systemImage: "paperclip")
                            }
                            Spacer()
                            Button(supportText("发送", "傳送", "Send")) { Task { await sendReply() } }
                                .buttonStyle(.borderedProminent)
                                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                        }
                    } header: {
                        Text(supportText("回复", "回覆", "Reply"))
                    } footer: {
                        Text(attachmentFooter)
                    }
                } else {
                    Section {
                        Label(supportText("此工单已关闭", "此支援單已關閉", "This ticket is closed"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
                .listRowBackground(Color.clear)
        }
        .navigationTitle(detail?.subject ?? supportText("工单详情", "支援單詳情", "Ticket Details"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .toolbar {
            if let detail, detail.status != "closed" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(supportText("关闭", "關閉", "Close"), role: .destructive) {
                        showingCloseConfirmation = true
                    }
                    .disabled(isBusy)
                }
            }
        }
        .confirmationDialog(
            supportText("关闭这个工单？", "關閉此支援單？", "Close this ticket?"),
            isPresented: $showingCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button(supportText("关闭工单", "關閉支援單", "Close Ticket"), role: .destructive) {
                Task { await closeTicket() }
            }
        } message: {
            Text(supportText("关闭后将不能继续回复或上传附件。", "關閉後將無法繼續回覆或上傳附件。", "After closing, you can no longer reply or upload attachments."))
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { Task { await upload(url) } }
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $previewFile) { file in
            SupportQuickLookPreview(url: file.url)
        }
        .overlay { if isBusy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .task { await load() }
    }

    private func reload() { Task { await load() } }

    private func showAttachment(_ attachment: SupportTicketAttachment) {
        Task { await open(attachment) }
    }

    private var attachmentFooter: String {
        supportText(
            "附件支持图片、PDF、文本、压缩包和常用办公文档，最大 10 MB。",
            "附件支援圖片、PDF、文字、壓縮檔和常用辦公文件，最大 10 MB。",
            "Attachments may be images, PDFs, text, archives, or common office documents up to 10 MB."
        )
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await APIClient.shared.get("api/tickets/\(ticketID)")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func sendReply() async {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let _: MutationResult = try await APIClient.shared.send(
                "api/tickets/\(ticketID)/messages",
                body: ReplyBody(message: text)
            )
            reply = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func closeTicket() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let _: MutationResult = try await APIClient.shared.send("api/tickets/\(ticketID)/close", method: "POST")
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func upload(_ url: URL) async {
        isBusy = true
        defer { isBusy = false }

        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > 10 * 1024 * 1024 {
                throw SupportFileError.tooLarge
            }
            let data = try Data(contentsOf: url)
            guard data.count <= 10 * 1024 * 1024 else { throw SupportFileError.tooLarge }
            let filename = url.lastPathComponent
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = text.isEmpty ? [:] : ["message": text]
            let _: APIClient.EmptyResponse = try await APIClient.shared.uploadFile(
                "api/tickets/\(ticketID)/attachments",
                data: data,
                filename: filename,
                mimeType: mimeType,
                fields: fields
            )
            reply = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func open(_ attachment: SupportTicketAttachment) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await APIClient.shared.data(attachment.url)
            let safeName = URL(fileURLWithPath: attachment.name).lastPathComponent
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("YHPhotosSupport", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(attachment.id)-\(safeName)")
            try data.write(to: url, options: .atomic)
            previewFile = SupportPreviewFile(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SupportMessageView: View {
    let message: SupportTicketMessage
    let openAttachment: (SupportTicketAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    message.mine ? supportText("我", "我", "Me") : (message.senderName ?? supportText("客服", "客服", "Support")),
                    systemImage: message.mine ? "person.crop.circle.fill" : "person.crop.circle.badge.checkmark"
                )
                .font(.caption.weight(.semibold))
                Spacer()
                if let date = message.createdAt {
                    Text(supportDate(date)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Text(message.message)
                .font(.body)
                .textSelection(.enabled)

            ForEach(message.attachments) { attachment in
                Button { openAttachment(attachment) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.name).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "eye")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct SupportFeedbackItem: Decodable, Identifiable, Sendable {
    struct Reply: Decodable, Sendable {
        let content: String
        let responder: String?
        let createdAt: String?
    }

    let id: Int
    let type: String
    let subject: String?
    let content: String
    let status: String
    let createdAt: String?
    let replies: [Reply]
}

private struct SupportFeedbackListView: View {
    @State private var items: [SupportFeedbackItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingComposer = false

    var body: some View {
        List {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.subject?.isEmpty == false ? item.subject! : feedbackType(item.type))
                            .font(.headline)
                        Spacer(minLength: 8)
                        SupportStatusBadge(status: item.status)
                    }
                    Text(item.content).font(.subheadline).foregroundStyle(.secondary)
                    if let date = item.createdAt {
                        Text(supportDate(date)).font(.caption2).foregroundStyle(.tertiary)
                    }
                    ForEach(Array(item.replies.enumerated()), id: \.offset) { _, reply in
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Label(reply.responder ?? supportText("客服回复", "客服回覆", "Support reply"), systemImage: "bubble.left.and.bubble.right.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                            Text(reply.content).font(.subheadline)
                            if let date = reply.createdAt {
                                Text(supportDate(date)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.vertical, 5)
            }

            if items.isEmpty && !isLoading && errorMessage == nil {
                EmptyStateView(
                    supportText("暂无反馈", "暫無回饋", "No feedback yet"),
                    systemImage: "bubble.left.and.exclamationmark.bubble.right",
                    description: supportText("欢迎告诉我们你的建议或遇到的问题。", "歡迎告訴我們你的建議或遇到的問題。", "Tell us about an idea or something that is not working.")
                ) {
                    Button(supportText("提交反馈", "提交回饋", "Send Feedback")) { showingComposer = true }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }

            LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingComposer = true } label: {
                    Label(supportText("提交反馈", "提交回饋", "Send Feedback"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            SupportNewFeedbackView { Task { await load() } }
        }
        .task { await load() }
    }

    private func reload() { Task { await load() } }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await APIClient.shared.get("api/me/feedback")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SupportNewFeedbackView: View {
    private struct FeedbackPayload: Encodable, Sendable {
        let type: String
        let content: String
        let subject: String?
    }

    private struct Result: Decodable, Sendable {
        let id: Int
        let ok: Bool
    }

    private let types = ["bug", "suggestion", "complaint", "other"]
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var type = "suggestion"
    @State private var subject = ""
    @State private var content = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(supportText("反馈类型", "回饋類型", "Feedback Type"), selection: $type) {
                        ForEach(types, id: \.self) { Text(feedbackType($0)).tag($0) }
                    }
                    TextField(supportText("主题（可选）", "主旨（可選）", "Subject (Optional)"), text: $subject, axis: .vertical)
                }
                Section(supportText("反馈内容", "回饋內容", "Feedback")) {
                    TextEditor(text: $content).frame(minHeight: 170)
                }
                Section {
                    Text(supportText("反馈会关联你的账号，以便你在这里查看处理状态和回复。", "回饋會連結你的帳號，方便你在這裡查看處理狀態和回覆。", "Feedback is linked to your account so you can see its status and replies here."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(supportText("提交反馈", "提交回饋", "Send Feedback"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(supportText("取消", "取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(supportText("提交", "提交", "Submit")) { Task { await submit() } }
                        .disabled(isSubmitting || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .disabled(isSubmitting)
            .overlay { if isSubmitting { ProgressView() } }
            .alert(supportText("提交失败", "提交失敗", "Submission Failed"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(supportText("好", "好", "OK"), role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            let _: Result = try await APIClient.shared.send(
                "api/feedback",
                body: FeedbackPayload(
                    type: type,
                    content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                    subject: trimmedSubject.isEmpty ? nil : trimmedSubject
                )
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SupportStatusBadge: View {
    let status: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var title: String {
        switch status {
        case "open", "new": supportText("待处理", "待處理", "Open")
        case "pending": supportText("待客服回复", "待客服回覆", "Waiting for Support")
        case "in_progress", "read": supportText("处理中", "處理中", "In Progress")
        case "replied": supportText("已回复", "已回覆", "Replied")
        case "closed": supportText("已关闭", "已關閉", "Closed")
        default: status
        }
    }

    private var color: Color {
        switch status {
        case "closed": .secondary
        case "replied": .green
        case "in_progress", "read": AppTheme.accent
        case "pending": .orange
        default: .purple
        }
    }
}

private struct SupportPreviewFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SupportQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) { }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private enum SupportFileError: LocalizedError {
    case tooLarge

    var errorDescription: String? {
        supportText("文件超过 10 MB 上限", "檔案超過 10 MB 上限", "The file exceeds the 10 MB limit.")
    }
}

private func supportCategory(_ value: String) -> String {
    switch value {
    case "account": supportText("账号问题", "帳號問題", "Account")
    case "copyright": supportText("版权与授权", "版權與授權", "Copyright & Licensing")
    case "technical": supportText("技术故障", "技術問題", "Technical Issue")
    case "report": supportText("举报与投诉", "檢舉與投訴", "Report & Complaint")
    default: supportText("其他", "其他", "Other")
    }
}

private func feedbackType(_ value: String) -> String {
    switch value {
    case "bug": supportText("问题报告", "問題回報", "Bug Report")
    case "suggestion": supportText("功能建议", "功能建議", "Suggestion")
    case "complaint": supportText("投诉", "投訴", "Complaint")
    default: supportText("其他", "其他", "Other")
    }
}

private func supportDate(_ value: String) -> String {
    String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
}
