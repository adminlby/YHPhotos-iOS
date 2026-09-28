import SwiftUI
import UIKit

struct AdminAPIKeysView: View {
    let identity: AdminIdentity
    @State private var panel: APISettingsPanel
    private var canKeys: Bool { identity.can(anyOf: APISettingsPanel.keys.permissions) }
    private var canApps: Bool { identity.can("system.apikey.applications") }
    init(identity: AdminIdentity) { self.identity = identity; _panel = State(initialValue: identity.can(anyOf: APISettingsPanel.keys.permissions) ? .keys : .applications) }
    var body: some View { VStack(spacing: 0) { if canKeys && canApps { Picker("API 管理", selection: $panel) { Text("密钥").tag(APISettingsPanel.keys); Text("申请").tag(APISettingsPanel.applications) }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8) }; if panel == .keys { APIKeyListView(identity: identity) } else { APIApplicationsView(identity: identity) } } }
}

private enum APISettingsPanel: String { case keys, applications; var permissions: [String] { self == .applications ? ["system.apikey.applications"] : ["system.apikey.view", "system.apikey.create", "system.apikey.edit", "system.apikey.whitelist", "system.apikey.enable", "system.apikey.disable", "system.apikey.ban", "system.apikey.rotate", "system.apikey.logs", "system.apikey.delete", "system.apikey.manage"] } }

