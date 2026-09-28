import SwiftUI

struct AdminSettingsView: View {
    let identity: AdminIdentity
    @State private var tab: SettingsTab
    private var tabs: [SettingsTab] { SettingsTab.allCases.filter { identity.can(anyOf: $0.permissions) } }
    init(identity: AdminIdentity) { self.identity = identity; _tab = State(initialValue: SettingsTab.allCases.first { identity.can(anyOf: $0.permissions) } ?? .site) }
    var body: some View {
        VStack(spacing: 0) {
            Picker("设置类别", selection: $tab) { ForEach(tabs) { Text($0.title).tag($0) } }.pickerStyle(.segmented).padding()
            switch tab {
            case .site: SiteSettingsView()
            case .watermark: WatermarkSettingsView()
            case .warnings: WarningRulesView()
            case .email: EmailRecordsView()
            case .api: AdminAPIKeysView(identity: identity)
            }
        }.navigationTitle("站点设置").navigationBarTitleDisplayMode(.inline)
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable { case site, watermark, warnings, email, api; var id: String { rawValue }; var title: String { switch self { case .site: "站点"; case .watermark: "水印"; case .warnings: "违规"; case .email: "邮件"; case .api: "API" } }; var permissions: [String] { switch self { case .site: ["system.settings"]; case .watermark: ["system.watermark"]; case .warnings: ["system.warning.rules"]; case .email: ["system.email.view"]; case .api: ["system.apikey.view", "system.apikey.create", "system.apikey.edit", "system.apikey.whitelist", "system.apikey.enable", "system.apikey.disable", "system.apikey.ban", "system.apikey.rotate", "system.apikey.logs", "system.apikey.delete", "system.apikey.applications", "system.apikey.manage"] } } }

private struct SiteSettingsView: View {
    @State private var items: [SiteSetting] = []; @State private var draft: [String: String] = [:]; @State private var loading = true; @State private var busy = false; @State private var error: String?
    private var categories: [String] { Array(Set(items.map { $0.category ?? "其它" })).sorted() }
    var body: some View { List {
        ForEach(categories, id: \.self) { category in Section(category) { ForEach(items.filter { ($0.category ?? "其它") == category }) { item in VStack(alignment: .leading, spacing: 5) { if item.type == "bool" { Toggle(item.description ?? "设置项", isOn: boolBinding(item.key)) } else { TextField(item.description ?? "设置项", text: textBinding(item.key), axis: .vertical).lineLimit(1...5) } } } } }
        if !items.isEmpty { Section { Button("保存站点设置", systemImage: "square.and.arrow.down") { Task { await save() } }.disabled(busy) } }
        if loading { ProgressView() }; if let error { Text(error).foregroundStyle(.red) }
    }.task { await load() }.refreshable { await load() } }
    private func textBinding(_ key: String) -> Binding<String> { Binding(get: { draft[key] ?? "" }, set: { draft[key] = $0 }) }
    private func boolBinding(_ key: String) -> Binding<Bool> { Binding(get: { ["1", "true", "yes", "on"].contains((draft[key] ?? "").lowercased()) }, set: { draft[key] = $0 ? "1" : "0" }) }
    @MainActor private func load() async { loading = true; do { let r: SiteSettingsResponse = try await APIClient.shared.get("api/admin/settings"); items = r.items; draft = Dictionary(uniqueKeysWithValues: r.items.map { ($0.key, $0.value ?? "") }); error = nil } catch { self.error = error.localizedDescription }; loading = false }
    @MainActor private func save() async { busy = true; defer { busy = false }; do { let _: SettingsSaveResponse = try await APIClient.shared.send("api/admin/settings", method: "PUT", body: SiteSettingsBody(items: items.map { .init(key: $0.key, value: draft[$0.key] ?? "") })); await load() } catch { self.error = error.localizedDescription } }
}

private struct WatermarkSettingsView: View {
    @State private var watermark = WatermarkSettings.defaults; @State private var loading = true; @State private var busy = false; @State private var error: String?
    var body: some View { Form {
        Section { Toggle("启用全局水印", isOn: $watermark.enabled); Picker("类型", selection: $watermark.type) { Text("文字").tag("text"); Text("图片").tag("image") }; TextField("水印文字", text: $watermark.textContent) }
        Section("布局") { Picker("位置", selection: $watermark.position) { Text("左上").tag("top_left"); Text("右上").tag("top_right"); Text("居中").tag("center"); Text("左下").tag("bottom_left"); Text("右下").tag("bottom_right") }; TextField("颜色（如 #FFFFFF）", text: $watermark.color).textInputAutocapitalization(.characters); Stepper("边距：\(watermark.margin) px", value: $watermark.margin, in: 0...500); Stepper("字号：\(watermark.fontSize) px", value: $watermark.fontSize, in: 1...500); VStack(alignment: .leading) { Text("不透明度：\(watermark.opacity)%"); Slider(value: Binding(get: { Double(watermark.opacity) }, set: { watermark.opacity = Int($0) }), in: 0...100, step: 1) } }
        Section { Button("保存全局水印", systemImage: "square.and.arrow.down") { Task { await save() } }.disabled(busy) }
        if loading { ProgressView() }; if let error { Text(error).foregroundStyle(.red) }
    }.task { await load() } }
    @MainActor private func load() async { loading = true; do { let r: WatermarkResponse = try await APIClient.shared.get("api/admin/settings/watermark"); watermark = r.watermark ?? .defaults; error = nil } catch { self.error = error.localizedDescription }; loading = false }
    @MainActor private func save() async { busy = true; defer { busy = false }; do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/settings/watermark", method: "PUT", body: WatermarkBody(enabled: watermark.enabled, type: watermark.type, text_content: watermark.textContent, position: watermark.position, opacity: watermark.opacity, font_size: watermark.fontSize, color: watermark.color, margin: watermark.margin)); error = nil } catch { self.error = error.localizedDescription } }
}

private struct WarningRulesView: View {
    @State private var rows: [WarningRule] = []; @State private var loading = true; @State private var busy = false; @State private var error: String?
    var body: some View { List {
        Section { Text("违规积分达到阈值时自动处置；不填写时长表示永久。") }
        ForEach($rows) { $row in Section { TextField("积分阈值", value: $row.pointsThreshold, format: .number).keyboardType(.numberPad); Picker("处置", selection: $row.action) { Text("禁言").tag("mute"); Text("暂停").tag("suspend"); Text("封禁").tag("ban") }; TextField("时长（天，0 表示永久）", value: $row.durationDays, format: .number).keyboardType(.numberPad); TextField("说明", text: Binding(get: { row.description ?? "" }, set: { row.description = $0.isEmpty ? nil : $0 }), axis: .vertical); Toggle("启用", isOn: $row.active) } header: { HStack { Text("\(row.pointsThreshold) 分规则"); Spacer(); Button(role: .destructive) { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "trash") } } } }
        Section { Button("添加规则", systemImage: "plus") { rows.append(.init(id: UUID(), pointsThreshold: 0, action: "mute", durationDays: 3, description: nil, active: true)) }; Button("保存全部规则", systemImage: "square.and.arrow.down") { Task { await save() } }.disabled(busy) }
        if loading { ProgressView() }; if let error { Text(error).foregroundStyle(.red) }
    }.task { await load() } }
    @MainActor private func load() async { loading = true; do { let r: WarningRulesResponse = try await APIClient.shared.get("api/admin/settings/warning-rules"); rows = r.items.map { .init(id: UUID(), pointsThreshold: $0.pointsThreshold, action: $0.action, durationDays: $0.durationDays ?? 0, description: $0.description, active: $0.active) }; error = nil } catch { self.error = error.localizedDescription }; loading = false }
    @MainActor private func save() async { busy = true; defer { busy = false }; do { let body = WarningRulesBody(rows: rows.map { .init(points_threshold: $0.pointsThreshold, action: $0.action, duration_days: $0.durationDays == 0 ? nil : $0.durationDays, description: $0.description, active: $0.active) }); let _: AdminActionResponse = try await APIClient.shared.send("api/admin/settings/warning-rules", method: "PUT", body: body); await load() } catch { self.error = error.localizedDescription } }
}

private struct EmailRecordsView: View {
    @State private var kind = "logs"; @State private var status = "all"; @State private var logResponse: EmailLogsResponse?; @State private var commandResponse: EmailCommandsResponse?; @State private var offset = 0; @State private var loading = true; @State private var error: String?; private let limit = 50
    var total: Int { kind == "logs" ? logResponse?.total ?? 0 : commandResponse?.total ?? 0 }
    var body: some View { List {
        Section { Picker("记录", selection: $kind) { Text("发信日志").tag("logs"); Text("邮件指令").tag("commands") }.pickerStyle(.segmented); if kind == "logs" { Picker("状态", selection: $status) { Text("全部").tag("all"); Text("排队中").tag("queued"); Text("已发送").tag("sent"); Text("失败").tag("failed") } } }
        if kind == "logs", let rows = logResponse?.items { Section("共 \(logResponse?.total ?? 0) 条") { ForEach(rows) { row in VStack(alignment: .leading, spacing: 4) { HStack { Text(row.subject ?? row.template ?? "无主题").font(.subheadline.weight(.medium)); Spacer(); Text(adminSystemLabel(row.status)).font(.caption).foregroundStyle(row.status == "failed" ? .red : .secondary) }; Text("收件人：\(row.to)").font(.caption).foregroundStyle(.secondary); if let provider = row.provider { Text("服务商：\(provider)").font(.caption2).foregroundStyle(.tertiary) }; if let message = row.error { Text(message).font(.caption).foregroundStyle(.red) }; Text(row.sentAt ?? row.createdAt ?? "").font(.caption2).foregroundStyle(.tertiary) } } } }
        if kind == "commands", let rows = commandResponse?.items { Section("共 \(commandResponse?.total ?? 0) 条") { ForEach(rows) { row in VStack(alignment: .leading, spacing: 4) { HStack { Text(row.command ?? row.subject ?? "无指令").font(.subheadline.weight(.medium)); Spacer(); Text(adminSystemLabel(row.status)).font(.caption).foregroundStyle(.secondary) }; Text("来自：\(row.from)").font(.caption).foregroundStyle(.secondary); if let type = row.relatedType { Text("关联：\(adminCompositeSystemLabel(type)) #\(row.relatedId.map(String.init) ?? "—")").font(.caption2).foregroundStyle(.tertiary) }; Text(row.processedAt ?? row.createdAt ?? "").font(.caption2).foregroundStyle(.tertiary) } } } }
        if total > limit { Section { AdminRankingPager(offset: $offset, limit: limit, total: total) } }; if loading { ProgressView() }; if !loading && total == 0 { Text("暂无记录").foregroundStyle(.secondary) }; if let error { Text(error).foregroundStyle(.red) }
    }.task(id: "\(kind)|\(status)|\(offset)") { await load() }.onChange(of: kind) { _ in offset = 0 }.onChange(of: status) { _ in offset = 0 } }
    @MainActor private func load() async { loading = true; do { if kind == "logs" { var query = [URLQueryItem(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset))]; if status != "all" { query.append(.init(name: "status", value: status)) }; logResponse = try await APIClient.shared.get("api/admin/settings/email-logs", query: query) } else { commandResponse = try await APIClient.shared.get("api/admin/settings/email-commands", query: [.init(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset))]) }; error = nil } catch { self.error = error.localizedDescription }; loading = false }
}

