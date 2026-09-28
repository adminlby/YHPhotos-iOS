import PhotosUI
import SwiftUI

struct AdminUsersView: View {
    @State private var searchText = ""
    @State private var submittedQuery = ""
    @State private var role = "all"
    @State private var banFilter = "all"
    @State private var sort = "new"
    @State private var response: AdminUsersResponse?
    @State private var selectedUserID: Int?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker("用户组", selection: $role) {
                    Text("全部用户组").tag("all")
                    ForEach(response?.roleOptions ?? []) { Text($0.name).tag($0.key) }
                }
                Picker("账号状态", selection: $banFilter) {
                    Text("全部").tag("all")
                    Text("正常").tag("0")
                    Text("已封禁").tag("1")
                }
                Picker("排序", selection: $sort) {
                    Text("最新注册").tag("new")
                    Text("最近活跃").tag("active")
                    Text("作品最多").tag("photos")
                }
            }

            if let response {
                Section("共 \(response.total) 位用户") {
                    ForEach(response.items) { user in
                        Button { selectedUserID = user.id } label: { AdminUserRow(user: user) }
                            .buttonStyle(.plain)
                    }
                }
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
            } else if let errorMessage {
                EmptyStateView("用户加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else if response?.items.isEmpty == true {
                EmptyStateView("没有匹配的用户", systemImage: "person.slash").listRowBackground(Color.clear)
            }
        }
        .navigationTitle("用户")
        .searchable(text: $searchText, prompt: "用户名、名称或邮箱")
        .onSubmit(of: .search) { submittedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
        .onChange(of: searchText) { if $0.isEmpty { submittedQuery = "" } }
        .task(id: "\(submittedQuery)|\(role)|\(banFilter)|\(sort)") { await load() }
        .refreshable { await load() }
        .sheet(isPresented: Binding(get: { selectedUserID != nil }, set: { if !$0 { selectedUserID = nil } }), onDismiss: { Task { await load() } }) {
            if let selectedUserID { AdminUserDetailLoaderView(userID: selectedUserID) }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            var query = [
                URLQueryItem(name: "sort", value: sort),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "offset", value: "0"),
            ]
            if !submittedQuery.isEmpty { query.append(URLQueryItem(name: "q", value: submittedQuery)) }
            if role != "all" { query.append(URLQueryItem(name: "role", value: role)) }
            if banFilter != "all" { query.append(URLQueryItem(name: "banned", value: banFilter)) }
            response = try await APIClient.shared.get("api/admin/users", query: query)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct AdminUserDetailLoaderView: View {
    @Environment(\.dismiss) private var dismiss
    let userID: Int

    @State private var detail: AdminUserDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    AdminUserDetailView(detail: detail) { await load() }
                } else if isLoading {
                    ProgressView("正在加载用户…")
                } else {
                    EmptyStateView("用户加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                        Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        do { detail = try await APIClient.shared.get("api/admin/users/\(userID)") }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct AdminUserRow: View {
    let user: AdminUserRowModel
    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: user.avatar, name: user.displayName, size: 46, filename: user.avatar)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(user.displayName).font(.subheadline.weight(.semibold))
                    Text(user.roleLabel).font(.caption2).foregroundStyle(.blue)
                    if user.banned { Text("已封禁").font(.caption2).foregroundStyle(.red) }
                }
                Text("@\(user.username) · \(user.email)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("\(user.photoCount) 个作品").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4).contentShape(Rectangle())
    }
}

private struct AdminUserDetailView: View {
    let detail: AdminUserDetail
    let reload: @MainActor () async -> Void

    @State private var displayName: String
    @State private var email: String
    @State private var bio: String
    @State private var role: String
    @State private var restriction = "ban"
    @State private var restrictionDays = ""
    @State private var restrictionReason = ""
    @State private var warningPoints = "2"
    @State private var warningReason = ""
    @State private var grantAmount = ""
    @State private var removeAmount = ""
    @State private var quotaDay = ""
    @State private var quotaWeek = ""
    @State private var quotaMonth = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var selectedAvatar: PhotosPickerItem?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmation: UserConfirmation?
    @State private var showingPermissions = false

