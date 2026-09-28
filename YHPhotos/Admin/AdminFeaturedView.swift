import SwiftUI

struct AdminFeaturedView: View {
    @State private var current: [AdminFeaturedItem] = []
    @State private var past: [AdminPastFeaturedItem] = []
    @State private var idText = ""
    @State private var dirty = false
    @State private var isLoading = true
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var removing: AdminFeaturedItem?
    @State private var showingPicker = false

    var body: some View {
        List {
            Section {
                TextField("图片 ID，逗号或空格分隔", text: $idText)
                    .keyboardType(.numbersAndPunctuation)
                Button("按 ID 加入精选", systemImage: "plus.circle.fill") { Task { await add(parseIDs()) } }
                    .disabled(parseIDs().isEmpty || busy)
                Button("搜索并选择已通过图片", systemImage: "magnifyingglass") { showingPicker = true }
            } header: {
                Text("添加精选")
            } footer: {
                Text("只有已通过审核且尚未精选的图片可以加入。")
            }

            Section {
                ForEach(Array(current.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 11) {
                        VStack(spacing: 4) {
                            Button { move(index, -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                            Button { move(index, 1) } label: { Image(systemName: "chevron.down") }.disabled(index == current.count - 1)
                        }.buttonStyle(.borderless)
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                        RemoteImage(urlString: item.thumb).frame(width: 76, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title.isEmpty ? "（无标题）" : item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("#\(item.id) · \(domainName(item.domain)) · \(item.uploader)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text("\(item.views) 浏览").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { removing = item } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                    }.padding(.vertical, 3)
                }
                if current.isEmpty, !isLoading { Text("暂无当前精选").foregroundStyle(.secondary) }
                if dirty { Button("保存当前排序", systemImage: "square.and.arrow.down.fill") { Task { await saveOrder() } }.disabled(busy) }
            } header: {
                HStack { Text("当前精选（\(current.count)）"); if dirty { Spacer(); Text("顺序未保存").foregroundStyle(.orange) } }
            }

            Section("往期精选（\(past.count)）") {
                ForEach(past) { item in
                    HStack(spacing: 11) {
                        RemoteImage(urlString: item.thumb).frame(width: 76, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) { Text(item.title.isEmpty ? "（无标题）" : item.title).font(.subheadline.weight(.semibold)); Text("#\(item.id) · \(item.uploader)").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Button("移除", role: .destructive) { Task { await removePast(item.id) } }.font(.caption)
                    }.padding(.vertical, 3)
                }
                if past.isEmpty, !isLoading { Text("暂无往期精选").foregroundStyle(.secondary) }
            }

            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("精选管理")
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showingPicker, onDismiss: { Task { await load() } }) { AdminFeaturedPicker { ids in await add(ids) } }
        .confirmationDialog("取消精选“\(removing?.title ?? "")”", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("取消并加入往期精选") { if let id = removing?.id { Task { await remove(id, archive: true) } } }
            Button("直接移除，不归档", role: .destructive) { if let id = removing?.id { Task { await remove(id, archive: false) } } }
            Button("返回", role: .cancel) { removing = nil }
        } message: { Text("归档后仍会在首页往期精选区域展示。") }
    }

    private func parseIDs() -> [Int] { idText.split(whereSeparator: { $0 == "," || $0 == "，" || $0.isWhitespace }).compactMap { Int($0) } }
    private func move(_ index: Int, _ delta: Int) { let target = index + delta; guard current.indices.contains(target) else { return }; current.swapAt(index, target); dirty = true }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do {
            async let now: AdminFeaturedResponse = APIClient.shared.get("api/admin/content/featured")
            async let old: AdminPastFeaturedResponse = APIClient.shared.get("api/admin/content/past-featured", query: [URLQueryItem(name: "limit", value: "100")])
            current = try await now.items
            past = try await old.items
            dirty = false
        } catch { errorMessage = error.localizedDescription }; isLoading = false
    }
    @MainActor private func add(_ ids: [Int]) async {
        guard !ids.isEmpty else { return }; busy = true; defer { busy = false }
        do {
            let result: AdminFeaturedAddResponse = try await APIClient.shared.send("api/admin/content/featured", body: AdminFeaturedAddBody(photo_ids: ids))
            idText = ""
            if result.added.isEmpty, let first = result.skipped.first { errorMessage = "未能添加：#\(first.id) \(first.reason)" } else { errorMessage = result.skipped.isEmpty ? nil : "部分图片被跳过：\(result.skipped.map { "#\($0.id) \($0.reason)" }.joined(separator: "，"))" }
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func saveOrder() async {
        busy = true; defer { busy = false }
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/featured/order", method: "PUT", body: AdminFeaturedOrderBody(ids: current.map(\.id))); dirty = false; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func remove(_ id: Int, archive: Bool) async {
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/photos/\(id)/feature", body: AdminFeatureBody(featured: false, archive: archive, sort_order: nil)); removing = nil; await load() }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func removePast(_ id: Int) async {
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/content/past-featured/\(id)", method: "DELETE"); await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminFeaturedPicker: View {
    @Environment(\.dismiss) private var dismiss
    let add: @MainActor ([Int]) async -> Void
    @State private var query = ""
    @State private var items: [FeaturedCandidate] = []
    @State private var selected: Set<Int> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button { if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) } } label: {
                    HStack { RemoteImage(urlString: item.thumb).frame(width: 72, height: 54).clipShape(RoundedRectangle(cornerRadius: 8)); VStack(alignment: .leading) { Text(item.title.isEmpty ? "（无标题）" : item.title); Text("#\(item.id) · \(item.uploader.displayName)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(item.id) ? .blue : .secondary) }
                }.buttonStyle(.plain)
            }
            .overlay {
                if isLoading { ProgressView() }
                else if let errorMessage { EmptyStateView("加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) }
            }
            .searchable(text: $query, prompt: "标题、注册号或上传者")
            .task(id: query) { await load() }
            .navigationTitle("选择精选图片").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("添加（\(selected.count)）") { Task { await add(Array(selected)); dismiss() } }.disabled(selected.isEmpty) }
            }
        }
    }
    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { var q = [URLQueryItem(name: "status", value: "approved"), URLQueryItem(name: "featured", value: "0"), URLQueryItem(name: "sort", value: "new"), URLQueryItem(name: "limit", value: "100")]; if !query.isEmpty { q.append(URLQueryItem(name: "q", value: query)) }; let response: FeaturedCandidatesResponse = try await APIClient.shared.get("api/admin/content/photos", query: q); items = response.items }
        catch { errorMessage = error.localizedDescription }; isLoading = false
    }
}

private struct AdminFeaturedItem: Codable, Identifiable, Sendable { let id: Int; let title: String; let status: String; let domain: String; let views: Int; let sortOrder: Int; let thumb: String?; let uploader: String }
private struct AdminFeaturedResponse: Codable, Sendable { let items: [AdminFeaturedItem] }
private struct AdminPastFeaturedItem: Codable, Identifiable, Sendable { let id: Int; let title: String; let domain: String; let thumb: String?; let uploader: String; let archivedAt: String? }
private struct AdminPastFeaturedResponse: Codable, Sendable { let items: [AdminPastFeaturedItem]; let total: Int }
private struct FeaturedCandidate: Codable, Identifiable, Sendable { struct Uploader: Codable, Sendable { let id: Int; let displayName: String }; let id: Int; let title: String; let domain: String; let thumb: String?; let uploader: Uploader; let featured: Bool }
private struct FeaturedCandidatesResponse: Codable, Sendable { let items: [FeaturedCandidate] }
private struct AdminFeaturedAddBody: Encodable, Sendable { let photo_ids: [Int] }
private struct AdminFeaturedOrderBody: Encodable, Sendable { let ids: [Int] }
private struct AdminFeatureBody: Encodable, Sendable { let featured: Bool; let archive: Bool; let sort_order: Int? }
private struct AdminFeaturedAddResponse: Codable, Sendable { struct Skipped: Codable, Sendable { let id: Int; let reason: String }; let added: [Int]; let skipped: [Skipped] }
