import SwiftUI
import UIKit

struct AdminRankingClaimsSections: View {
    let activity: RankingActivity
    @State private var response: RankingClaimConfigResponse?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Section("领奖状态") {
            if let response {
                Label(response.published ? "已发布，配置和获奖名单已锁定" : "尚未发布", systemImage: response.published ? "lock.fill" : "doc.badge.gearshape")
                if let deadline = response.deadline { LabeledContent("登记截止", value: deadline) }
                NavigationLink("奖品与表单配置") { RankingClaimConfigView(activity: activity, initial: response) { Task { await load() } } }
                NavigationLink("登记与发放管理") { RankingClaimManagementView(activity: activity, config: response.config) }
            } else if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red); Button("重试") { Task { await load() } } }
        }.task { await load() }
    }
    @MainActor private func load() async { loading = true; do { response = try await APIClient.shared.get("api/admin/ranking/activities/\(activity.id)/claims/config"); error = nil } catch { self.error = error.localizedDescription }; loading = false }
}

private struct RankingClaimConfigView: View {
    let activity: RankingActivity
    let initial: RankingClaimConfigResponse
    let changed: () -> Void
    @State private var config: RankingClaimConfig
    @State private var groupEditor: ClaimGroupEditorState?
    @State private var fieldEditor: ClaimFieldEditorState?
    @State private var winners: [RankingClaimSnapshot]?
    @State private var busy = false
    @State private var dirty = false
    @State private var confirmPublish = false
    @State private var error: String?