    init(detail: AdminUserDetail, reload: @escaping @MainActor () async -> Void) {
        self.detail = detail
        self.reload = reload
        _displayName = State(initialValue: detail.displayName)
        _email = State(initialValue: detail.email)
        _bio = State(initialValue: detail.bio ?? "")
        _role = State(initialValue: detail.role)
        _quotaDay = State(initialValue: detail.priorityOverride?.perDay.map(String.init) ?? "")
        _quotaWeek = State(initialValue: detail.priorityOverride?.perWeek.map(String.init) ?? "")
        _quotaMonth = State(initialValue: detail.priorityOverride?.perMonth.map(String.init) ?? "")
    }

    var body: some View {
        Form {
            summary
            if detail.canEdit { profileEditor; passwordEditor }
            if detail.canAssignRole { roleEditor }
            if detail.canBan { restrictions }
            if detail.canWarn { warningEditor }
            if detail.canQuota { priorityEditor }
            if detail.canReset2fa { twoFactorSection }
            if detail.canRevokeSessions { sessionSection; wechatSection }
            if detail.canManagePerms {
                Section { Button("编辑逐项个人权限", systemImage: "person.badge.key.fill") { showingPermissions = true } }
            }
            history
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("用户详情")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(busy)
        .sheet(isPresented: $showingPermissions) { AdminUserPermissionsView(userID: detail.id) }
        .onChange(of: selectedAvatar) { item in
            guard let item else { return }
            Task { await uploadAvatar(item) }
        }
        .confirmationDialog(confirmation?.title ?? "确认操作", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            Button(confirmation?.button ?? "确认", role: confirmation?.destructive == true ? .destructive : nil) {
                guard let confirmation else { return }
                Task { await performConfirmation(confirmation) }
            }
            Button("取消", role: .cancel) { confirmation = nil }
        }
    }

    private var summary: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(urlString: detail.avatarUrl, name: detail.displayName, size: 64, filename: detail.avatar)
                VStack(alignment: .leading, spacing: 3) {
                    Text(detail.displayName).font(.title3.weight(.semibold))
                    Text("@\(detail.username) · \(detail.email)").font(.caption).foregroundStyle(.secondary)
                    Text(detail.roleLabel).font(.caption.weight(.semibold)).foregroundStyle(.blue)
                }
            }
            if detail.banned { Label("已封禁：\(detail.banReason ?? "未填写理由")", systemImage: "person.crop.circle.badge.xmark").foregroundStyle(.red) }
            if detail.suspended { Label("账号已暂停", systemImage: "pause.circle.fill").foregroundStyle(.orange) }
            if detail.muted { Label("账号已禁言", systemImage: "speaker.slash.fill").foregroundStyle(.orange) }
            LabeledContent("作品 / 通过 / 驳回", value: "\(detail.stats.total) / \(detail.stats.approved) / \(detail.stats.rejected)")
            LabeledContent("违规分", value: String(detail.warningPoints))
        }
    }

    private var profileEditor: some View {
        Section("账号资料") {
            PhotosPicker(selection: $selectedAvatar, matching: .images) { Label("更换头像", systemImage: "camera.fill") }
            TextField("显示名称", text: $displayName)
            TextField("邮箱", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
            TextField("个人简介", text: $bio, axis: .vertical).lineLimit(3...6)
            Button("保存账号资料", systemImage: "square.and.arrow.down.fill") { Task { await saveProfile() } }
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || !email.contains("@"))
        }
    }

    private var passwordEditor: some View {
        Section("重置密码") {
            SecureField("新密码（至少 8 位）", text: $newPassword)
            SecureField("再次输入新密码", text: $confirmPassword)
            Button("重置密码并下线全部设备", systemImage: "key.fill", role: .destructive) {
                confirmation = .resetPassword
            }
            .disabled(newPassword.count < 8 || newPassword != confirmPassword)
        }
    }

    private var roleEditor: some View {
        Section("所属用户组") {
            Picker("用户组", selection: $role) {
                ForEach(detail.roleOptions) { Text($0.name).tag($0.key) }
            }
            Button("保存用户组") { Task { await send("role", body: RoleBody(role: role)) } }
                .disabled(role == detail.role)
        }
    }

    private var restrictions: some View {
        Section("账号限制") {
            if detail.banned { Button("解除封禁") { confirmation = .simple("unban", "确认解除封禁？") } }
            if detail.suspended { Button("解除暂停") { confirmation = .simple("unsuspend", "确认解除暂停？") } }
            if detail.muted { Button("解除禁言") { confirmation = .simple("unmute", "确认解除禁言？") } }
            Picker("处置", selection: $restriction) {
                Text("封禁（禁止登录）").tag("ban")
                Text("暂停（不能互动/上传）").tag("suspend")
                Text("禁言（不能互动）").tag("mute")
            }
            TextField("天数，留空为永久", text: $restrictionDays).keyboardType(.numberPad)
            TextField("理由（会通知用户）", text: $restrictionReason, axis: .vertical)
            Button("执行账号限制", role: .destructive) { confirmation = .restriction }
        }
    }

    private var warningEditor: some View {
        Section("违规警告 / 扣分") {
            TextField("扣分", text: $warningPoints).keyboardType(.numberPad)
            TextField("警告理由（必填）", text: $warningReason, axis: .vertical)
            Button("发出警告", systemImage: "exclamationmark.triangle.fill") { Task { await warn() } }
                .disabled(warningReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder private var priorityEditor: some View {
        Section("优先队列额度") {
            LabeledContent("当前余额", value: String(detail.priorityQuota.balance))
            LabeledContent("累计获得 / 使用", value: "\(detail.priorityQuota.totalGranted) / \(detail.priorityQuota.totalUsed)")
            TextField("授予数量（1–1000）", text: $grantAmount).keyboardType(.numberPad)
            Button("授予额度") { Task { await changePriority("grant", amount: grantAmount) } }
            TextField("删除数量", text: $removeAmount).keyboardType(.numberPad)
            Button("删除额度", role: .destructive) { Task { await changePriority("remove", amount: removeAmount) } }
            Button("清空可用额度", role: .destructive) { confirmation = .clearPriority }
                .disabled(detail.priorityQuota.balance == 0)
        }
        Section("优先上传时段限额") {
            TextField("每天上限（留空不限）", text: $quotaDay).keyboardType(.numberPad)
            TextField("每周上限（留空不限）", text: $quotaWeek).keyboardType(.numberPad)
            TextField("每月上限（留空不限）", text: $quotaMonth).keyboardType(.numberPad)
            Button("保存限额") { Task { await saveQuota() } }
        }
    }

    private var twoFactorSection: some View {
        Section("两步验证") {
            if detail.twoFactor.isEmpty { Text("未绑定任何两步验证方式").foregroundStyle(.secondary) }
            ForEach(detail.twoFactor, id: \.method) { method in
                Toggle(twoFactorName(method.method), isOn: Binding(
                    get: { method.enabled },
                    set: { enabled in Task { await toggle2FA(method.method, enabled: enabled) } }
                ))
            }
            Button("清除全部两步验证绑定", role: .destructive) { confirmation = .reset2FA }
                .disabled(detail.twoFactor.isEmpty)
        }
    }

    private var sessionSection: some View {
        Section("登录会话（\(detail.sessions.count)）") {
            ForEach(detail.sessions) { session in
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.ip ?? "未知 IP").font(.subheadline)
                    Text(session.userAgent ?? "未知设备").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Button("下线此会话", role: .destructive) { Task { await revokeSession(session.id) } }
                        .font(.caption)
                }
            }
            if !detail.sessions.isEmpty { Button("全部会话下线", role: .destructive) { confirmation = .revokeAllSessions } }
        }
    }

    private var wechatSection: some View {
        Section("微信小程序绑定") {
            LabeledContent("状态", value: detail.wechatBinding.bound ? "已绑定" : "未绑定")
            if let masked = detail.wechatBinding.openidMasked { LabeledContent("OpenID", value: masked) }
            if detail.wechatBinding.bound {
                Button("强制解绑并吊销小程序会话", role: .destructive) { confirmation = .unbindWechat }
            }
        }
    }

    @ViewBuilder private var history: some View {
        if !detail.warnings.isEmpty {
            Section("警告记录") {
                ForEach(detail.warnings) { warning in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("-\(warning.points) 分 · \(warning.issuedBy ?? "系统")").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        Text(warning.reason)
                        if detail.canWarn {
                            Button("撤销警告", role: .destructive) { confirmation = .revokeWarning(warning.id) }.font(.caption)
                        }
                    }
                }
            }
        }
        if !detail.bans.isEmpty {
            Section("处置历史") {
                ForEach(detail.bans) { ban in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(restrictionName(ban.action)).font(.subheadline.weight(.semibold))
                        Text(ban.reason ?? "无说明").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @MainActor private func run(_ operation: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do { try await operation(); errorMessage = nil; await reload() }
        catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func send<Body: Encodable & Sendable>(_ path: String, method: String = "POST", body: Body) async {
        await run { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/users/\(detail.id)/\(path)", method: method, body: body) }
    }

    @MainActor private func noBody(_ path: String, method: String = "POST", query: [URLQueryItem] = []) async {
        await run {
            let _: AdminActionResponse = try await APIClient.shared.send(
                "api/admin/users/\(detail.id)/\(path)", method: method, query: query
            )
        }
    }

    @MainActor private func saveProfile() async {
        await send("", method: "PUT", body: ProfileBody(display_name: displayName, email: email, bio: bio))
    }

    @MainActor private func warn() async {
        await send("warn", body: WarnBody(points: Int(warningPoints) ?? 0, level: 1, reason: warningReason, photo_id: nil))
    }

    @MainActor private func changePriority(_ action: String, amount: String) async {
        guard let value = Int(amount), (1...1000).contains(value) else { errorMessage = "请输入 1 至 1000 的整数"; return }
        if action == "remove", value > detail.priorityQuota.balance { errorMessage = "删除数量不能超过当前余额"; return }
        await send("priority/\(action)", body: PriorityBody(amount: value, note: nil))
    }

    @MainActor private func saveQuota() async {
        await send("quota", body: QuotaBody(priority_per_day: Int(quotaDay), priority_per_week: Int(quotaWeek), priority_per_month: Int(quotaMonth), reason: nil, expires_at: nil))
    }

    @MainActor private func toggle2FA(_ method: String, enabled: Bool) async {
        await send("2fa/toggle", body: TwoFABody(method: method, enabled: enabled))
    }

    @MainActor private func revokeSession(_ id: Int) async {
        await noBody("sessions/revoke", query: [URLQueryItem(name: "session_id", value: String(id))])
    }

    @MainActor private func uploadAvatar(_ item: PhotosPickerItem) async {
        busy = true
        defer { busy = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), data.count <= 8 * 1024 * 1024 else {
                throw APIClientError.server(code: "avatar_invalid", message: "头像不能为空且不能超过 8MB", status: 400)
            }
            let _: AdminActionResponse = try await APIClient.shared.upload("api/admin/users/\(detail.id)/avatar", imageData: data, filename: "avatar.jpg", mimeType: "image/jpeg", fields: [:])
            errorMessage = nil
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func performConfirmation(_ action: UserConfirmation) async {
        confirmation = nil
        switch action {
        case .resetPassword: await send("password", method: "PUT", body: PasswordBody(new_password: newPassword))
        case .restriction:
            await send("ban", body: RestrictionBody(action: restriction, duration_days: Int(restrictionDays), reason: restrictionReason.nilIfBlank))
        case .simple(let path, _): await noBody(path)
        case .clearPriority: await send("priority/clear", body: NoteBody(note: nil))
        case .reset2FA: await noBody("2fa/reset")
        case .revokeAllSessions: await noBody("sessions/revoke")
        case .unbindWechat: await noBody("wechat-binding", method: "DELETE")
        case .revokeWarning(let id): await noBody("warnings/\(id)", method: "DELETE")
        }
    }
}

private struct AdminUserPermissionsView: View {
    @Environment(\.dismiss) private var dismiss
    let userID: Int
    @State private var response: AdminUserPermissionsResponse?
    @State private var busyKey: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let response {
                    Section {
                        Text("用户组「\(response.roleLabel)」提供基础权限；个人拒绝优先于个人授予和组权限。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Dictionary(grouping: response.items, by: \.categoryLabel).keys.sorted(), id: \.self) { category in
                        Section(category) {
                            ForEach(response.items.filter { $0.categoryLabel == category }) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack { Text(item.name); Spacer(); if item.effective { Text("生效").font(.caption2).foregroundStyle(.green) } }
                                    Text(item.description).font(.caption).foregroundStyle(.secondary)
                                    Picker("覆盖", selection: Binding(
                                        get: { item.override ?? "inherit" },
                                        set: { state in Task { await setPermission(item.permKey, state: state) } }
                                    )) {
                                        Text("继承").tag("inherit"); Text("授予").tag("grant"); Text("拒绝").tag("deny")
                                    }
                                    .pickerStyle(.segmented).disabled(response.isAdmin || busyKey == item.permKey)
                                }
                            }
                        }
                    }
                } else { ProgressView().frame(maxWidth: .infinity) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("逐项个人权限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        do { response = try await APIClient.shared.get("api/admin/users/\(userID)/permissions"); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func setPermission(_ key: String, state: String) async {
        busyKey = key
        defer { busyKey = nil }
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/users/\(userID)/permissions", body: PermissionBody(perm_key: key, state: state, expires_at: nil))
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

private enum UserConfirmation: Equatable {
    case resetPassword, restriction, clearPriority, reset2FA, revokeAllSessions, unbindWechat
    case revokeWarning(Int)
    case simple(String, String)
    var title: String {
        switch self {
        case .resetPassword: "确认重置密码并强制下线全部设备？"
        case .restriction: "确认执行账号限制？"
        case .clearPriority: "确认清空全部可用优先额度？"
        case .reset2FA: "确认清除全部两步验证绑定？"
        case .revokeAllSessions: "确认下线全部会话？"
        case .unbindWechat: "确认解绑微信并吊销小程序会话？"
        case .revokeWarning: "确认撤销这条警告？已有处罚不会自动解除。"
        case .simple(_, let title): title
        }
    }
    var button: String { destructive ? "确认执行" : "确认" }
    var destructive: Bool { self != .simple("", "") }
}

private struct AdminRoleOption: Codable, Identifiable, Sendable { let key: String; let name: String; let level: Int; var id: String { key } }
private struct AdminUserRowModel: Codable, Identifiable, Sendable {
    let id: Int; let username: String; let displayName: String; let email: String; let avatar: String?
    let role: String; let roleLabel: String; let banned: Bool; let photoCount: Int; let createdAt: String?
}
private struct AdminUsersResponse: Codable, Sendable { let items: [AdminUserRowModel]; let total: Int; let roleOptions: [AdminRoleOption] }

private struct AdminUserDetail: Codable, Sendable {
    struct Stats: Codable, Sendable { let total: Int; let approved: Int; let rejected: Int; let pending: Int }
    struct Warning: Codable, Identifiable, Sendable { let id: Int; let level: Int; let points: Int; let reason: String; let photoId: Int?; let issuedBy: String?; let acknowledged: Bool; let expiresAt: String?; let createdAt: String? }
    struct Ban: Codable, Identifiable, Sendable { let id: Int; let action: String; let reason: String?; let durationDays: Int?; let by: String?; let expiresAt: String?; let createdAt: String? }
    struct Session: Codable, Identifiable, Sendable { let id: Int; let ip: String?; let userAgent: String?; let lastActive: String?; let createdAt: String?; let expiresAt: String? }
    struct TwoFactor: Codable, Sendable { let method: String; let enabled: Bool }
    struct PriorityQuota: Codable, Sendable { let balance: Int; let approvalStreak: Int; let totalGranted: Int; let totalUsed: Int }
    struct PriorityOverride: Codable, Sendable { let perDay: Int?; let perWeek: Int?; let perMonth: Int?; let reason: String?; let expiresAt: String?; let createdAt: String? }
    struct WechatBinding: Codable, Sendable { let bound: Bool; let openidMasked: String?; let hasUnionid: Bool; let boundAt: String?; let updatedAt: String?; let activeSessionCount: Int }
    let id: Int; let username: String; let email: String; let displayName: String; let avatar: String?; let avatarUrl: String?; let bio: String?
    let role: String; let roleLabel: String; let banned: Bool; let banReason: String?; let banExpiresAt: String?
    let muted: Bool; let mutedUntil: String?; let suspended: Bool; let suspendedUntil: String?; let twoFactorEnabled: Bool; let createdAt: String?
    let stats: Stats; let warningPoints: Int; let warnings: [Warning]; let bans: [Ban]
    let priorityQuota: PriorityQuota; let priorityOverride: PriorityOverride?; let sessions: [Session]; let twoFactor: [TwoFactor]; let wechatBinding: WechatBinding
    let permissions: [String]; let roleOptions: [AdminRoleOption]
    let canEdit: Bool; let canAssignRole: Bool; let canBan: Bool; let canWarn: Bool; let canQuota: Bool; let canRevokeSessions: Bool; let canUnbindWechat: Bool; let canReset2fa: Bool; let canManagePerms: Bool
}

private struct AdminPermissionItem: Codable, Identifiable, Sendable {
    let permKey: String; let name: String; let category: String; let categoryLabel: String; let description: String
    let fromGroup: Bool; let override: String?; let effective: Bool; let expiresAt: String?
    var id: String { permKey }
}
private struct AdminUserPermissionsResponse: Codable, Sendable { let roleLabel: String; let isAdmin: Bool; let items: [AdminPermissionItem] }

private struct ProfileBody: Encodable, Sendable { let display_name: String; let email: String; let bio: String }
private struct PasswordBody: Encodable, Sendable { let new_password: String }
private struct RoleBody: Encodable, Sendable { let role: String }
private struct RestrictionBody: Encodable, Sendable { let action: String; let duration_days: Int?; let reason: String? }
private struct WarnBody: Encodable, Sendable { let points: Int; let level: Int; let reason: String; let photo_id: Int? }
private struct PriorityBody: Encodable, Sendable { let amount: Int; let note: String? }
private struct NoteBody: Encodable, Sendable { let note: String? }
private struct QuotaBody: Encodable, Sendable { let priority_per_day: Int?; let priority_per_week: Int?; let priority_per_month: Int?; let reason: String?; let expires_at: String? }
private struct TwoFABody: Encodable, Sendable { let method: String; let enabled: Bool }
private struct PermissionBody: Encodable, Sendable { let perm_key: String; let state: String; let expires_at: String? }

private func twoFactorName(_ method: String) -> String {
    switch method { case "totp": "验证器 (TOTP)"; case "email_otp": "邮箱验证码"; case "sms_otp": "短信验证码"; default: method }
}
private func restrictionName(_ action: String) -> String {
    switch action { case "ban": "封禁"; case "unban": "解除限制"; case "mute": "禁言"; case "suspend": "暂停"; default: action }
}
private extension String {
    var nilIfBlank: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value }
}
