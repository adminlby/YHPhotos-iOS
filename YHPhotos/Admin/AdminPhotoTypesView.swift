import SwiftUI

struct AdminPhotoTypesView: View {
    @State private var domain = "aviation"
    @State private var items: [AdminPhotoType] = []
    @State private var editor: PhotoTypeEditorState?
    @State private var deleting: AdminPhotoType?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var shown: [AdminPhotoType] { items.filter { $0.domain == domain } }
    var body: some View {
        List {
            Section {
                Picker("领域", selection: $domain) { Text("航空").tag("aviation"); Text("铁路").tag("railway"); Text("模拟飞行").tag("flight_sim") }.pickerStyle(.segmented)
                Button("新建图片类型", systemImage: "plus.circle.fill") { editor = PhotoTypeEditorState(item: nil, domain: domain) }
            }
            Section("\(domainName(domain)) · \(shown.count) 项") {
                ForEach(shown) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(item.labelZh).font(.subheadline.weight(.semibold)); if !item.active { Text("停用").font(.caption2).foregroundStyle(.secondary) } }
                            Text("\(item.value) · 排序 \(item.sortOrder)").font(.caption).foregroundStyle(.secondary)
                            if item.relaxAircraftFields || item.airportOptional { Text([item.relaxAircraftFields ? "放宽飞机字段" : nil, item.airportOptional ? "机场可空" : nil].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.orange) }
                        }
                        Spacer()
                        Menu { Button("编辑", systemImage: "pencil") { editor = PhotoTypeEditorState(item: item, domain: item.domain) }; Button("删除", systemImage: "trash", role: .destructive) { deleting = item } } label: { Image(systemName: "ellipsis.circle") }
                    }.opacity(item.active ? 1 : 0.58)
                }
                if shown.isEmpty, !isLoading { Text("该领域暂无图片类型").foregroundStyle(.secondary) }
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("上传类型")
        .task { await load() }.refreshable { await load() }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { AdminPhotoTypeEditor(state: $0) }
        .confirmationDialog("删除图片类型“\(deleting?.labelZh ?? "")”？已有图片使用时服务端会阻止删除。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }; Button("取消", role: .cancel) { deleting = nil }
        }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { let response: AdminPhotoTypesResponse = try await APIClient.shared.get("api/admin/photo-types"); items = response.items } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func delete(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/photo-types/\(id)", method: "DELETE"); deleting = nil; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct PhotoTypeEditorState: Identifiable { let id = UUID(); let item: AdminPhotoType?; let domain: String }
private struct AdminPhotoTypeEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: PhotoTypeEditorState
    @State private var domain: String; @State private var value: String; @State private var labelZh: String; @State private var labelEn: String; @State private var sortOrder: String; @State private var active: Bool; @State private var relax: Bool; @State private var airportOptional: Bool; @State private var errorMessage: String?; @State private var busy = false
    init(state: PhotoTypeEditorState) { self.state = state; let item = state.item; _domain = State(initialValue: item?.domain ?? state.domain); _value = State(initialValue: item?.value ?? ""); _labelZh = State(initialValue: item?.labelZh ?? ""); _labelEn = State(initialValue: item?.labelEn ?? ""); _sortOrder = State(initialValue: String(item?.sortOrder ?? 10)); _active = State(initialValue: item?.active ?? true); _relax = State(initialValue: item?.relaxAircraftFields ?? false); _airportOptional = State(initialValue: item?.airportOptional ?? false) }
    var body: some View {
        NavigationStack {
            Form {
                Section("标识") { Picker("领域", selection: $domain) { Text("航空").tag("aviation"); Text("铁路").tag("railway"); Text("模拟飞行").tag("flight_sim") }.disabled(state.item != nil); TextField("稳定值（创建后不可修改）", text: $value).disabled(state.item != nil) }
                Section("显示") { TextField("中文名称", text: $labelZh); TextField("英文名称", text: $labelEn); TextField("排序（小在前）", text: $sortOrder).keyboardType(.numberPad); Toggle("在上传页启用", isOn: $active) }
                if domain == "aviation" { Section("航空表单规则") { Toggle("注册号、机型和航司可留空", isOn: $relax); Toggle("机场可留空", isOn: $airportOptional) } }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(state.item == nil ? "新建图片类型" : "编辑图片类型").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(value.trimmingCharacters(in: .whitespaces).isEmpty || labelZh.trimmingCharacters(in: .whitespaces).isEmpty || busy) } }
        }
    }
    @MainActor private func save() async {
        busy = true; defer { busy = false }
        do {
            let common = AdminPhotoTypeUpdateBody(label_zh: labelZh, label_en: labelEn.isEmpty ? nil : labelEn, sort_order: Int(sortOrder) ?? 0, active: active, relax_aircraft_fields: domain == "aviation" && relax, airport_optional: domain == "aviation" && airportOptional)
            if let id = state.item?.id { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/photo-types/\(id)", method: "PUT", body: common) }
            else { let body = AdminPhotoTypeCreateBody(domain: domain, value: value, label_zh: common.label_zh, label_en: common.label_en, sort_order: common.sort_order, active: common.active, relax_aircraft_fields: common.relax_aircraft_fields, airport_optional: common.airport_optional); let _: AdminActionResponse = try await APIClient.shared.send("api/admin/photo-types", body: body) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminPhotoType: Codable, Identifiable, Sendable { let id: Int; let domain: String; let value: String; let labelZh: String; let labelEn: String?; let sortOrder: Int; let active: Bool; let relaxAircraftFields: Bool; let airportOptional: Bool }
private struct AdminPhotoTypesResponse: Codable, Sendable { let items: [AdminPhotoType] }
private struct AdminPhotoTypeUpdateBody: Encodable, Sendable { let label_zh: String; let label_en: String?; let sort_order: Int; let active: Bool; let relax_aircraft_fields: Bool; let airport_optional: Bool }
private struct AdminPhotoTypeCreateBody: Encodable, Sendable { let domain: String; let value: String; let label_zh: String; let label_en: String?; let sort_order: Int; let active: Bool; let relax_aircraft_fields: Bool; let airport_optional: Bool }
