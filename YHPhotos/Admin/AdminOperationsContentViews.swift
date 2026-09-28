import QuickLook
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AdminRuleDocumentsView: View {
    @State private var documents: [AdminRuleDocument] = []
    @State private var importingKey: String?
    @State private var uploadingKey: String?
    @State private var preview: RuleDocumentPreview?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let definitions: [(key: String, title: String, description: String, symbol: String)] = [
        ("aviation", "航空上传规则", "在航空作品上传流程中展示的规则文档。", "airplane"),
        ("railway", "铁路上传规则", "在铁路作品上传流程中展示的规则文档。", "tram.fill"),
        ("site", "网站规则", "面向全站用户展示的网站规则文档。", "globe.asia.australia.fill")
    ]

    var body: some View {
        List {
            Section {
                Label("上传新 PDF 会立即替换当前版本；单个文件最大 20 MB。", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(definitions, id: \.key) { definition in
                let document = documents.first { $0.key == definition.key }
                Section {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: definition.symbol)
                            .font(.title2).foregroundStyle(AppTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(document?.title ?? definition.title).font(.headline)
                                Text(document?.available == true ? "已发布" : "未上传")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(document?.available == true ? .green : .secondary)
                            }
                            Text(definition.description).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let document, document.available {
                        LabeledContent("文件名", value: document.filename ?? "规则文档.pdf")
                        LabeledContent("文件大小", value: byteCount(document.size))
                        LabeledContent("更新时间", value: document.updatedAt?.replacingOccurrences(of: "T", with: " ").prefix(16).description ?? "—")
                        if document.url != nil {
                            Button("安全预览当前 PDF", systemImage: "doc.text.magnifyingglass") { Task { await open(document) } }
                        }
                    } else {
                        Text("尚未发布 PDF，前台对应位置将显示暂无文档。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(document?.available == true ? "选择替换文件" : "选择 PDF", systemImage: "arrow.up.doc.fill") {
                        importingKey = definition.key
                    }
                    .disabled(uploadingKey != nil)
                    if uploadingKey == definition.key { HStack { ProgressView(); Text("正在上传…") } }
                } header: { Text(definition.title) }
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("规则文档")
        .task { await load() }
        .refreshable { await load() }
        .fileImporter(
            isPresented: Binding(get: { importingKey != nil }, set: { if !$0 { importingKey = nil } }),
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            guard let key = importingKey else { return }
            importingKey = nil
            Task { await handleImport(result, key: key) }
        }
        .sheet(item: $preview) { RulePDFPreviewView(url: $0.url, title: $0.title) }
    }

    private func byteCount(_ count: Int?) -> String {
        guard let count else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { let response: AdminRuleDocumentsResponse = try await APIClient.shared.get("api/admin/rules/documents"); documents = response.items }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func handleImport(_ result: Result<[URL], Error>, key: String) async {
        do {
            guard let url = try result.get().first else { return }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
            if (values.fileSize ?? 0) > 20 * 1024 * 1024 {
                throw RuleDocumentError.tooLarge
            }
            let data = try Data(contentsOf: url)
            guard data.starts(with: Data("%PDF".utf8)) else { throw RuleDocumentError.notPDF }
            uploadingKey = key; defer { uploadingKey = nil }
            let _: AdminRuleUploadResponse = try await APIClient.shared.uploadFile(
                "api/admin/rules/documents/\(key)", method: "PUT", data: data,
                filename: values.name ?? "rules.pdf", mimeType: "application/pdf"
            )
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func open(_ document: AdminRuleDocument) async {
        guard let path = document.url else { return }
        do {
            let data = try await APIClient.shared.data(path)
            let safeName = (document.filename ?? "\(document.key)-rules.pdf").replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("rule-\(UUID().uuidString)-\(safeName)")
            try data.write(to: url, options: .atomic)
            preview = RuleDocumentPreview(url: url, title: document.title)
        } catch { errorMessage = error.localizedDescription }
    }
}

struct AdminAnnouncementsView: View {
    @State private var response: AdminAnnouncementsResponse?
    @State private var editor: AnnouncementEditorState?
    @State private var deleting: AdminAnnouncement?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button("发布公告", systemImage: "plus.circle.fill") { editor = AnnouncementEditorState(item: nil) }
            }
            if let response, !response.items.isEmpty {
                Section("共 \(response.total) 条公告") {
                    ForEach(response.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.typeLabel).font(.caption2.weight(.semibold)).foregroundStyle(item.typeColor)
                                if !item.visible { Image(systemName: "eye.slash").foregroundStyle(.secondary) }
                                Spacer()
                                Menu {
                                    Button("编辑", systemImage: "pencil") { editor = AnnouncementEditorState(item: item) }
                                    Button("删除", systemImage: "trash", role: .destructive) { deleting = item }
                                } label: { Image(systemName: "ellipsis.circle") }
                            }
                            if let content = item.content, !content.isEmpty { Text(content).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                            Text("\(item.author ?? "系统") · \(item.createdAt?.replacingOccurrences(of: "T", with: " ").prefix(16).description ?? "—")")
                                .font(.caption2).foregroundStyle(.tertiary)
                            if item.startAt != nil || item.endAt != nil {
                                Label("展示：\(item.startAt?.prefix(16).description ?? "立即") – \(item.endAt?.prefix(16).description ?? "长期")", systemImage: "calendar")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            } else if !isLoading && errorMessage == nil {
                EmptyStateView("还没有公告", systemImage: "megaphone")
                    .listRowBackground(Color.clear)
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("公告")
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { AdminAnnouncementEditor(state: $0) }
        .confirmationDialog("删除公告“\(deleting?.title ?? "")”？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { response = try await APIClient.shared.get("api/admin/announcements", query: [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: "0")]) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func delete(_ id: Int) async {
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/announcements/\(id)", method: "DELETE"); deleting = nil; await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct AdminNewsView: View {
    @State private var status = "all"
    @State private var query = ""
    @State private var response: AdminNewsResponse?
    @State private var editor: NewsEditorState?
    @State private var deleting: AdminNewsItem?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $status) {
                    Text("全部").tag("all"); Text("待审核").tag("pending"); Text("已发布").tag("published"); Text("草稿").tag("draft"); Text("驳回").tag("rejected"); Text("归档").tag("archived")
                }.pickerStyle(.menu)
                Button("新建资讯", systemImage: "plus.circle.fill") { editor = NewsEditorState(item: nil) }
            }
            if let response, !response.items.isEmpty {
                Section("共 \(response.total) 条资讯") {
                    ForEach(response.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 10) {
                                AdminNewsCover(url: item.cover)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                        Text(item.statusLabel).font(.caption2.weight(.semibold)).foregroundStyle(item.statusColor)
                                    }
                                    if let summary = item.summary, !summary.isEmpty { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    Text("\(item.source ?? "—") · \(item.views) 浏览 · 排序 \(item.sortOrder)").font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            HStack {
                                if item.status == "pending" {
                                    Button("通过发布") { Task { await setStatus(item.id, "published") } }.tint(.green)
                                    Button("驳回", role: .destructive) { Task { await setStatus(item.id, "rejected") } }
                                }
                                Spacer()
                                Button("编辑", systemImage: "pencil") { editor = NewsEditorState(item: item) }
                                Button("删除", systemImage: "trash", role: .destructive) { deleting = item }
                            }.font(.caption)
                        }.padding(.vertical, 4)
                    }
                }
            } else if !isLoading && errorMessage == nil {
                EmptyStateView("还没有资讯", systemImage: "newspaper").listRowBackground(Color.clear)
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("资讯")
        .searchable(text: $query, prompt: "搜索资讯标题")
        .task(id: "\(status)|\(query)") { await load() }
        .refreshable { await load() }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { AdminNewsEditor(state: $0) }
        .confirmationDialog("删除资讯“\(deleting?.title ?? "")”？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do {
            response = try await APIClient.shared.get("api/admin/news", query: [URLQueryItem(name: "status", value: status), URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: "0")])
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
    @MainActor private func setStatus(_ id: Int, _ status: String) async {
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/news/\(id)", method: "PUT", body: AdminNewsStatusBody(status: status)); await load() }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func delete(_ id: Int) async {
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/news/\(id)", method: "DELETE"); deleting = nil; await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminNewsEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: NewsEditorState
    @State private var title: String; @State private var summary: String; @State private var content = ""; @State private var source: String; @State private var url: String; @State private var status: String; @State private var sortOrder: String; @State private var coverFilename: String; @State private var coverURL: String?; @State private var photoID = ""; @State private var linkedPhoto: AdminNewsLinkedPhoto?; @State private var selectedCover: PhotosPickerItem?; @State private var loadingDetail: Bool; @State private var uploadingCover = false; @State private var busy = false; @State private var errorMessage: String?

    init(state: NewsEditorState) {
        self.state = state; let item = state.item
        _title = State(initialValue: item?.title ?? ""); _summary = State(initialValue: item?.summary ?? ""); _source = State(initialValue: item?.source ?? ""); _url = State(initialValue: item?.url ?? ""); _status = State(initialValue: item?.status ?? "draft"); _sortOrder = State(initialValue: item.map { String($0.sortOrder) } ?? ""); _coverFilename = State(initialValue: item?.coverFilename ?? ""); _coverURL = State(initialValue: item?.cover); _loadingDetail = State(initialValue: item != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("资讯内容") {
                    TextField("标题（支持 Markdown 行内语法）", text: $title)
                    TextField("摘要", text: $summary, axis: .vertical).lineLimit(2...5)
                    TextField("正文（支持 Markdown）", text: $content, axis: .vertical).lineLimit(8...18)
                    TextField("来源", text: $source)
                    TextField("原文链接", text: $url).textInputAutocapitalization(.never).keyboardType(.URL)
                }
                Section("发布") {
                    Picker("状态", selection: $status) { Text("草稿").tag("draft"); Text("待审核").tag("pending"); Text("已发布").tag("published"); Text("已驳回").tag("rejected"); Text("归档").tag("archived") }
                    TextField(state.item == nil ? "排序（留空自动置顶）" : "排序（越大越靠前）", text: $sortOrder).keyboardType(.numberPad)
                }
                Section("封面") {
                    if let coverURL { AdminNewsCover(url: coverURL, width: 180, height: 105) }
                    else if !coverFilename.isEmpty { Text("当前文件：\(coverFilename)").font(.caption).foregroundStyle(.secondary) }
                    PhotosPicker(selection: $selectedCover, matching: .images) { Label(coverFilename.isEmpty ? "选择封面图" : "更换封面图", systemImage: "photo.badge.plus") }.disabled(uploadingCover)
                    if uploadingCover { HStack { ProgressView(); Text("正在上传并处理封面…") } }
                    if !coverFilename.isEmpty { Button("移除封面", role: .destructive) { coverFilename = ""; coverURL = nil } }
                }
                Section("关联站内照片") {
                    TextField("图片 ID（留空表示不关联）", text: $photoID).keyboardType(.numberPad)
                    if let linkedPhoto { HStack { AdminNewsCover(url: linkedPhoto.thumb, width: 70, height: 48); Text(linkedPhoto.title ?? "图片 #\(photoID)").font(.caption) } }
                    Text("被资讯引用的作品作者将获得“新闻前线”徽章。").font(.caption).foregroundStyle(.secondary)
                }
                if loadingDetail { Section { HStack { ProgressView(); Text("正在加载完整正文…") } } }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(state.item == nil ? "新建资讯" : "编辑资讯").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy || loadingDetail || uploadingCover) } }
            .task { await loadDetail() }
            .onChange(of: selectedCover) { item in if let item { Task { await uploadCover(item) } } }
            .onChange(of: photoID) { _ in linkedPhoto = nil }
        }
    }

    @MainActor private func loadDetail() async {
        guard let id = state.item?.id else { return }; loadingDetail = true; defer { loadingDetail = false }
        do { let detail: AdminNewsDetail = try await APIClient.shared.get("api/admin/news/\(id)"); content = detail.content ?? ""; photoID = detail.photoId.map(String.init) ?? ""; if detail.photoId != nil { linkedPhoto = AdminNewsLinkedPhoto(title: detail.photoTitle, thumb: detail.photoThumb) } }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func uploadCover(_ item: PhotosPickerItem) async {
        uploadingCover = true; errorMessage = nil; defer { uploadingCover = false; selectedCover = nil }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: raw),
                  let data = image.jpegData(compressionQuality: 0.9),
                  data.count <= 15 * 1024 * 1024 else { throw AdminOpsImageError.tooLarge }
            let response: AdminOpsImageUploadResponse = try await APIClient.shared.upload("api/admin/ops/upload", imageData: data, filename: "news-cover.jpg", mimeType: "image/jpeg", fields: ["kind": "news"])
            coverFilename = response.filename; coverURL = response.url
        } catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func save() async {
        busy = true; errorMessage = nil; defer { busy = false }
        do {
            let body = AdminNewsBody(title: title, summary: summary, content: content, cover_filename: coverFilename, source: source, url: url, status: status, sort_order: Int(sortOrder), photo_id: Int(photoID))
            if let id = state.item?.id { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/news/\(id)", method: "PUT", body: body) } else { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/news", body: body) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminNewsCover: View {
    let url: String?; var width: CGFloat = 76; var height: CGFloat = 52
    var body: some View { AsyncImage(url: url.flatMap(URL.init(string:))) { phase in if case .success(let image) = phase { image.resizable().scaledToFill() } else { Image(systemName: "photo").foregroundStyle(.secondary) } }.frame(width: width, height: height).background(.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8)) }
}

private struct AdminAnnouncementEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: AnnouncementEditorState
    @State private var title: String
    @State private var content: String
    @State private var type: String
    @State private var pinned: Bool
    @State private var visible: Bool
    @State private var startAt: String
    @State private var endAt: String
    @State private var busy = false
    @State private var errorMessage: String?

    init(state: AnnouncementEditorState) {
        self.state = state
        let item = state.item
        _title = State(initialValue: item?.title ?? "")
        _content = State(initialValue: item?.content ?? "")
        _type = State(initialValue: item?.type ?? "info")
        _pinned = State(initialValue: item?.pinned ?? false)
        _visible = State(initialValue: item?.visible ?? true)
        _startAt = State(initialValue: item?.startAt?.prefix(16).description ?? "")
        _endAt = State(initialValue: item?.endAt?.prefix(16).description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("公告内容") {
                    TextField("标题（支持 Markdown 行内语法）", text: $title)
                    TextField("内容（支持 Markdown）", text: $content, axis: .vertical).lineLimit(6...12)
                    Picker("类型", selection: $type) {
                        Text("信息").tag("info"); Text("提醒").tag("warning"); Text("重要").tag("important"); Text("维护").tag("maintenance")
                    }
                }
                Section("展示") {
                    Toggle("置顶", isOn: $pinned)
                    Toggle("前台可见", isOn: $visible)
                    TextField("开始时间（YYYY-MM-DD HH:mm，可空）", text: $startAt)
                    TextField("结束时间（YYYY-MM-DD HH:mm，可空）", text: $endAt)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(state.item == nil ? "发布公告" : "编辑公告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy) }
            }
        }
    }

    @MainActor private func save() async {
        busy = true; defer { busy = false }; errorMessage = nil
        do {
            let body = AdminAnnouncementBody(
                title: title, content: content, type: type, pinned: pinned, visible: visible,
                start_at: startAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : startAt,
                end_at: endAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : endAt
            )
            if let id = state.item?.id { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/announcements/\(id)", method: "PUT", body: body) }
            else { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/announcements", body: body) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RulePDFPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let title: String
    var body: some View {
        NavigationStack {
            RuleQuickLookView(url: url).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

private struct RuleQuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

private struct AdminRuleDocumentsResponse: Codable, Sendable { let items: [AdminRuleDocument] }
private struct AdminRuleDocument: Codable, Identifiable, Sendable {
    let key: String; let title: String; let available: Bool; let url: String?; let filename: String?; let size: Int?; let updatedAt: String?
    var id: String { key }
}
private struct AdminRuleUploadResponse: Codable, Sendable { let ok: Bool; let item: AdminRuleDocument }
private struct RuleDocumentPreview: Identifiable { let id = UUID(); let url: URL; let title: String }
private enum RuleDocumentError: LocalizedError {
    case tooLarge, notPDF
    var errorDescription: String? { switch self { case .tooLarge: "PDF 文件不能超过 20 MB"; case .notPDF: "所选文件不是有效的 PDF" } }
}

private struct AdminAnnouncementsResponse: Codable, Sendable { let items: [AdminAnnouncement]; let total: Int }
private struct AdminAnnouncement: Codable, Identifiable, Sendable {
    let id: Int; let title: String; let content: String?; let type: String; let pinned: Bool; let visible: Bool; let startAt: String?; let endAt: String?; let createdAt: String?; let author: String?
    var typeLabel: String { switch type { case "info": "信息"; case "warning": "提醒"; case "important": "重要"; case "maintenance": "维护"; default: type } }
    var typeColor: Color { switch type { case "warning": .orange; case "important": .red; case "maintenance": .purple; default: AppTheme.accent } }
}
private struct AnnouncementEditorState: Identifiable { let id = UUID(); let item: AdminAnnouncement? }
private struct AdminAnnouncementBody: Encodable, Sendable { let title: String; let content: String; let type: String; let pinned: Bool; let visible: Bool; let start_at: String?; let end_at: String? }

private struct AdminNewsResponse: Codable, Sendable { let items: [AdminNewsItem]; let total: Int }
private struct AdminNewsItem: Codable, Identifiable, Sendable {
    let id: Int; let title: String; let summary: String?; let source: String?; let url: String?; let cover: String?; let coverFilename: String?; let status: String; let views: Int; let sortOrder: Int; let publishedAt: String?; let createdAt: String?; let author: String?
    var statusLabel: String { switch status { case "draft": "草稿"; case "pending": "待审核"; case "published": "已发布"; case "archived": "已归档"; case "rejected": "已驳回"; default: status } }
    var statusColor: Color { switch status { case "pending": .orange; case "published": .green; case "rejected": .red; default: .secondary } }
}
private struct NewsEditorState: Identifiable { let id = UUID(); let item: AdminNewsItem? }
private struct AdminNewsDetail: Codable, Sendable { let id: Int; let title: String; let summary: String?; let content: String?; let coverFilename: String?; let source: String?; let url: String?; let status: String; let sortOrder: Int; let photoId: Int?; let photoTitle: String?; let photoThumb: String? }
private struct AdminNewsLinkedPhoto { let title: String?; let thumb: String? }
private struct AdminNewsBody: Encodable, Sendable { let title: String; let summary: String; let content: String; let cover_filename: String; let source: String; let url: String; let status: String; let sort_order: Int?; let photo_id: Int? }
private struct AdminNewsStatusBody: Encodable, Sendable { let status: String }
private struct AdminOpsImageUploadResponse: Codable, Sendable { let filename: String; let url: String }
private enum AdminOpsImageError: LocalizedError { case tooLarge; var errorDescription: String? { "图片不能超过 15 MB" } }
