import PhotosUI
import SwiftUI
import UIKit

struct AdminBadgesView: View {
    @State private var response: AdminBadgesResponse?
    @State private var offset = 0
    @State private var editor: BadgeEditorState?
    @State private var grant: BadgeGrantState?
    @State private var revoke: BadgeRevokeState?
    @State private var deleting: AdminBadge?
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let limit = 40

    var body: some View {
        List {
            Section { Button("新建徽章", systemImage: "plus.circle.fill") { editor = BadgeEditorState(badge: nil) } }
            if let response, !response.items.isEmpty {
                Section("共 \(response.total) 个徽章") {
                    ForEach(response.items) { badge in
                        HStack(spacing: 12) {
                            AdminBadgeIconView(filename: badge.icon)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(badge.name).font(.subheadline.weight(.semibold)); if !badge.active { Text("停用").font(.caption2).foregroundStyle(.secondary) } }
                                Text("\(badge.code) · \(badge.category ?? "未分类") · \(badge.holders) 人持有").font(.caption).foregroundStyle(.secondary)
                                if let description = badge.description, !description.isEmpty { Text(description).font(.caption2).foregroundStyle(.tertiary).lineLimit(2) }
                            }
                            Spacer(minLength: 0)
                            Menu {
                                Button("授予用户", systemImage: "person.badge.plus") { grant = BadgeGrantState(badge: badge) }
                                Button("从用户收回", systemImage: "person.badge.minus") { revoke = BadgeRevokeState(badge: badge) }
                                Button("编辑", systemImage: "pencil") { editor = BadgeEditorState(badge: badge) }
                                Button("删除徽章", systemImage: "trash", role: .destructive) { deleting = badge }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }.opacity(badge.active ? 1 : 0.6).padding(.vertical, 4)
                    }
                }
                if response.total > limit {
                    Section { HStack { Button("上一页", systemImage: "chevron.left") { offset = max(0, offset - limit) }.disabled(offset == 0); Spacer(); Text("\(offset / limit + 1) / \(max(1, Int(ceil(Double(response.total) / Double(limit)))))").foregroundStyle(.secondary); Spacer(); Button("下一页") { offset += limit }.disabled(offset + limit >= response.total); Image(systemName: "chevron.right") } }
                }
            } else if !isLoading && errorMessage == nil { EmptyStateView("还没有徽章", systemImage: "medal").listRowBackground(Color.clear) }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("徽章管理")
        .task(id: offset) { await load() }.refreshable { await load() }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { AdminBadgeEditor(state: $0) }
        .sheet(item: $grant, onDismiss: { Task { await load() } }) { AdminBadgeGrantView(state: $0) }
        .sheet(item: $revoke, onDismiss: { Task { await load() } }) { AdminBadgeRevokeView(state: $0) }
        .confirmationDialog("删除徽章“\(deleting?.name ?? "")”？所有用户已获得的该徽章也会被收回。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("永久删除", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }; Button("取消", role: .cancel) { deleting = nil }
        }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { response = try await APIClient.shared.get("api/admin/badges", query: [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]) } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func delete(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/badges/\(id)", method: "DELETE"); deleting = nil; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminBadgeEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: BadgeEditorState
    @State private var code: String; @State private var name: String; @State private var description: String; @State private var icon: String; @State private var category: String; @State private var sortOrder: String; @State private var active: Bool
    @State private var selectedImage: PhotosPickerItem?; @State private var previewURL: String?; @State private var uploading = false; @State private var busy = false; @State private var errorMessage: String?

    init(state: BadgeEditorState) { self.state = state; let badge = state.badge; _code = State(initialValue: badge?.code ?? ""); _name = State(initialValue: badge?.name ?? ""); _description = State(initialValue: badge?.description ?? ""); _icon = State(initialValue: badge?.icon ?? ""); _category = State(initialValue: badge?.category ?? "成就"); _sortOrder = State(initialValue: String(badge?.sortOrder ?? 0)); _active = State(initialValue: badge?.active ?? true) }
    var body: some View {
        NavigationStack {
            Form {
                Section("标识") { TextField("唯一 code", text: $code).textInputAutocapitalization(.never).disabled(state.badge != nil); TextField("名称", text: $name); TextField("描述", text: $description, axis: .vertical).lineLimit(2...6) }
                Section("展示") { Picker("分类", selection: $category) { Text("成就").tag("成就"); Text("等级").tag("等级"); Text("活动").tag("活动"); Text("荣誉").tag("荣誉") }; TextField("排序（越大越靠前）", text: $sortOrder).keyboardType(.numberPad); Toggle("启用", isOn: $active) }
                Section("徽章图标") {
                    if let previewURL { RemoteImage(urlString: previewURL).frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 14)) }
                    else if !icon.isEmpty { RemoteImage(urlString: "uploads/badges/\(icon)").frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 14)) }
                    else { AdminBadgeIconView(filename: nil) }
                    PhotosPicker(selection: $selectedImage, matching: .images) { Label(icon.isEmpty ? "选择图标" : "更换图标", systemImage: "photo.badge.plus") }.disabled(uploading)
                    if uploading { HStack { ProgressView(); Text("正在上传并处理…") } }
                    if !icon.isEmpty { Button("移除自定义图标", role: .destructive) { icon = ""; previewURL = nil } }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(state.badge == nil ? "新建徽章" : "编辑徽章").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || uploading || busy) } }
            .onChange(of: selectedImage) { item in if let item { Task { await upload(item) } } }
        }
    }
    @MainActor private func upload(_ item: PhotosPickerItem) async {
        uploading = true; errorMessage = nil; defer { uploading = false; selectedImage = nil }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self), let image = UIImage(data: raw), let data = image.jpegData(compressionQuality: 0.9), data.count <= 15 * 1024 * 1024 else { throw BadgeImageError.invalidOrLarge }
            let response: BadgeImageUploadResponse = try await APIClient.shared.upload("api/admin/ops/upload", imageData: data, filename: "badge-icon.jpg", mimeType: "image/jpeg", fields: ["kind": "badge"])
            icon = response.filename; previewURL = response.url
        } catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func save() async {
        busy = true; errorMessage = nil; defer { busy = false }
        do {
            let body = AdminBadgeBody(code: code, name: name, description: description, icon: icon, category: category, sort_order: Int(sortOrder) ?? 0, active: active)
            if let id = state.badge?.id { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/badges/\(id)", method: "PUT", body: body) }
            else { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/badges", body: body) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminBadgeGrantView: View {
    @Environment(\.dismiss) private var dismiss
    let state: BadgeGrantState
    @State private var query = ""
    @State private var suggestions: [AdminOpsUser] = []
    @State private var selectedUser: AdminOpsUser?
    @State private var note = ""
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("选择用户") {
                    TextField("用户名 / 昵称 / 邮箱 / ID", text: $query).textInputAutocapitalization(.never)
                    ForEach(suggestions) { user in
                        Button { selectedUser = user; query = user.displayName; suggestions = [] } label: { HStack { AvatarView(urlString: user.avatar, name: user.displayName, size: 32); VStack(alignment: .leading) { Text(user.displayName).foregroundStyle(.primary); Text("@\(user.username) · #\(user.id)").font(.caption).foregroundStyle(.secondary) }; Spacer(); if selectedUser?.id == user.id { Image(systemName: "checkmark.circle.fill") } } }
                    }
                    if let selectedUser { LabeledContent("将授予", value: "\(selectedUser.displayName) (#\(selectedUser.id))") }
                }
                Section("备注") { TextField("可选备注", text: $note, axis: .vertical).lineLimit(2...5) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("授予“\(state.badge.name)”").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("授予") { Task { await grant() } }.disabled(selectedUser == nil || busy) } }
            .task(id: query) { await lookup() }
        }
    }
    @MainActor private func lookup() async { guard query.trimmingCharacters(in: .whitespaces).count >= 1, selectedUser?.displayName != query else { suggestions = []; return }; do { try? await Task.sleep(nanoseconds: 250_000_000); let response: AdminOpsUsersResponse = try await APIClient.shared.get("api/admin/ops/user-lookup", query: [URLQueryItem(name: "q", value: query)]); guard !Task.isCancelled else { return }; suggestions = response.items } catch { suggestions = [] } }
    @MainActor private func grant() async { guard let selectedUser else { return }; busy = true; errorMessage = nil; defer { busy = false }; do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/badges/\(state.badge.id)/grant", body: BadgeGrantBody(user_id: selectedUser.id, note: note.isEmpty ? nil : note)); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminBadgeRevokeView: View {
    @Environment(\.dismiss) private var dismiss
    let state: BadgeRevokeState
    @State private var userID = ""
    @State private var busy = false
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("后端目前只按用户 ID 收回徽章。此操作不会删除用户账号。") }
                Section("用户") { TextField("用户 ID", text: $userID).keyboardType(.numberPad) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }.navigationTitle("收回“\(state.badge.name)”").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("收回", role: .destructive) { Task { await revoke() } }.disabled(Int(userID) == nil || busy) } }
        }
    }
    @MainActor private func revoke() async { guard let id = Int(userID) else { return }; busy = true; defer { busy = false }; do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/badges/\(state.badge.id)/holders/\(id)", method: "DELETE"); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminBadgeIconView: View {
    let filename: String?
    var body: some View { Group { if let filename, !filename.isEmpty { RemoteImage(urlString: "uploads/badges/\(filename)") } else { Image(systemName: "medal.fill").font(.title2).foregroundStyle(.orange) } }.frame(width: 48, height: 48).background(.orange.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 11)) }
}

