import SwiftUI

struct AdminQuotaView: View {
    @State private var rows: [AdminQuotaRow] = []
    @State private var editor: QuotaEditorState?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label("普通上传不限总量，当前仅“单批上限”实际生效；空值或 0 表示不限。每日/待审上限是兼容旧字段。", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("配额规则（按顺序匹配）") {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Button { editor = QuotaEditorState(index: index, row: row) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(row.roleLabel).font(.subheadline.weight(.semibold)).foregroundStyle(.primary); Spacer(); Text(row.maxPerUpload.map { $0 == 0 ? "不限" : "单批 \($0)" } ?? "不限").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent) }
                            if let description = row.description, !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary) }
                            if row.dailyUploadLimit != nil || row.maxPending != nil { Text("兼容字段：每日 \(row.dailyUploadLimit.map(String.init) ?? "—") · 待审 \(row.maxPending.map(String.init) ?? "—")").font(.caption2).foregroundStyle(.tertiary) }
                        }.padding(.vertical, 3)
                    }.buttonStyle(.plain)
                }
                .onDelete { rows.remove(atOffsets: $0); saved = false }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1); saved = false }
                Button("添加规则", systemImage: "plus.circle.fill") { editor = QuotaEditorState(index: nil, row: AdminQuotaRow(role: "", dailyUploadLimit: nil, maxPending: nil, maxPerUpload: 10, description: nil)) }
            }
            Section {
                Button { Task { await save() } } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text(saved ? "已保存" : "保存全部规则") }; Spacer() } }.disabled(isSaving)
            } footer: { Text("“默认”规则用于兜底，其余用户组规则会覆盖默认值。拖动可调整保存顺序。") }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("配额管理")
        .toolbar { EditButton() }
        .task { await load() }.refreshable { await load() }
        .sheet(item: $editor) { state in AdminQuotaRowEditor(state: state) { row in if let index = state.index { rows[index] = row } else { rows.append(row) }; saved = false; editor = nil } }
    }

    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { let response: AdminQuotaResponse = try await APIClient.shared.get("api/admin/settings/quota-rules"); rows = response.items } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func save() async { isSaving = true; errorMessage = nil; saved = false; defer { isSaving = false }; do { let body = AdminQuotaBody(rows: rows.map(\.requestBody)); let _: AdminActionResponse = try await APIClient.shared.send("api/admin/settings/quota-rules", method: "PUT", body: body); saved = true; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminQuotaRowEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: QuotaEditorState
    let onSave: (AdminQuotaRow) -> Void
    @State private var role: String; @State private var maxPerUpload: String; @State private var daily: String; @State private var pending: String; @State private var description: String
    init(state: QuotaEditorState, onSave: @escaping (AdminQuotaRow) -> Void) { self.state = state; self.onSave = onSave; _role = State(initialValue: state.row.role); _maxPerUpload = State(initialValue: state.row.maxPerUpload.map(String.init) ?? ""); _daily = State(initialValue: state.row.dailyUploadLimit.map(String.init) ?? ""); _pending = State(initialValue: state.row.maxPending.map(String.init) ?? ""); _description = State(initialValue: state.row.description ?? "") }
    var body: some View {
        NavigationStack {
            Form {
                Section("匹配") { TextField("角色键，如 default / user", text: $role).textInputAutocapitalization(.never).font(.system(.body, design: .monospaced)) }
                Section("生效规则") { TextField("单批上传上限（空/0=不限）", text: $maxPerUpload).keyboardType(.numberPad) }
                Section("兼容旧字段（当前不参与限额）") { TextField("每日上限", text: $daily).keyboardType(.numberPad); TextField("待审上限", text: $pending).keyboardType(.numberPad) }
                Section("说明") { TextField("可选说明", text: $description, axis: .vertical).lineLimit(2...5) }
            }
            .navigationTitle(state.index == nil ? "添加配额规则" : "编辑配额规则").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("完成") { onSave(AdminQuotaRow(role: role.trimmingCharacters(in: .whitespacesAndNewlines), dailyUploadLimit: Int(daily), maxPending: Int(pending), maxPerUpload: Int(maxPerUpload), description: description.isEmpty ? nil : description)) }.disabled(role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
        }
    }
}

private struct AdminQuotaResponse: Codable, Sendable { let items: [AdminQuotaRow] }
private struct AdminQuotaRow: Codable, Sendable {
    let role: String; let dailyUploadLimit: Int?; let maxPending: Int?; let maxPerUpload: Int?; let description: String?
    var roleLabel: String { switch role { case "default": "默认"; case "user": "普通用户"; case "intern_moderator": "航空实习审核员"; case "moderator": "航空审核员"; case "senior_moderator": "航空高级审核员"; case "railway_intern_moderator": "铁路实习审核员"; case "railway_moderator": "铁路审核员"; case "railway_senior_moderator": "铁路高级审核员"; case "admin": "管理员"; default: role } }
    var requestBody: AdminQuotaRowBody { AdminQuotaRowBody(role: role, daily_upload_limit: dailyUploadLimit, max_pending: maxPending, max_per_upload: maxPerUpload, description: description) }
}
private struct QuotaEditorState: Identifiable { let id = UUID(); let index: Int?; let row: AdminQuotaRow }
private struct AdminQuotaRowBody: Encodable, Sendable { let role: String; let daily_upload_limit: Int?; let max_pending: Int?; let max_per_upload: Int?; let description: String? }
private struct AdminQuotaBody: Encodable, Sendable { let rows: [AdminQuotaRowBody] }