    init(activity: RankingActivity, initial: RankingClaimConfigResponse, changed: @escaping () -> Void) { self.activity = activity; self.initial = initial; self.changed = changed; _config = State(initialValue: initial.config) }
    var body: some View {
        List {
            Section {
                Text(initial.published ? "领奖已发布，配置和获奖数据已锁定。" : "结束活动后核对最终榜单，再预览并发布领奖。同一用户只匹配第一个符合条件的奖励组。")
                if let deadline = initial.deadline { LabeledContent("登记截止", value: deadline) }
                if !initial.published { Button("载入一周年完整示例", systemImage: "doc.on.doc") { config = initial.template; dirty = true; winners = nil } }
            }
            Section("表单") {
                TextField("表单标题", text: $config.title)
                TextField("领奖说明 / 使用范围 / 尺码说明", text: $config.instructions, axis: .vertical).lineLimit(4...10)
                Stepper("发布后登记 \(config.days) 天", value: $config.days, in: 1...365)
            }.onChange(of: config) { _ in if !initial.published { dirty = true; winners = nil } }
            Section("奖励组（按首个匹配生效）") {
                ForEach(Array(config.groups.enumerated()), id: \.element.id) { index, group in
                    Button { groupEditor = .init(index: index, group: group) } label: {
                        VStack(alignment: .leading, spacing: 4) { HStack { Text("\(index + 1). \(group.name)").foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }; Text("排名 \(group.rankMin)～\(group.rankMax.map(String.init) ?? "不限") · 至少 \(group.minApproved) 张 · 固定 ¥\(money(group.fixedCents)) + 每张 ¥\(money(group.perApprovedCents))").font(.caption).foregroundStyle(.secondary); if !group.rewards.isEmpty { Text(group.rewards.joined(separator: "；")).font(.caption2).foregroundStyle(.tertiary) } }
                    }.buttonStyle(.plain).swipeActions { Button("删除", role: .destructive) { deleteGroup(index) }; if index > 0 { Button("上移", systemImage: "arrow.up") { config.groups.swapAt(index, index - 1) }.tint(.blue) } }
                }
                if !initial.published { Button("添加奖励组", systemImage: "plus") { groupEditor = .init(index: nil, group: .new()) } }
            }
            Section("领奖字段") {
                Text("条件来源必须位于当前字段之前；未选择奖励组表示所有奖励组适用。").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(config.fields.enumerated()), id: \.element.key) { index, field in
                    Button { fieldEditor = .init(index: index, field: field, preceding: Array(config.fields.prefix(index)), groups: config.groups) } label: {
                        VStack(alignment: .leading, spacing: 4) { HStack { Text("\(index + 1). \(field.label)").foregroundStyle(.primary); Spacer(); Text(field.typeLabel).font(.caption).foregroundStyle(.secondary) }; Text("key: \(field.key)\(field.required ? " · 必填" : "")\(field.groups.isEmpty ? " · 全部奖励组" : " · " + field.groups.joined(separator: ", "))").font(.caption2).foregroundStyle(.tertiary) }
                    }.buttonStyle(.plain).swipeActions { Button("删除", role: .destructive) { deleteField(index) }; if index > 0 { Button("上移", systemImage: "arrow.up") { config.fields.swapAt(index, index - 1) }.tint(.blue) } }
                }
                if !initial.published { Button("添加字段", systemImage: "plus") { fieldEditor = .init(index: nil, field: .new(), preceding: config.fields, groups: config.groups) } }
            }
            if let winners {
                Section("获奖名单预览 · \(winners.count) 人 · 合计 ¥\(money(winners.reduce(0) { $0 + $1.amountCents }))") {
                    ForEach(winners) { row in VStack(alignment: .leading, spacing: 3) { Text("#\(row.rank) · \(row.displayName ?? "用户 #\(row.userId)")"); Text("\(row.groupName) · \(row.approvedCount) 张 · ¥\(money(row.amountCents))").font(.caption).foregroundStyle(.secondary) } }
                }
            }
            if !initial.published {
                Section("发布") {
                    Button(dirty ? "保存草稿 *" : "保存草稿", systemImage: "square.and.arrow.down") { Task { await save() } }
                    Button("预览获奖名单", systemImage: "person.3.sequence") { Task { await preview() } }.disabled(dirty)
                    Button("发布领奖", systemImage: "paperplane.fill") { confirmPublish = true }.disabled(dirty || winners?.isEmpty != false || activity.status != "ended" && activity.status != "archived")
                    if activity.status != "ended" && activity.status != "archived" { Text("必须先将活动设为“已结束”或“归档”。").font(.caption).foregroundStyle(.orange) }
                }
            }
            if busy { Section { ProgressView() } }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .disabled(initial.published || busy)
        .navigationTitle("奖品与表单")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $groupEditor) { state in ClaimGroupEditor(state: state) { value in if let i = state.index { config.groups[i] = value } else { config.groups.append(value) }; dirty = true } }
        .sheet(item: $fieldEditor) { state in ClaimFieldEditor(state: state) { value in if let i = state.index { config.fields[i] = value } else { config.fields.append(value) }; dirty = true } }
        .confirmationDialog("发布后将锁定奖品、字段及获奖名单，并从现在开始计算登记期限。确定发布？", isPresented: $confirmPublish, titleVisibility: .visible) { Button("发布并生成名单") { Task { await publish() } }; Button("取消", role: .cancel) {} }
    }
    private func deleteGroup(_ index: Int) { let id = config.groups[index].id; guard !config.fields.contains(where: { $0.groups.contains(id) }) else { error = "请先移除字段对该奖励组的引用"; return }; config.groups.remove(at: index); dirty = true }
    private func deleteField(_ index: Int) { let key = config.fields[index].key; guard !config.fields.contains(where: { $0.condition?.field == key }) else { error = "请先移除其他字段对该字段的条件引用"; return }; config.fields.remove(at: index); dirty = true }
    @MainActor private func save() async { busy = true; defer { busy = false }; do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/ranking/activities/\(activity.id)/claims/config", method: "PUT", body: config); dirty = false; error = nil; changed() } catch { self.error = error.localizedDescription } }
    @MainActor private func preview() async { busy = true; defer { busy = false }; do { let r: RankingClaimPreviewResponse = try await APIClient.shared.get("api/admin/ranking/activities/\(activity.id)/claims/preview"); winners = r.items; error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func publish() async { busy = true; defer { busy = false }; do { let r: RankingClaimPublishResponse = try await APIClient.shared.send("api/admin/ranking/activities/\(activity.id)/claims/publish", method: "POST"); error = "已发布，共 \(r.count) 位获奖用户"; changed() } catch { self.error = error.localizedDescription } }
}

private struct ClaimGroupEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: ClaimGroupEditorState; let save: (RankingRewardGroup) -> Void
    @State private var value: RankingRewardGroup
    init(state: ClaimGroupEditorState, save: @escaping (RankingRewardGroup) -> Void) { self.state = state; self.save = save; _value = State(initialValue: state.group) }
    var body: some View { NavigationStack { Form {
        Section("标识") { TextField("标识（小写字母开头）", text: $value.id).textInputAutocapitalization(.never).disabled(state.index != nil); TextField("奖励组名称", text: $value.name) }
        Section("匹配条件") { Stepper("起始排名：\(value.rankMin)", value: $value.rankMin, in: 1...100000); Toggle("限制结束排名", isOn: Binding(get: { value.rankMax != nil }, set: { value.rankMax = $0 ? max(value.rankMin, value.rankMin) : nil })); if value.rankMax != nil { Stepper("结束排名：\(value.rankMax ?? value.rankMin)", value: Binding(get: { value.rankMax ?? value.rankMin }, set: { value.rankMax = $0 }), in: value.rankMin...100000) }; Stepper("最低有效图片：\(value.minApproved)", value: $value.minApproved, in: 0...100000) }
        Section("奖品与奖金") { TextField("奖品（每行一项）", text: Binding(get: { value.rewards.joined(separator: "\n") }, set: { value.rewards = $0.components(separatedBy: .newlines).filter { !$0.isEmpty } }), axis: .vertical).lineLimit(3...8); TextField("固定奖金（分）", value: $value.fixedCents, format: .number).keyboardType(.numberPad); TextField("每张有效图片奖金（分）", value: $value.perApprovedCents, format: .number).keyboardType(.numberPad) }
    }.navigationTitle(state.index == nil ? "添加奖励组" : "编辑奖励组").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { save(value); dismiss() }.disabled(value.id.isEmpty || value.name.trimmingCharacters(in: .whitespaces).isEmpty) } } } }
}

private struct ClaimFieldEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: ClaimFieldEditorState; let save: (RankingClaimField) -> Void
    @State private var value: RankingClaimField
    init(state: ClaimFieldEditorState, save: @escaping (RankingClaimField) -> Void) { self.state = state; self.save = save; _value = State(initialValue: state.field) }
    var body: some View { NavigationStack { Form {
        Section("字段") { TextField("key（小写字母开头）", text: $value.key).textInputAutocapitalization(.never).disabled(state.index != nil); TextField("字段名称", text: $value.label); Picker("类型", selection: $value.type) { Text("短文本").tag("text"); Text("长文本").tag("textarea"); Text("单选").tag("select"); Text("确认勾选").tag("checkbox"); Text("图片上传").tag("image") }; Toggle("必填 / 必须确认", isOn: $value.required); TextField("提示说明", text: $value.help, axis: .vertical).lineLimit(2...6) }
        if value.type == "select" { Section("选项") { TextField("每行一个选项", text: Binding(get: { value.options.joined(separator: "\n") }, set: { value.options = $0.components(separatedBy: .newlines).filter { !$0.isEmpty } }), axis: .vertical).lineLimit(3...9) } }
        if value.type == "text" { Section { Picker("格式校验", selection: $value.validation) { Text("不限").tag("none"); Text("电话号码").tag("phone") } } }
        Section("适用奖励组（不选表示全部）") { ForEach(state.groups) { group in Toggle(group.name, isOn: Binding(get: { value.groups.contains(group.id) }, set: { if $0 { value.groups.append(group.id) } else { value.groups.removeAll { $0 == group.id } } })) } }
        Section("显示条件") {
            Picker("来源字段", selection: Binding(get: { value.condition?.field ?? "" }, set: { key in let parent = state.preceding.first { $0.key == key }; value.condition = parent.map { .init(field: $0.key, equals: $0.type == "checkbox" ? .bool(true) : .string($0.options.first ?? "")) } })) { Text("始终显示").tag(""); ForEach(state.preceding.filter { $0.type == "select" || $0.type == "checkbox" }) { Text($0.label).tag($0.key) } }
            if let condition = value.condition, let parent = state.preceding.first(where: { $0.key == condition.field }) { Picker("等于", selection: Binding(get: { condition.equals.display }, set: { value.condition = .init(field: condition.field, equals: parent.type == "checkbox" ? .bool($0 == "true") : .string($0)) })) { if parent.type == "checkbox" { Text("已确认").tag("true"); Text("未确认").tag("false") } else { ForEach(parent.options, id: \.self) { Text($0).tag($0) } } } }
        }
    }.navigationTitle(state.index == nil ? "添加字段" : "编辑字段").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { if value.type != "text" { value.validation = "none" }; save(value); dismiss() }.disabled(value.key.isEmpty || value.label.trimmingCharacters(in: .whitespaces).isEmpty || value.type == "select" && value.options.isEmpty) } } } }
}