private struct BadgeEditorState: Identifiable { let id = UUID(); let badge: AdminBadge? }
private struct BadgeGrantState: Identifiable { let id = UUID(); let badge: AdminBadge }
private struct BadgeRevokeState: Identifiable { let id = UUID(); let badge: AdminBadge }
private struct AdminBadgesResponse: Codable, Sendable { let items: [AdminBadge]; let total: Int }
private struct AdminBadge: Codable, Identifiable, Sendable { let id: Int; let code: String; let name: String; let description: String?; let icon: String?; let category: String?; let sortOrder: Int; let active: Bool; let holders: Int }
private struct AdminBadgeBody: Encodable, Sendable { let code: String; let name: String; let description: String; let icon: String; let category: String; let sort_order: Int; let active: Bool }
private struct BadgeGrantBody: Encodable, Sendable { let user_id: Int; let note: String? }
private struct AdminOpsUsersResponse: Codable, Sendable { let items: [AdminOpsUser] }
private struct AdminOpsUser: Codable, Identifiable, Sendable { let id: Int; let username: String; let displayName: String; let email: String?; let avatar: String?; let role: String }
private struct BadgeImageUploadResponse: Codable, Sendable { let filename: String; let url: String }
private enum BadgeImageError: LocalizedError { case invalidOrLarge; var errorDescription: String? { "请选择有效图片，处理后大小不能超过 15 MB" } }
