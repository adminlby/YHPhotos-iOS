import SwiftUI

struct AdminGroupsView: View {
    let identity: AdminIdentity

    @State private var mode: GroupAdminMode
    @State private var query = ""
    @State private var status = ""
    @State private var groups: AdminGroupsResponse?
    @State private var posts: AdminGroupPostsResponse?
    @State private var selectedGroup: AdminGroupRow?
    @State private var deletingPost: AdminGroupPost?
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(identity: AdminIdentity) {
        self.identity = identity
        _mode = State(initialValue: identity.can(anyOf: ["group.manage"]) ? .groups : .posts)
    }

    private var canManage: Bool { identity.can(anyOf: ["group.manage"]) }
    private var canModeratePosts: Bool { identity.can(anyOf: ["group.post.moderate"]) }

    var body: some View {
        List {
            Section {
                Picker("管理内容", selection: $mode) {
                    if canManage { Text("小组").tag(GroupAdminMode.groups) }
                    if canModeratePosts { Text("帖子审核").tag(GroupAdminMode.posts) }
                }
                .pickerStyle(.segmented)

                if mode == .groups, groups?.supportsBan == true {
                    Picker("状态", selection: $status) {
                        Text("全部").tag("")
                        Text("正常").tag("active")
                        Text("已封禁").tag("banned")
                    }
                    .pickerStyle(.segmented)
                }
            }

            if mode == .groups { groupContent } else { postContent }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let errorMessage {
                EmptyStateView("加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("小组管理")
        .searchable(text: $query, prompt: mode == .groups ? "搜索小组名或组长" : "搜索帖子、作者或小组")
        .task(id: "\(mode.rawValue)|\(status)|\(query)") { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedGroup, onDismiss: { Task { await load() } }) { row in
            AdminGroupDetailView(groupID: row.id, canModeratePosts: canModeratePosts)
        }
        .confirmationDialog(
            "移除这条帖子？作者会收到系统通知。",
            isPresented: Binding(get: { deletingPost != nil }, set: { if !$0 { deletingPost = nil } }),
            titleVisibility: .visible
        ) {
            Button("移除帖子", role: .destructive) {
                if let id = deletingPost?.id { Task { await deletePost(id) } }
            }
            Button("取消", role: .cancel) { deletingPost = nil }
        }
    }

    @ViewBuilder private var groupContent: some View {
        if groups?.supportsBan == false {
            Section {
                Label("当前服务端未应用 groups.status 迁移；封禁暂不可用，转移、解散和帖子审核不受影响。", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        if let response = groups, !response.items.isEmpty {
            Section("共 \(response.total) 个小组") {
                ForEach(response.items) { group in
                    Button { selectedGroup = group } label: {
                        HStack(spacing: 12) {
                            AdminRemoteThumbnail(url: group.logo, fallback: "person.3.fill", size: 48, cornerRadius: 12)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(group.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    if group.status == "banned" {
                                        Text("已封禁").font(.caption2.weight(.semibold)).foregroundStyle(.red)
                                    }
                                }
                                Text("组长 \(group.founder.displayName ?? "—")")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(group.members) 成员 · \(group.posts) 帖")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if !isLoading && errorMessage == nil {
            EmptyStateView("没有匹配的小组", systemImage: "person.3")
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder private var postContent: some View {
        if let response = posts, !response.items.isEmpty {
            Section("共 \(response.total) 条帖子") {
                ForEach(response.items) { post in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            if post.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                            Text(post.group?.name ?? "小组已删除").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                            Spacer()
                            Text(post.author.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(post.content).font(.subheadline).textSelection(.enabled)
                        HStack {
                            if let createdAt = post.createdAt { Text(createdAt.replacingOccurrences(of: "T", with: " ").prefix(16)) }
                            Spacer()
                            Button("移除", systemImage: "trash", role: .destructive) { deletingPost = post }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        } else if !isLoading && errorMessage == nil {
            EmptyStateView("没有匹配的帖子", systemImage: "text.bubble")
                .listRowBackground(Color.clear)
        }
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let common = [
                URLQueryItem(name: "q", value: query.trimmingCharacters(in: .whitespacesAndNewlines)),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "offset", value: "0")
            ]
            if mode == .groups {
                var params = common
                if !status.isEmpty { params.append(URLQueryItem(name: "status", value: status)) }
                groups = try await APIClient.shared.get("api/admin/groups", query: params)
            } else {
                posts = try await APIClient.shared.get("api/admin/groups/posts", query: common)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor private func deletePost(_ id: Int) async {
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/groups/posts/\(id)", method: "DELETE")
            deletingPost = nil
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct AdminGroupPolicyView: View {
    @State private var policy: AdminGroupCreatePolicy?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saved = false

    var body: some View {
        Form {
            if let binding = policyBinding {
                Section("开放状态") {
                    Toggle("开放用户创建小组", isOn: binding.enabled)
                    if !binding.wrappedValue.enabled {
                        Label("总开关关闭时，所有用户都无法创建小组。", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                Section("创建门槛") {
                    Toggle("需邮箱已验证", isOn: binding.requireEmailVerified)
                    Stepper("最低注册天数：\(binding.wrappedValue.minAccountAgeDays)", value: binding.minAccountAgeDays, in: 0...3650)
                    Stepper("最低已通过作品：\(binding.wrappedValue.minApprovedPhotos)", value: binding.minApprovedPhotos, in: 0...100_000)
                }
                .disabled(!binding.wrappedValue.enabled)
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack { Spacer(); if isSaving { ProgressView() } else { Text(saved ? "已保存" : "保存策略") }; Spacer() }
                    }
                    .disabled(isSaving)
                } footer: {
                    Text("数值为 0 表示不限制。不满足门槛的用户无法在前台创建小组。")
                }
            } else if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                EmptyStateView("策略加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }

            if let errorMessage, policy != nil {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("小组创建条件")
        .task { await load() }
        .refreshable { await load() }
    }

    private var policyBinding: Binding<AdminGroupCreatePolicy>? {
        guard policy != nil else { return nil }
        return Binding(get: { policy! }, set: { policy = $0; saved = false })
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { policy = try await APIClient.shared.get("api/admin/groups/create-policy") }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func save() async {
        guard let policy else { return }
        isSaving = true; errorMessage = nil; saved = false
        defer { isSaving = false }
        do {
            let body = AdminGroupCreatePolicyBody(
                enabled: policy.enabled,
                require_email_verified: policy.requireEmailVerified,
                min_account_age_days: max(0, policy.minAccountAgeDays),
                min_approved_photos: max(0, policy.minApprovedPhotos)
            )
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/groups/create-policy", method: "PUT", body: body)
            saved = true
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminGroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let groupID: Int
    let canModeratePosts: Bool

    @State private var detail: AdminGroupDetail?
    @State private var action: GroupActionSheet?
    @State private var deletingPost: AdminGroupPost?
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let detail {
                    Section {
                        HStack(spacing: 14) {
                            AdminRemoteThumbnail(url: detail.logo, fallback: "person.3.fill", size: 58, cornerRadius: 13)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(detail.name).font(.headline)
                                    if detail.status == "banned" { Text("已封禁").font(.caption2).foregroundStyle(.red) }
                                }
                                if let description = detail.description, !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary) }
                                Text("\(detail.memberCount) 成员 · \(detail.joinPolicy == "approval" ? "加入需审批" : "开放加入")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("管理操作") {
                        if detail.supportsBan {
                            Button(detail.status == "banned" ? "解封小组" : "封禁小组", systemImage: detail.status == "banned" ? "checkmark.circle.fill" : "nosign") {
                                if detail.status == "banned" { Task { await perform(path: "unban", body: EmptyAdminBody()) } }
                                else { action = .ban }
                            }
                            .foregroundStyle(detail.status == "banned" ? .green : .red)
                        }
                        Button("解散小组", systemImage: "trash", role: .destructive) { action = .dissolve }
                    }

                    Section("成员（\(detail.members.count)）") {
                        ForEach(detail.members) { member in
                            HStack(spacing: 10) {
                                AdminRemoteThumbnail(url: member.avatar, fallback: "person.fill", size: 34, cornerRadius: 17)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.displayName).font(.subheadline)
                                    Text("\(member.roleLabel) · \(member.statusLabel)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if member.role != "owner", member.status == "active" {
                                    Button { action = .transfer(member) } label: { Image(systemName: "arrow.left.arrow.right") }
                                        .accessibilityLabel("转让组长给\(member.displayName)")
                                }
                            }
                        }
                    }

                    Section("近期帖子（\(detail.posts.count)）") {
                        if detail.posts.isEmpty { Text("暂无帖子").foregroundStyle(.secondary) }
                        ForEach(detail.posts) { post in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    if post.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                                    Text(post.author.displayName).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    if canModeratePosts {
                                        Button(role: .destructive) { deletingPost = post } label: { Image(systemName: "trash") }
                                    }
                                }
                                Text(post.content).font(.subheadline).textSelection(.enabled)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } else if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                } else {
                    EmptyStateView("小组详情加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                        Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }.listRowBackground(Color.clear)
                }
                if let errorMessage, detail != nil { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("小组详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { if isBusy { ProgressView() } }
            }
            .task { await load() }
            .sheet(item: $action) { action in actionSheet(action) }
            .confirmationDialog("移除这条帖子？作者会收到系统通知。", isPresented: Binding(get: { deletingPost != nil }, set: { if !$0 { deletingPost = nil } }), titleVisibility: .visible) {
                Button("移除帖子", role: .destructive) { if let id = deletingPost?.id { Task { await deletePost(id) } } }
                Button("取消", role: .cancel) { deletingPost = nil }
            }
        }
    }

    @ViewBuilder private func actionSheet(_ action: GroupActionSheet) -> some View {
        switch action {
        case .ban:
            AdminGroupBanView(groupName: detail?.name ?? "") { reason in await ban(reason) }
        case .transfer(let member):
            AdminGroupConfirmActionView(
                title: "转移所有权",
                message: "将“\(detail?.name ?? "")”的组长转移给 \(member.displayName)？旧组长将降为管理员。",
                buttonTitle: "确认转移",
                role: nil
            ) { await transfer(to: member.id) }
        case .dissolve:
            AdminGroupConfirmActionView(
                title: "解散小组",
                message: "此操作将永久删除小组、成员关系及全部帖子，无法恢复。",
                buttonTitle: "永久解散",
                role: .destructive
            ) { await dissolve() }
        }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { detail = try await APIClient.shared.get("api/admin/groups/\(groupID)") }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func perform<Body: Encodable & Sendable>(path: String, body: Body) async {
        isBusy = true; errorMessage = nil; defer { isBusy = false }
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/groups/\(groupID)/\(path)", body: body)
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func ban(_ reason: String) async -> Bool {
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/groups/\(groupID)/ban", body: AdminGroupBanBody(reason: reason.isEmpty ? nil : reason))
            await load(); return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    @MainActor private func transfer(to userID: Int) async -> Bool {
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/groups/\(groupID)/transfer", body: AdminGroupTransferBody(user_id: userID))
            await load(); return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    @MainActor private func dissolve() async -> Bool {
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/groups/\(groupID)/dissolve", body: EmptyAdminBody())
            dismiss(); return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    @MainActor private func deletePost(_ id: Int) async {
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/groups/posts/\(id)", method: "DELETE")
            deletingPost = nil; await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminGroupBanView: View {
    @Environment(\.dismiss) private var dismiss
    let groupName: String
    let perform: (String) async -> Bool
    @State private var reason = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section { Text("封禁后将无法发帖或加入。组长会收到包含原因的系统通知。") }
                Section("原因") { TextField("违反规定", text: $reason, axis: .vertical).lineLimit(3...6) }
            }
            .navigationTitle("封禁“\(groupName)”").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("封禁", role: .destructive) { Task { busy = true; if await perform(reason) { dismiss() }; busy = false } }.disabled(busy)
                }
            }
        }
    }
}

private struct AdminGroupConfirmActionView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    let buttonTitle: String
    let role: ButtonRole?
    let perform: () async -> Bool
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(message) }
                Section {
                    Button(role: role) { Task { busy = true; if await perform() { dismiss() }; busy = false } } label: {
                        HStack { Spacer(); if busy { ProgressView() } else { Text(buttonTitle) }; Spacer() }
                    }.disabled(busy)
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

private struct AdminRemoteThumbnail: View {
    let url: String?
    let fallback: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            if case .success(let image) = phase { image.resizable().scaledToFill() }
            else { Image(systemName: fallback).font(.system(size: size * 0.38)).foregroundStyle(AppTheme.accent) }
        }
        .frame(width: size, height: size)
        .background(AppTheme.accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

private enum GroupAdminMode: String, Hashable { case groups, posts }
private enum GroupActionSheet: Identifiable {
    case ban, transfer(AdminGroupMember), dissolve
    var id: String {
        switch self { case .ban: "ban"; case .transfer(let member): "transfer-\(member.id)"; case .dissolve: "dissolve" }
    }
}

private struct AdminGroupsResponse: Codable, Sendable { let items: [AdminGroupRow]; let total: Int; let supportsBan: Bool }
private struct AdminGroupRow: Codable, Identifiable, Sendable {
    let id: Int; let name: String; let logo: String?; let status: String; let founder: AdminGroupFounder; let members: Int; let posts: Int; let createdAt: String?
}
private struct AdminGroupFounder: Codable, Sendable { let id: Int?; let displayName: String? }
private struct AdminGroupPostsResponse: Codable, Sendable { let items: [AdminGroupPost]; let total: Int }
private struct AdminGroupPost: Codable, Identifiable, Sendable {
    let id: Int; let content: String; let pinned: Bool; let createdAt: String?; let author: AdminGroupPostAuthor; let group: AdminGroupPostGroup?
}
private struct AdminGroupPostAuthor: Codable, Sendable { let id: Int?; let displayName: String }
private struct AdminGroupPostGroup: Codable, Sendable { let id: Int?; let name: String?; let href: String? }
private struct AdminGroupDetail: Codable, Sendable {
    let id: Int; let name: String; let description: String?; let logo: String?; let banner: String?; let status: String; let joinPolicy: String?; let founder: AdminGroupFounder; let createdAt: String?; let memberCount: Int; let members: [AdminGroupMember]; let posts: [AdminGroupPost]; let supportsBan: Bool
}
private struct AdminGroupMember: Codable, Identifiable, Sendable {
    let id: Int; let displayName: String; let avatar: String?; let role: String; let status: String; let joinedAt: String?
    var roleLabel: String { switch role { case "owner": "组长"; case "admin": "管理员"; case "member": "成员"; default: role } }
    var statusLabel: String { switch status { case "active": "正常"; case "pending": "待审批"; case "banned": "已移出"; default: status } }
}
private struct AdminGroupCreatePolicy: Codable, Sendable {
    var enabled: Bool; var requireEmailVerified: Bool; var minAccountAgeDays: Int; var minApprovedPhotos: Int
}
private struct AdminGroupCreatePolicyBody: Encodable, Sendable { let enabled: Bool; let require_email_verified: Bool; let min_account_age_days: Int; let min_approved_photos: Int }
private struct AdminGroupBanBody: Encodable, Sendable { let reason: String? }
private struct AdminGroupTransferBody: Encodable, Sendable { let user_id: Int }
private struct EmptyAdminBody: Encodable, Sendable {}