private struct APIKeyListView: View {
    let identity: AdminIdentity
    @State private var response: APIKeysResponse?; @State private var creating = false; @State private var revealed: APISecretResponse?; @State private var loading = true; @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("公开 API 前缀为 /api/public，请求须携带 X-Api-Key 与 X-Api-Secret。Secret 只在签发或重签时显示一次。")
                    .font(.caption).foregroundStyle(.secondary)
                if identity.can("system.apikey.create") {
                    Button("手动签发密钥", systemImage: "key.fill") { creating = true }
                }
            }
            if response?.schemaReady == false {
                Section { Label("公开 API 数据库结构尚未就绪，请先执行对应迁移。", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
            if response?.partnerSharingReady == false {
                Section { Label("合作方供图结构尚未就绪，目前只能使用普通 API。", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            if let items = response?.items {
                Section("密钥（\(items.count)）") {
                    ForEach(items) { key in
                        NavigationLink {
                            APIKeyDetailView(identity: identity, key: key, partnerSharingReady: response?.partnerSharingReady != false) {
                                Task { await load() }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(key.name).font(.subheadline.weight(.semibold)); Spacer(); APIKeyStatusLabel(status: key.status) }
                                Text(key.apiKey).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                Text(key.summary).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            if loading { ProgressView() }
            if !loading && response?.items.isEmpty == true { Text("还没有 API 密钥").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) {
            APIKeyCreateView(partnerSharingReady: response?.partnerSharingReady != false) { revealed = $0 }
        }
        .sheet(item: $revealed) { APISecretRevealView(response: $0) }
    }
    @MainActor private func load() async { loading = true; do { response = try await APIClient.shared.get("api/admin/settings/api-keys"); error = nil } catch { self.error = error.localizedDescription }; loading = false }
}

private struct APIKeyCreateView: View {
    @Environment(\.dismiss) private var dismiss
    let partnerSharingReady: Bool; let revealed: (APISecretResponse) -> Void
    @State private var name = ""; @State private var scopes = Set(["photos", "data", "open"]); @State private var rate = "1000"; @State private var qps = "0"; @State private var partner = "general"; @State private var busy = false; @State private var error: String?
    var body: some View { NavigationStack { Form { Section("项目") { TextField("项目名称", text: $name); TextField("每小时限额（0 不限）", text: $rate).keyboardType(.numberPad); TextField("QPS（0 不限）", text: $qps).keyboardType(.numberPad); PartnerTypePicker(value: $partner, enabled: partnerSharingReady) }; APIKeyScopeSection(scopes: $scopes); if let error { Section { Text(error).foregroundStyle(.red) } } }.navigationTitle("签发 API 密钥").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("签发") { Task { await create() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || scopes.isEmpty || busy) } } } }
    @MainActor private func create() async { busy = true; defer { busy = false }; do { let body = APIKeyCreateBody(name: name, description: nil, contact: nil, scopes: Array(scopes).sorted(), rate_limit: Int(rate) ?? 0, qps: Int(qps) ?? 0, expires_at: nil, ip_whitelist: nil, whitelist_enabled: false, partner_type: partner); let r: APISecretResponse = try await APIClient.shared.send("api/admin/settings/api-keys", body: body); dismiss(); revealed(r) } catch { self.error = error.localizedDescription } }
}

private struct APIKeyDetailView: View {
    let identity: AdminIdentity; let key: APIKeyRecord; let partnerSharingReady: Bool; let changed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String; @State private var description: String; @State private var contact: String; @State private var scopes: Set<String>; @State private var rate: String; @State private var qps: String; @State private var expires: String; @State private var partner: String; @State private var whitelist: String; @State private var whitelistOn: Bool
    @State private var action: APIKeyAction?; @State private var banReason = ""; @State private var revealed: APISecretResponse?; @State private var logs: APIKeyLogsResponse?; @State private var logOffset = 0; @State private var busy = false; @State private var error: String?
    init(identity: AdminIdentity, key: APIKeyRecord, partnerSharingReady: Bool, changed: @escaping () -> Void) { self.identity = identity; self.key = key; self.partnerSharingReady = partnerSharingReady; self.changed = changed; _name = .init(initialValue: key.name); _description = .init(initialValue: key.description ?? ""); _contact = .init(initialValue: key.contact ?? ""); _scopes = .init(initialValue: Set(key.scopes)); _rate = .init(initialValue: String(key.rateLimit)); _qps = .init(initialValue: String(key.qps)); _expires = .init(initialValue: key.expiresAt ?? ""); _partner = .init(initialValue: key.partnerType); _whitelist = .init(initialValue: key.ipWhitelist ?? ""); _whitelistOn = .init(initialValue: key.whitelistEnabled ?? false) }
    var body: some View { List {
        Section("密钥") { LabeledContent("Key") { Text(key.apiKey).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }; LabeledContent("状态") { APIKeyStatusLabel(status: key.status) }; LabeledContent("归属", value: key.owner ?? "无归属用户"); if let last = key.lastUsedAt { LabeledContent("最近调用", value: last) }; if let reason = key.bannedReason { LabeledContent("封禁原因", value: reason) } }
        if identity.can("system.apikey.edit") { Section("基本信息与限额") { TextField("项目名称", text: $name); TextField("联系方式", text: $contact); TextField("用途说明", text: $description, axis: .vertical).lineLimit(2...6); TextField("每小时限额（0 不限）", text: $rate).keyboardType(.numberPad); TextField("QPS（0 不限）", text: $qps).keyboardType(.numberPad); TextField("过期时间（留空永久）", text: $expires); PartnerTypePicker(value: $partner, enabled: partnerSharingReady); APIKeyScopeChecks(scopes: $scopes); Button("保存信息") { Task { await saveInfo() } } } }
        if identity.can("system.apikey.whitelist") { Section("IP 白名单") { Toggle("启用 IP 白名单", isOn: $whitelistOn); TextField("每行一个 IP 或 CIDR", text: $whitelist, axis: .vertical).lineLimit(3...10).font(.system(.body, design: .monospaced)).disabled(!whitelistOn); Button("保存白名单") { Task { await saveWhitelist() } } } }
        Section("状态操作") {
            if identity.can("system.apikey.enable"), key.status == "disabled" { Button("启用", systemImage: "play.fill") { Task { await simpleAction("enable") } }.foregroundStyle(.green) }
            if identity.can("system.apikey.disable"), key.status == "active" { Button("停用", systemImage: "pause.fill") { action = .disable } }
            if identity.can("system.apikey.ban"), key.status != "banned" { TextField("封禁原因（选填）", text: $banReason); Button("封禁", systemImage: "hand.raised.fill", role: .destructive) { action = .ban } }
            if identity.can("system.apikey.ban"), key.status == "banned" { Button("解除封禁", systemImage: "lock.open") { Task { await simpleAction("unban") } } }
            if identity.can("system.apikey.rotate") { Button("重签 Secret", systemImage: "arrow.triangle.2.circlepath") { action = .rotate } }
            if identity.can("system.apikey.delete") { Button("永久删除密钥与调用日志", systemImage: "trash", role: .destructive) { action = .delete } }
        }
        if identity.can("system.apikey.logs") { Section("调用日志") { if let logs { ForEach(logs.items) { row in VStack(alignment: .leading, spacing: 3) { HStack { Text("\(row.method) \(row.path)").font(.system(.caption, design: .monospaced)); Spacer(); Text(String(row.status)).foregroundStyle((200..<400).contains(row.status) ? .green : .red) }; Text("\(row.scope) · \(row.ip ?? "—") · \(row.latencyMs.map { "\($0) ms" } ?? "—")\(row.error.map { " · \($0)" } ?? "")").font(.caption2).foregroundStyle(.secondary); Text(row.createdAt ?? "").font(.caption2).foregroundStyle(.tertiary) } }; if logs.total > 20 { AdminRankingPager(offset: $logOffset, limit: 20, total: logs.total) } } else { ProgressView() } } }
        if busy { ProgressView() }; if let error { Text(error).foregroundStyle(.red) }
    }.navigationTitle(key.name).navigationBarTitleDisplayMode(.inline).task(id: logOffset) { if identity.can("system.apikey.logs") { await loadLogs() } }.sheet(item: $revealed) { APISecretRevealView(response: $0) }.confirmationDialog(action?.prompt ?? "", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) { if let action { Button(action.button, role: action.destructive ? .destructive : nil) { Task { await perform(action) } } }; Button("取消", role: .cancel) {} } }
    @MainActor private func saveInfo() async { await working { let body = APIKeyEditBody(name: name, description: description, contact: contact, scopes: Array(scopes).sorted(), rate_limit: Int(rate) ?? 0, qps: Int(qps) ?? 0, expires_at: expires.isEmpty ? nil : expires.replacingOccurrences(of: "T", with: " "), partner_type: partner); let _: AdminActionResponse = try await APIClient.shared.send("api/admin/settings/api-keys/\(key.id)", method: "PATCH", body: body) } }
    @MainActor private func saveWhitelist() async { await working { let _: APIWhitelistResponse = try await APIClient.shared.send("api/admin/settings/api-keys/\(key.id)/whitelist", method: "PUT", body: APIWhitelistBody(ip_whitelist: whitelist, whitelist_enabled: whitelistOn)) } }
    @MainActor private func simpleAction(_ path: String) async { await working { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/settings/api-keys/\(key.id)/\(path)", method: "POST") } }
    @MainActor private func perform(_ value: APIKeyAction) async { action = nil; switch value { case .disable: await simpleAction("disable"); case .ban: await working { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/settings/api-keys/\(key.id)/ban", body: APIBanBody(reason: banReason.isEmpty ? nil : banReason)) }; case .rotate: await working { revealed = try await APIClient.shared.send("api/admin/settings/api-keys/\(key.id)/rotate", method: "POST") }; case .delete: await working { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/settings/api-keys/\(key.id)", method: "DELETE"); dismiss() } } }
    @MainActor private func working(_ work: () async throws -> Void) async { busy = true; defer { busy = false }; do { try await work(); error = nil; changed() } catch { self.error = error.localizedDescription } }
    @MainActor private func loadLogs() async { do { logs = try await APIClient.shared.get("api/admin/settings/api-keys/\(key.id)/logs", query: [.init(name: "offset", value: String(logOffset)), .init(name: "limit", value: "20")]) } catch { self.error = error.localizedDescription } }
}

private struct APIApplicationsView: View {
    let identity: AdminIdentity
    @State private var response: APIApplicationsResponse?; @State private var status = "pending"; @State private var offset = 0; @State private var decision: APIApplicationDecisionState?; @State private var reject: APIApplicationRejectState?; @State private var revealed: APISecretResponse?; @State private var loading = true; @State private var error: String?; private let limit = 20
    var body: some View { List {
        Section { Picker("状态", selection: $status) { Text("待审批").tag("pending"); Text("全部").tag("all"); Text("已通过").tag("approved"); Text("未通过").tag("rejected") } }
        if let response { Section("共 \(response.total) 条 · 待审批 \(response.pending) 条") { ForEach(response.items) { app in VStack(alignment: .leading, spacing: 6) { HStack { Text(app.name).font(.subheadline.weight(.semibold)); Spacer(); APIKeyStatusLabel(status: app.status) }; Text("\(app.user.displayName ?? app.user.username ?? "用户 #\(app.user.id)") · 每小时 \(app.rateLimit) · QPS \(app.qps)").font(.caption).foregroundStyle(.secondary); Text(app.purpose).font(.caption).lineLimit(3); Text("范围：\(app.scopes.joined(separator: "、"))\(app.contact.map { " · \($0)" } ?? "")").font(.caption2).foregroundStyle(.tertiary); if !app.whitelist.isEmpty { Text(app.whitelist).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary) }; if let reply = app.adminReply { Text("管理员回复：\(reply)").font(.caption).foregroundStyle(.secondary) }; if app.status == "pending" { HStack { Button("审批通过") { decision = .init(application: app) }.buttonStyle(.borderedProminent); Button("拒绝", role: .destructive) { reject = .init(application: app) }.buttonStyle(.bordered) } } }.padding(.vertical, 3) } }; if response.total > limit { Section { AdminRankingPager(offset: $offset, limit: limit, total: response.total) } } }
        if loading { ProgressView() }; if !loading && response?.items.isEmpty == true { Text("暂无申请").foregroundStyle(.secondary) }; if let error { Text(error).foregroundStyle(.red) }
    }.task(id: "\(status)|\(offset)") { await load() }.sheet(item: $decision) { APIApplicationApproveView(state: $0, partnerSharingReady: response?.partnerSharingReady != false) { revealed = $0; Task { await load() } } }.sheet(item: $reject) { APIApplicationRejectView(state: $0) { Task { await load() } } }.sheet(item: $revealed) { APISecretRevealView(response: $0) } }
    @MainActor private func load() async { loading = true; do { var q = [URLQueryItem(name: "offset", value: String(offset)), .init(name: "limit", value: String(limit))]; if status != "all" { q.append(.init(name: "status", value: status)) }; response = try await APIClient.shared.get("api/admin/settings/api-applications", query: q); error = nil } catch { self.error = error.localizedDescription }; loading = false }
}

private struct APIApplicationApproveView: View {
    @Environment(\.dismiss) private var dismiss; let state: APIApplicationDecisionState; let partnerSharingReady: Bool; let completed: (APISecretResponse) -> Void
    @State private var scopes: Set<String>; @State private var rate: String; @State private var qps: String; @State private var whitelist: String; @State private var whitelistOn: Bool; @State private var expires = ""; @State private var reply = ""; @State private var partner = "general"; @State private var busy = false; @State private var error: String?
    init(state: APIApplicationDecisionState, partnerSharingReady: Bool, completed: @escaping (APISecretResponse) -> Void) { self.state = state; self.partnerSharingReady = partnerSharingReady; self.completed = completed; let a = state.application; _scopes = .init(initialValue: Set(a.scopes.isEmpty ? ["photos"] : a.scopes)); _rate = .init(initialValue: String(a.rateLimit)); _qps = .init(initialValue: String(a.qps)); _whitelist = .init(initialValue: a.whitelist); _whitelistOn = .init(initialValue: !a.whitelist.isEmpty) }
    var body: some View { NavigationStack { Form { APIKeyScopeSection(scopes: $scopes); Section("限额与类型") { TextField("每小时限额", text: $rate).keyboardType(.numberPad); TextField("QPS", text: $qps).keyboardType(.numberPad); TextField("过期时间（选填）", text: $expires); PartnerTypePicker(value: $partner, enabled: partnerSharingReady) }; Section("IP 白名单") { Toggle("启用", isOn: $whitelistOn); TextField("每行一个 IP / CIDR", text: $whitelist, axis: .vertical).lineLimit(3...8).disabled(!whitelistOn) }; Section("给用户的回复") { TextField("选填", text: $reply, axis: .vertical).lineLimit(2...6) }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("审批“\(state.application.name)”").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("通过并签发") { Task { await approve() } }.disabled(scopes.isEmpty || busy) } } } }
    @MainActor private func approve() async { busy = true; defer { busy = false }; do { let body = APIApplicationApproveBody(scopes: Array(scopes).sorted(), rate_limit: Int(rate) ?? 0, qps: Int(qps) ?? 0, whitelist_enabled: whitelistOn, ip_whitelist: whitelist, expires_at: expires.isEmpty ? nil : expires, reply: reply.isEmpty ? nil : reply, partner_type: partner); let r: APISecretResponse = try await APIClient.shared.send("api/admin/settings/api-applications/\(state.application.id)/approve", body: body); dismiss(); completed(r) } catch { self.error = error.localizedDescription } }
}

private struct APIApplicationRejectView: View {
    @Environment(\.dismiss) private var dismiss; let state: APIApplicationRejectState; let completed: () -> Void
    @State private var reply = ""; @State private var busy = false; @State private var error: String?
    var body: some View { NavigationStack { Form { Section { TextField("拒绝原因（可留空）", text: $reply, axis: .vertical).lineLimit(3...8) }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("拒绝申请").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("确认拒绝", role: .destructive) { Task { await reject() } }.disabled(busy) } } } }
    @MainActor private func reject() async { busy = true; defer { busy = false }; do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/settings/api-applications/\(state.application.id)/reject", body: APIApplicationRejectBody(reply: reply.isEmpty ? nil : reply)); dismiss(); completed() } catch { self.error = error.localizedDescription } }
}

private struct APISecretRevealView: View {
    @Environment(\.dismiss) private var dismiss; let response: APISecretResponse
    var body: some View { NavigationStack { Form { Section { Label("Secret 只显示这一次，请立即安全保存。", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }; Section("Key") { Text(response.apiKey).font(.system(.body, design: .monospaced)).textSelection(.enabled); Button("复制 Key", systemImage: "doc.on.doc") { UIPasteboard.general.string = response.apiKey } }; Section("Secret") { Text(response.apiSecret).font(.system(.body, design: .monospaced)).textSelection(.enabled); Button("复制 Secret", systemImage: "doc.on.doc") { UIPasteboard.general.string = response.apiSecret } } }.navigationTitle("密钥已生成").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("我已保存") { dismiss() } } } } }
}

private struct APIKeyScopeSection: View { @Binding var scopes: Set<String>; var body: some View { Section("权限范围") { APIKeyScopeChecks(scopes: $scopes) } } }
private struct APIKeyScopeChecks: View { @Binding var scopes: Set<String>; var body: some View { Toggle("图片 API", isOn: scope("photos")); Toggle("数据 API", isOn: scope("data")); Toggle("公开数据", isOn: scope("open")) }; private func scope(_ value: String) -> Binding<Bool> { Binding(get: { scopes.contains(value) }, set: { if $0 { scopes.insert(value) } else { scopes.remove(value) } }) } }
private struct PartnerTypePicker: View { @Binding var value: String; let enabled: Bool; var body: some View { Picker("合作方产品类型", selection: $value) { Text("普通 API").tag("general"); Text("AirNav 供图 API").tag("airnav"); Text("双流机场供图 API").tag("shuangliu") }.disabled(!enabled) } }
private struct APIKeyStatusLabel: View { let status: String; var body: some View { Text(["active":"启用", "disabled":"停用", "banned":"封禁", "pending":"待审批", "approved":"已通过", "rejected":"未通过"][status] ?? status).font(.caption.weight(.semibold)).foregroundStyle(status == "active" || status == "approved" ? .green : status == "banned" || status == "rejected" ? .red : .secondary) } }
private enum APIKeyAction: String, Identifiable { case disable, ban, rotate, delete; var id: String { rawValue }; var prompt: String { switch self { case .disable: "停用后该密钥会立即无法调用。"; case .ban: "封禁该密钥并记录原因？"; case .rotate: "重签后旧 Secret 会立即失效。"; case .delete: "永久删除密钥和全部调用日志？此操作无法恢复。" } }; var button: String { switch self { case .disable: "停用"; case .ban: "封禁"; case .rotate: "重签"; case .delete: "永久删除" } }; var destructive: Bool { self != .rotate } }
private struct APIApplicationDecisionState: Identifiable { let id = UUID(); let application: APIApplication }
private struct APIApplicationRejectState: Identifiable { let id = UUID(); let application: APIApplication }

private struct APIKeysResponse: Codable, Sendable { let schemaReady: Bool?; let applicationsReady: Bool?; let partnerSharingReady: Bool?; let items: [APIKeyRecord] }
private struct APIKeyRecord: Codable, Identifiable, Sendable { let id: Int; let name: String; let description: String?; let contact: String?; let apiKey: String; let scopes: [String]; let partnerType: String; let rateLimit: Int; let qps: Int; let enabled: Bool; let status: String; let owner: String?; let ownerId: Int?; let ipWhitelist: String?; let whitelistEnabled: Bool?; let bannedReason: String?; let bannedAt: String?; let lastUsedAt: String?; let expiresAt: String?; let createdAt: String?; var partnerLabel: String { ["general":"普通 API", "airnav":"AirNav", "shuangliu":"双流机场"][partnerType] ?? partnerType }; var summary: String { "\(partnerLabel) · 每小时 \(rateLimit == 0 ? "不限" : String(rateLimit)) · QPS \(qps == 0 ? "不限" : String(qps)) · \(owner ?? "无归属")" } }
private struct APISecretResponse: Codable, Identifiable, Sendable { var id: String { apiSecret }; let apiKey: String; let apiSecret: String }
private struct APIKeyCreateBody: Encodable, Sendable { let name: String; let description: String?; let contact: String?; let scopes: [String]; let rate_limit: Int; let qps: Int; let expires_at: String?; let ip_whitelist: String?; let whitelist_enabled: Bool; let partner_type: String }
private struct APIKeyEditBody: Encodable, Sendable { let name: String; let description: String?; let contact: String?; let scopes: [String]; let rate_limit: Int; let qps: Int; let expires_at: String?; let partner_type: String }
private struct APIWhitelistBody: Encodable, Sendable { let ip_whitelist: String; let whitelist_enabled: Bool }
private struct APIWhitelistResponse: Codable, Sendable { let ok: Bool; let ipWhitelist: String; let whitelistEnabled: Bool }
private struct APIBanBody: Encodable, Sendable { let reason: String? }
private struct APIKeyLogsResponse: Codable, Sendable { let total: Int; let items: [APIKeyLog] }
private struct APIKeyLog: Codable, Identifiable, Sendable { let id: Int; let scope: String; let method: String; let path: String; let status: Int; let ip: String?; let userAgent: String?; let latencyMs: Int?; let error: String?; let createdAt: String? }
private struct APIApplicationsResponse: Codable, Sendable { let total: Int; let pending: Int; let partnerSharingReady: Bool?; let items: [APIApplication] }
private struct APIApplication: Codable, Identifiable, Sendable { struct User: Codable, Sendable { let id: Int; let displayName: String?; let username: String? }; let id: Int; let name: String; let purpose: String; let contact: String?; let scopes: [String]; let rateLimit: Int; let qps: Int; let whitelist: String; let status: String; let adminReply: String?; let apiKeyId: Int?; let user: User; let handler: String?; let handledAt: String?; let createdAt: String? }
private struct APIApplicationApproveBody: Encodable, Sendable { let scopes: [String]; let rate_limit: Int; let qps: Int; let whitelist_enabled: Bool; let ip_whitelist: String; let expires_at: String?; let reply: String?; let partner_type: String }
private struct APIApplicationRejectBody: Encodable, Sendable { let reply: String? }