private struct SiteSettingsResponse: Codable, Sendable { let items: [SiteSetting] }
private struct SiteSetting: Codable, Identifiable, Sendable { var id: String { key }; let key: String; let value: String?; let type: String; let category: String?; let description: String? }
private struct SiteSettingsBody: Encodable, Sendable { struct Item: Encodable, Sendable { let key: String; let value: String }; let items: [Item] }
private struct SettingsSaveResponse: Codable, Sendable { let ok: Bool; let updated: Int }
private struct WatermarkResponse: Codable, Sendable { let watermark: WatermarkSettings? }
private struct WatermarkSettings: Codable, Sendable { var enabled: Bool; var type: String; var textContent: String; var position: String; var opacity: Int; var fontSize: Int; var color: String; var margin: Int; static let defaults = Self(enabled: true, type: "text", textContent: "", position: "bottom_right", opacity: 60, fontSize: 24, color: "#FFFFFF", margin: 20) }
private struct WatermarkBody: Encodable, Sendable { let enabled: Bool; let type: String; let text_content: String; let position: String; let opacity: Int; let font_size: Int; let color: String; let margin: Int }
private struct WarningRulesResponse: Codable, Sendable { struct Item: Codable, Sendable { let pointsThreshold: Int; let action: String; let durationDays: Int?; let description: String?; let active: Bool }; let items: [Item] }
private struct WarningRule: Identifiable { let id: UUID; var pointsThreshold: Int; var action: String; var durationDays: Int; var description: String?; var active: Bool }
private struct WarningRulesBody: Encodable, Sendable { struct Row: Encodable, Sendable { let points_threshold: Int; let action: String; let duration_days: Int?; let description: String?; let active: Bool }; let rows: [Row] }
private struct EmailLogsResponse: Codable, Sendable { let total: Int; let items: [EmailLog] }
private struct EmailLog: Codable, Identifiable, Sendable { let id: Int; let to: String; let subject: String?; let template: String?; let status: String; let provider: String?; let error: String?; let sentAt: String?; let createdAt: String? }
private struct EmailCommandsResponse: Codable, Sendable { let total: Int; let items: [EmailCommand] }
private struct EmailCommand: Codable, Identifiable, Sendable { let id: Int; let from: String; let subject: String?; let command: String?; let status: String; let relatedType: String?; let relatedId: Int?; let processedAt: String?; let createdAt: String? }