private struct RankingClaimManagementView: View {
    let activity: RankingActivity; let config: RankingClaimConfig
    @State private var response: RankingClaimsResponse?
    @State private var status = "all"; @State private var offset = 0; @State private var selected: RankingClaimRecord?; @State private var exportURL: URL?; @State private var loading = true; @State private var error: String?
    private let limit = 50
    var body: some View { List {
        Section { Picker("状态", selection: $status) { Text("全部状态").tag("all"); ForEach((response?.statuses ?? RankingClaimRecord.statusLabels).sorted(by: { $0.key < $1.key }), id: \.key) { Text($0.value).tag($0.key) } }; Button("导出全部 CSV", systemImage: "square.and.arrow.up") { Task { await export() } }; if let exportURL { ShareLink(item: exportURL) { Label("分享已导出的 CSV", systemImage: "doc.badge.arrow.up") } } }
        if let response { Section("共 \(response.total) 人") { ForEach(response.items) { claim in Button { selected = claim } label: { HStack { VStack(alignment: .leading, spacing: 4) { Text("#\(claim.snapshot.rank) · \(claim.snapshot.displayName ?? "用户 #\(claim.snapshot.userId)")").foregroundStyle(.primary); Text("\(claim.snapshot.groupName) · \(claim.snapshot.approvedCount) 张 · ¥\(money(claim.snapshot.amountCents))").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(claim.statusLabel).font(.caption).foregroundStyle(AppTheme.accent) } }.buttonStyle(.plain) } }; if response.total > limit { Section { AdminRankingPager(offset: $offset, limit: limit, total: response.total) } } }
        if loading { ProgressView() }; if !loading && response?.items.isEmpty == true { Text("暂无领奖记录。发布领奖后会生成获奖名单。").foregroundStyle(.secondary) }; if let error { Text(error).foregroundStyle(.red) }
    }.navigationTitle("登记与发放").navigationBarTitleDisplayMode(.inline).task(id: "\(status)|\(offset)") { await load() }.sheet(item: $selected, onDismiss: { Task { await load() } }) { RankingClaimDetailView(activityID: activity.id, claim: $0, config: config) } }
    @MainActor private func load() async { loading = true; do { response = try await APIClient.shared.get("api/admin/ranking/activities/\(activity.id)/claims", query: [.init(name: "status", value: status), .init(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset))]); error = nil } catch { self.error = error.localizedDescription }; loading = false }
    @MainActor private func export() async { do { let data = try await APIClient.shared.data("api/admin/ranking/activities/\(activity.id)/claims/export"); let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-\(activity.id)-claims.csv"); try data.write(to: url, options: .atomic); exportURL = url; error = nil } catch { self.error = error.localizedDescription } }
}

private struct RankingClaimDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let activityID: Int; let claim: RankingClaimRecord; let config: RankingClaimConfig
    @State private var status: String; @State private var note: String; @State private var receiptID: String?; @State private var busy = false; @State private var error: String?
    init(activityID: Int, claim: RankingClaimRecord, config: RankingClaimConfig) { self.activityID = activityID; self.claim = claim; self.config = config; _status = State(initialValue: claim.status); _note = State(initialValue: claim.adminNote ?? "") }
    var body: some View { NavigationStack { Form {
        Section("获奖信息") { LabeledContent("用户", value: "\(claim.snapshot.displayName ?? "—") (#\(claim.snapshot.userId))"); LabeledContent("排名", value: "#\(claim.snapshot.rank)"); LabeledContent("有效图片", value: String(claim.snapshot.approvedCount)); LabeledContent("奖励组", value: claim.snapshot.groupName); LabeledContent("奖金", value: "¥\(money(claim.snapshot.amountCents))"); Text(claim.snapshot.rewards.isEmpty ? "现金奖金" : claim.snapshot.rewards.joined(separator: "；")) }
        Section("登记内容") { ForEach(config.fields.filter { claim.answers[$0.key] != nil }) { field in VStack(alignment: .leading, spacing: 5) { Text(field.label).font(.caption).foregroundStyle(.secondary); if field.type == "image", case .string(let id) = claim.answers[field.key] { Button("查看私有图片凭证", systemImage: "photo") { receiptID = id } } else { Text(claim.answers[field.key]?.display ?? "—") } } } }
        Section("发放进度") { Picker("状态", selection: $status) { ForEach(([claim.status] + claim.allowedTransitions).uniqued(), id: \.self) { Text(RankingClaimRecord.statusLabels[$0] ?? $0).tag($0) } }; TextField("发放备注（用户可见，可填写物流单号）", text: $note, axis: .vertical).lineLimit(3...8); Button("保存进度") { Task { await save() } }.disabled(busy) }
        if let submitted = claim.submittedAt { Section { LabeledContent("登记时间", value: submitted) } }; if let error { Section { Text(error).foregroundStyle(.red) } }
    }.navigationTitle("核对 / 发放").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }.sheet(item: Binding(get: { receiptID.map(ReceiptState.init) }, set: { receiptID = $0?.id })) { RankingClaimReceiptView(id: $0.id) } } }
    @MainActor private func save() async { busy = true; defer { busy = false }; do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/ranking/activities/\(activityID)/claims/\(claim.id)/status", method: "PUT", body: RankingClaimStatusBody(status: status, note: note)); dismiss() } catch { self.error = error.localizedDescription } }
}

private struct RankingClaimReceiptView: View {
    @Environment(\.dismiss) private var dismiss; let id: String
    @State private var image: UIImage?; @State private var error: String?
    var body: some View { NavigationStack { Group { if let image { ZoomableImageView(image: image).background(.black).ignoresSafeArea(edges: .bottom) } else if let error { EmptyStateView("图片加载失败", systemImage: "exclamationmark.triangle", description: error) } else { ProgressView("正在安全加载…") } }.navigationTitle("领奖图片凭证").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } } }.task { await load() } }
    @MainActor private func load() async { do { let data = try await APIClient.shared.data("api/ranking/claim-files/\(id)"); guard let value = UIImage(data: data) else { throw ClaimReceiptError.invalid }; image = value } catch { self.error = error.localizedDescription } }
}

private func money(_ cents: Int) -> String { String(format: "%.2f", Double(cents) / 100) }
private struct ClaimGroupEditorState: Identifiable { let id = UUID(); let index: Int?; let group: RankingRewardGroup }
private struct ClaimFieldEditorState: Identifiable { let id = UUID(); let index: Int?; let field: RankingClaimField; let preceding: [RankingClaimField]; let groups: [RankingRewardGroup] }
private struct ReceiptState: Identifiable { let id: String }
private enum ClaimReceiptError: LocalizedError { case invalid; var errorDescription: String? { "服务器返回的内容不是有效图片" } }

private struct RankingClaimConfigResponse: Codable, Sendable { let config: RankingClaimConfig; let published: Bool; let deadline: String?; let template: RankingClaimConfig }
private struct RankingClaimConfig: Codable, Hashable, Sendable { var title: String; var instructions: String; var days: Int; var groups: [RankingRewardGroup]; var fields: [RankingClaimField] }
private struct RankingRewardGroup: Codable, Hashable, Identifiable, Sendable { var id: String; var name: String; var rankMin: Int; var rankMax: Int?; var minApproved: Int; var rewards: [String]; var fixedCents: Int; var perApprovedCents: Int; static func new() -> Self { .init(id: "g_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())", name: "新奖励组", rankMin: 1, rankMax: nil, minApproved: 1, rewards: [], fixedCents: 0, perApprovedCents: 0) } }
private struct RankingClaimField: Codable, Hashable, Identifiable, Sendable { var id: String { key }; var key: String; var label: String; var type: String; var required: Bool; var help: String; var options: [String]; var groups: [String]; var condition: RankingClaimCondition?; var validation: String; var typeLabel: String { ["text":"短文本", "textarea":"长文本", "select":"单选", "checkbox":"确认", "image":"图片"][type] ?? type }; static func new() -> Self { .init(key: "f_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())", label: "新字段", type: "text", required: false, help: "", options: [], groups: [], condition: nil, validation: "none") } }
private struct RankingClaimCondition: Codable, Hashable, Sendable { var field: String; var equals: RankingClaimScalar }
private enum RankingClaimScalar: Codable, Hashable, Sendable { case string(String), bool(Bool), number(Double), null; init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); if c.decodeNil() { self = .null } else if let v = try? c.decode(Bool.self) { self = .bool(v) } else if let v = try? c.decode(Double.self) { self = .number(v) } else { self = .string(try c.decode(String.self)) } }; func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); switch self { case .string(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .number(let v): try c.encode(v); case .null: try c.encodeNil() } }; var display: String { switch self { case .string(let v): v; case .bool(let v): v ? "true" : "false"; case .number(let v): String(v); case .null: "—" } } }
private struct RankingClaimPreviewResponse: Codable, Sendable { let items: [RankingClaimSnapshot] }
private struct RankingClaimPublishResponse: Codable, Sendable { let ok: Bool; let count: Int }
private struct RankingClaimsResponse: Codable, Sendable { let items: [RankingClaimRecord]; let total: Int; let statuses: [String: String] }
private struct RankingClaimRecord: Codable, Identifiable, Sendable { let id: Int; let snapshot: RankingClaimSnapshot; let answers: [String: RankingClaimScalar]; let status: String; let statusLabel: String; let adminNote: String?; let submittedAt: String?; static let statusLabels = ["unregistered":"未登记", "registered":"已登记", "verified":"已核验", "pending":"待发奖", "awarded":"已发奖", "production":"待制作", "shipping":"待发货", "shipped":"已发货", "received":"已签收"]; var allowedTransitions: [String] { ["unregistered":[], "registered":["verified"], "verified":["registered", "pending", "production", "shipping"], "pending":["verified", "awarded"], "production":["verified", "shipping"], "shipping":["production", "shipped"], "shipped":["received"], "awarded":[], "received":[]][status] ?? [] } }
private struct RankingClaimSnapshot: Codable, Identifiable, Sendable { var id: Int { userId }; let userId: Int; let displayName: String?; let rank: Int; let approvedCount: Int; let groupId: String; let groupName: String; let rewards: [String]; let amountCents: Int }
private struct RankingClaimStatusBody: Encodable, Sendable { let status: String; let note: String }
private extension Array where Element: Hashable { func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } } }
