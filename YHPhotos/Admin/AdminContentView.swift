import SwiftUI

struct AdminContentView: View {
    let identity: AdminIdentity
    @State private var tab: ContentTab

    init(identity: AdminIdentity) {
        self.identity = identity
        let first = ContentTab.allCases.first { $0.allowed(identity) } ?? .photos
        _tab = State(initialValue: first)
    }

    private var tabs: [ContentTab] { ContentTab.allCases.filter { $0.allowed(identity) } }

    var body: some View {
        VStack(spacing: 0) {
            if tabs.count > 1 {
                Picker("内容类型", selection: $tab) {
                    ForEach(tabs) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
            }
            switch tab {
            case .photos: AdminContentPhotosView(identity: identity)
            case .comments: AdminContentCommentsView()
            case .collections: AdminContentCollectionsView()
            case .tags: AdminContentTagsView()
            }
        }
        .navigationTitle("内容管理")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum ContentTab: String, CaseIterable, Identifiable {
    case photos, comments, collections, tags
    var id: String { rawValue }
    var title: String { switch self { case .photos: "图片"; case .comments: "评论"; case .collections: "合集"; case .tags: "标签" } }
    var symbol: String { switch self { case .photos: "photo.on.rectangle"; case .comments: "bubble.left.fill"; case .collections: "square.stack.fill"; case .tags: "tag.fill" } }
    func allowed(_ identity: AdminIdentity) -> Bool {
        switch self {
        case .photos: identity.can(anyOf: ["content.photo.edit", "content.photo.delete", "content.photo.feature"])
        case .comments: identity.can("content.comment.moderate")
        case .collections: identity.can("content.collection.manage")
        case .tags: identity.can("content.tag.manage")
        }
    }
}

private struct AdminContentPhotosView: View {
    let identity: AdminIdentity
    @State private var status = "all"
    @State private var domain = "all"
    @State private var searchText = ""
    @State private var submittedQuery = ""
    @State private var response: ContentPhotosResponse?
    @State private var editingID: Int?
    @State private var inspectingID: Int?
    @State private var deleting: ContentPhoto?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var canInspect: Bool { identity.can(anyOf: ["content.photo.edit", "content.photo.requery", "content.photo.delete"]) }

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $status) {
                    Text("全部").tag("all"); Text("已通过").tag("approved"); Text("待审").tag("pending"); Text("驳回").tag("rejected")
                }
                Picker("领域", selection: $domain) {
                    Text("全领域").tag("all"); Text("航空").tag("aviation"); Text("铁路").tag("railway"); Text("模拟飞行").tag("flight_sim")
                }
            }
            if let response {
                Section("共 \(response.total) 张") {
                    ForEach(response.items) { photo in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                RemoteImage(urlString: photo.thumb).frame(width: 96, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(photo.title.isEmpty ? "（无标题）" : photo.title).font(.subheadline.weight(.semibold)).lineLimit(1); Spacer(); Text("#\(photo.id)").font(.caption.monospaced()).foregroundStyle(.secondary) }
                                    Text("\(domainName(photo.domain)) · \(photo.uploader.displayName)").font(.caption).foregroundStyle(.secondary)
                                    HStack { ContentStatusBadge(status: photo.status); Text("\(photo.views) 浏览").font(.caption2).foregroundStyle(.secondary); if photo.featured { Label("精选", systemImage: "star.fill").font(.caption2).foregroundStyle(.orange) } }
                                }
                            }
                            HStack {
                                if canInspect { Button("检查", systemImage: "magnifyingglass") { inspectingID = photo.id } }
                                if identity.can("content.photo.edit") { Button("编辑", systemImage: "pencil") { editingID = photo.id } }
                                if identity.can("content.photo.delete") { Button("删除", systemImage: "trash", role: .destructive) { deleting = photo } }
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            ContentLoadingRows(isLoading: isLoading, errorMessage: errorMessage, empty: response?.items.isEmpty == true, emptyTitle: "没有匹配的图片") { await load() }
        }
        .searchable(text: $searchText, prompt: "ID、标题、注册号或上传者")
        .onSubmit(of: .search) { submittedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
        .onChange(of: searchText) { if $0.isEmpty { submittedQuery = "" } }
        .task(id: "\(status)|\(domain)|\(submittedQuery)") { await load() }
        .refreshable { await load() }
        .sheet(isPresented: Binding(get: { editingID != nil }, set: { if !$0 { editingID = nil } }), onDismiss: { Task { await load() } }) {
            if let editingID { AdminContentPhotoEditor(photoID: editingID) }
        }
        .fullScreenCover(isPresented: Binding(get: { inspectingID != nil }, set: { if !$0 { inspectingID = nil } })) {
            if let inspectingID { AdminPhotoInspectionLoaderView(endpoint: "api/admin/content/photos/\(inspectingID)/inspect") }
        }
        .confirmationDialog("确认永久删除“\(deleting?.title ?? "")”？此操作不可恢复。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("永久删除", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do {
            var query = [URLQueryItem(name: "status", value: status), URLQueryItem(name: "sort", value: "new"), URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: "0")]
            if domain != "all" { query.append(URLQueryItem(name: "domain", value: domain)) }
            if !submittedQuery.isEmpty { query.append(URLQueryItem(name: "q", value: submittedQuery)) }
            response = try await APIClient.shared.get("api/admin/content/photos", query: query)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func delete(_ id: Int) async {
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/photos/\(id)", method: "DELETE"); deleting = nil; await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminContentPhotoEditor: View {
    @Environment(\.dismiss) private var dismiss
    let photoID: Int
    @State private var detail: ContentPhotoDetail?
    @State private var title = ""
    @State private var description = ""
    @State private var registration = ""
    @State private var aircraftType = ""
    @State private var aircraftOperator = ""
    @State private var airportName = ""
    @State private var tags = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let detail {
                    Section {
                        RemoteImage(urlString: detail.thumb, contentMode: .fit).frame(maxWidth: .infinity).frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 12))
                        TextField("标题", text: $title)
                        TextField("描述", text: $description, axis: .vertical).lineLimit(3...6)
                    }
                    if detail.domain == "aviation" {
                        Section("航空资料") {
                            TextField("注册号", text: $registration).textInputAutocapitalization(.characters)
                            TextField("机型", text: $aircraftType)
                            TextField("航司", text: $aircraftOperator)
                            TextField("拍摄地点", text: $airportName)
                        }
                    }
                    Section("标签") { TextField("逗号分隔，清空即全部移除", text: $tags, axis: .vertical) }
                } else if errorMessage == nil { ProgressView().frame(maxWidth: .infinity) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("编辑图片 #\(photoID)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(detail == nil || busy) }
            }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        do {
            let value: ContentPhotoDetail = try await APIClient.shared.get("api/admin/content/photos/\(photoID)")
            detail = value; title = value.title; description = value.description ?? ""; registration = value.aircraftRegistration ?? ""; aircraftType = value.aircraftType ?? ""; aircraftOperator = value.operator ?? ""; airportName = value.airportName ?? ""; tags = value.tags
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func save() async {
        busy = true; defer { busy = false }
        do {
            let body = ContentPhotoEditBody(title: title, description: description, aircraft_registration: detail?.domain == "aviation" ? registration : nil, aircraft_type: detail?.domain == "aviation" ? aircraftType : nil, operator: detail?.domain == "aviation" ? aircraftOperator : nil, airport_code: nil, airport_name: detail?.domain == "aviation" ? airportName : nil, tags: tags)
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/photos/\(photoID)", method: "PUT", body: body)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminContentCommentsView: View {
    @State private var status = "all"
    @State private var searchText = ""
    @State private var response: ContentCommentsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section { Picker("状态", selection: $status) { Text("全部").tag("all"); Text("正常").tag("visible"); Text("隐藏").tag("hidden"); Text("待审").tag("pending"); Text("已删除").tag("deleted") } }
            if let response {
                Section("共 \(response.total) 条") {
                    ForEach(response.items) { comment in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(comment.content)
                            Text("\(comment.author.displayName) · \(comment.likes) 赞").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                ContentStatusBadge(status: comment.status)
                                Spacer()
                                if comment.status != "visible" { Button("恢复") { Task { await setStatus(comment.id, "visible") } } }
                                if comment.status != "hidden" { Button("隐藏") { Task { await setStatus(comment.id, "hidden") } } }
                                if comment.status != "deleted" { Button("删除", role: .destructive) { Task { await setStatus(comment.id, "deleted") } } }
                            }.font(.caption)
                        }.padding(.vertical, 3)
                    }
                }
            }
            ContentLoadingRows(isLoading: isLoading, errorMessage: errorMessage, empty: response?.items.isEmpty == true, emptyTitle: "没有评论") { await load() }
        }
        .searchable(text: $searchText, prompt: "评论内容或作者")
        .task(id: "\(status)|\(searchText)") { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do {
            var query = [URLQueryItem(name: "status", value: status), URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: "0")]
            if !searchText.isEmpty { query.append(URLQueryItem(name: "q", value: searchText)) }
            response = try await APIClient.shared.get("api/admin/content/comments", query: query)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
    @MainActor private func setStatus(_ id: Int, _ status: String) async {
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/comments/\(id)/status", body: ContentStatusBody(status: status)); await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminContentCollectionsView: View {
    @State private var visibility = "all"
    @State private var searchText = ""
    @State private var response: ContentCollectionsResponse?
    @State private var deleting: ContentCollection?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section { Picker("可见性", selection: $visibility) { Text("全部").tag("all"); Text("公开").tag("public"); Text("不公开列出").tag("unlisted"); Text("私密").tag("private") } }
            if let response {
                Section("共 \(response.total) 个") {
                    ForEach(response.items) { collection in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Label(collection.title, systemImage: "square.stack.fill").font(.subheadline.weight(.semibold)); Spacer(); Text("\(collection.photoCount) 张").font(.caption).foregroundStyle(.secondary) }
                            Text("所有者：\(collection.owner.displayName)").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Picker("可见性", selection: Binding(get: { collection.visibility }, set: { value in Task { await setVisibility(collection.id, value) } })) {
                                    Text("公开").tag("public"); Text("不公开列出").tag("unlisted"); Text("私密").tag("private")
                                }.labelsHidden()
                                Spacer(); Button("删除", role: .destructive) { deleting = collection }
                            }.font(.caption)
                        }.padding(.vertical, 3)
                    }
                }
            }
            ContentLoadingRows(isLoading: isLoading, errorMessage: errorMessage, empty: response?.items.isEmpty == true, emptyTitle: "没有合集") { await load() }
        }
        .searchable(text: $searchText, prompt: "合集名称或所有者")
        .task(id: "\(visibility)|\(searchText)") { await load() }
        .refreshable { await load() }
        .confirmationDialog("确认删除合集“\(deleting?.title ?? "")”？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除合集", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }; Button("取消", role: .cancel) { deleting = nil }
        }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do {
            var query = [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: "0")]
            if visibility != "all" { query.append(URLQueryItem(name: "visibility", value: visibility)) }; if !searchText.isEmpty { query.append(URLQueryItem(name: "q", value: searchText)) }
            response = try await APIClient.shared.get("api/admin/content/collections", query: query)
        } catch { errorMessage = error.localizedDescription }; isLoading = false
    }
    @MainActor private func setVisibility(_ id: Int, _ value: String) async {
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/collections/\(id)/visibility", body: VisibilityBody(visibility: value)); await load() }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func delete(_ id: Int) async {
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/collections/\(id)", method: "DELETE"); deleting = nil; await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminContentTagsView: View {
    @State private var sort = "usage"
    @State private var searchText = ""
    @State private var response: ContentTagsResponse?
    @State private var editing: ContentTag?
    @State private var mergeSource: ContentTag?
    @State private var deleting: ContentTag?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                Picker("排序", selection: $sort) { Text("按使用").tag("usage"); Text("最新").tag("new"); Text("按名称").tag("name") }
                if let mergeSource { Label("选择目标标签，将“\(mergeSource.name)”合并进去", systemImage: "arrow.triangle.merge").foregroundStyle(.orange); Button("取消合并") { self.mergeSource = nil } }
            }
            if let response {
                Section("共 \(response.total) 个") {
                    ForEach(response.items) { tag in
                        HStack {
                            Button { if let source = mergeSource, source.id != tag.id { Task { await merge(source.id, into: tag.id) } } } label: {
                                VStack(alignment: .leading) { Text(tag.name); Text("使用 \(tag.used) 次 · \(tag.type)").font(.caption).foregroundStyle(.secondary) }
                            }.buttonStyle(.plain)
                            Spacer()
                            Menu {
                                Button("重命名", systemImage: "pencil") { editing = tag }
                                Button("合并到…", systemImage: "arrow.triangle.merge") { mergeSource = tag }
                                Button("删除", systemImage: "trash", role: .destructive) { deleting = tag }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                }
            }
            ContentLoadingRows(isLoading: isLoading, errorMessage: errorMessage, empty: response?.items.isEmpty == true, emptyTitle: "没有标签") { await load() }
        }
        .searchable(text: $searchText, prompt: "搜索标签")
        .task(id: "\(sort)|\(searchText)") { await load() }
        .refreshable { await load() }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { tag in AdminTagRenameView(tag: tag) }
        .confirmationDialog("删除标签“\(deleting?.name ?? "")”？将解除与所有图片的关联。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除标签", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }; Button("取消", role: .cancel) { deleting = nil }
        }
    }
    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { var q = [URLQueryItem(name: "sort", value: sort), URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "offset", value: "0")]; if !searchText.isEmpty { q.append(URLQueryItem(name: "q", value: searchText)) }; response = try await APIClient.shared.get("api/admin/content/tags", query: q) }
        catch { errorMessage = error.localizedDescription }; isLoading = false
    }
    @MainActor private func merge(_ from: Int, into: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/tags/merge", body: TagMergeBody(from_id: from, into_id: into)); mergeSource = nil; await load() } catch { errorMessage = error.localizedDescription } }
    @MainActor private func delete(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/tags/\(id)", method: "DELETE"); deleting = nil; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminTagRenameView: View {
    @Environment(\.dismiss) private var dismiss
    let tag: ContentTag
    @State private var name: String
    @State private var errorMessage: String?
    init(tag: ContentTag) { self.tag = tag; _name = State(initialValue: tag.name) }
    var body: some View { NavigationStack { Form { TextField("标签名称", text: $name); if let errorMessage { Text(errorMessage).foregroundStyle(.red) } }.navigationTitle("重命名标签").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) } } } }
    @MainActor private func save() async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/tags/\(tag.id)", method: "PUT", body: TagNameBody(name: name)); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct ContentLoadingRows: View {
    let isLoading: Bool; let errorMessage: String?; let empty: Bool; let emptyTitle: String; let retry: @MainActor () async -> Void
    var body: some View { if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) } else if let errorMessage { EmptyStateView("加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await retry() } }.buttonStyle(.borderedProminent) }.listRowBackground(Color.clear) } else if empty { EmptyStateView(emptyTitle, systemImage: "tray").listRowBackground(Color.clear) } }
}

private struct ContentStatusBadge: View {
    let status: String
    var body: some View { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.12), in: Capsule()) }
    private var label: String { switch status { case "approved": "已通过"; case "pending": "待审"; case "rejected": "驳回"; case "appealing": "申诉"; case "visible": "正常"; case "hidden": "隐藏"; case "deleted": "已删除"; default: status } }
    private var color: Color { switch status { case "approved", "visible": .green; case "rejected", "deleted": .red; case "hidden", "pending": .orange; default: .blue } }
}

private struct ContentPhoto: Codable, Identifiable, Sendable { struct Uploader: Codable, Sendable { let id: Int; let displayName: String }; let id: Int; let title: String; let status: String; let domain: String; let views: Int; let featured: Bool; let featuredSort: Int; let thumb: String?; let uploader: Uploader; let createdAt: String? }
private struct ContentPhotosResponse: Codable, Sendable { let items: [ContentPhoto]; let total: Int }
private struct ContentPhotoDetail: Codable, Sendable { let id: Int; let title: String; let description: String?; let domain: String; let thumb: String?; let aircraftRegistration: String?; let aircraftType: String?; let `operator`: String?; let airportCode: String?; let airportName: String?; let tags: String }
private struct ContentPhotoEditBody: Encodable, Sendable { let title: String?; let description: String?; let aircraft_registration: String?; let aircraft_type: String?; let `operator`: String?; let airport_code: String?; let airport_name: String?; let tags: String? }
private struct ContentComment: Codable, Identifiable, Sendable { struct Person: Codable, Sendable { let id: Int?; let displayName: String }; struct Photo: Codable, Sendable { let id: Int?; let title: String?; let href: String? }; let id: Int; let content: String; let status: String; let likes: Int; let createdAt: String?; let author: Person; let photo: Photo }
private struct ContentCommentsResponse: Codable, Sendable { let items: [ContentComment]; let total: Int }
private struct ContentCollection: Codable, Identifiable, Sendable { struct Owner: Codable, Sendable { let id: Int; let displayName: String }; let id: Int; let title: String; let visibility: String; let photoCount: Int; let createdAt: String?; let owner: Owner }
private struct ContentCollectionsResponse: Codable, Sendable { let items: [ContentCollection]; let total: Int }
private struct ContentTag: Codable, Identifiable, Sendable { let id: Int; let name: String; let type: String; let used: Int }
private struct ContentTagsResponse: Codable, Sendable { let items: [ContentTag]; let total: Int }
private struct ContentStatusBody: Encodable, Sendable { let status: String }
private struct VisibilityBody: Encodable, Sendable { let visibility: String }
private struct TagMergeBody: Encodable, Sendable { let from_id: Int; let into_id: Int }
private struct TagNameBody: Encodable, Sendable { let name: String }
