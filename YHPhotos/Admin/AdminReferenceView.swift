import MapKit
import SwiftUI

struct AdminReferenceView: View {
    let identity: AdminIdentity
    @State private var kind = "aircraft-type"
    @State private var query = ""
    @State private var response: ReferenceResponse?
    @State private var editor: ReferenceEditorState?
    @State private var importing = false
    @State private var deletingID: Int?
    @State private var registrationTools: RegistrationToolState?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    var body: some View {
        List {
            Section {
                Picker("字典", selection: $kind) { ForEach(referenceKinds, id: \.key) { Text($0.name).tag($0.key) } }
                Button("新建\(kindName(kind))", systemImage: "plus.circle.fill") { if let response { editor = ReferenceEditorState(row: nil, response: response) } }
                if identity.can("reference.import") { Button("批量导入结构化数据", systemImage: "square.and.arrow.down") { importing = true } }
                if identity.can("reference.backfill") { Button("存量外键回填", systemImage: "arrow.triangle.2.circlepath") { Task { await backfill() } } }
            }
            if let response {
                Section("共 \(response.total) 条") {
                    ForEach(Array(response.items.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(row[response.nameCol]?.display ?? "#\(row["id"]?.display ?? "")").font(.subheadline.weight(.semibold)); Spacer(); Text("#\(row["id"]?.display ?? "")").font(.caption.monospaced()).foregroundStyle(.secondary) }
                            let details = response.columns.filter { $0 != response.nameCol }.prefix(4).compactMap { column -> String? in guard let value = row[column]?.display, !value.isEmpty else { return nil }; return "\(columnLabel(column)): \(referenceDisplayValue(value, column: column))" }
                            if !details.isEmpty { Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                            HStack {
                                if kind == "registration", let id = row["id"]?.intValue { Button("运营人", systemImage: "building.2") { registrationTools = RegistrationToolState(id: id, title: row[response.nameCol]?.display ?? "#\(id)", tab: .operators) }; Button("事件", systemImage: "calendar") { registrationTools = RegistrationToolState(id: id, title: row[response.nameCol]?.display ?? "#\(id)", tab: .events) } }
                                Button("编辑", systemImage: "pencil") { editor = ReferenceEditorState(row: row, response: response) }
                                if let id = row["id"]?.intValue { Button("删除", systemImage: "trash", role: .destructive) { deletingID = id } }
                            }.font(.caption)
                        }.padding(.vertical, 3)
                    }
                }
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            else if let errorMessage { EmptyStateView("字典加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await load() } } }.listRowBackground(Color.clear) }
            else if response?.items.isEmpty == true { EmptyStateView("暂无字典数据", systemImage: "books.vertical").listRowBackground(Color.clear) }
            if let resultMessage { Section { Text(resultMessage).font(.caption).foregroundStyle(.secondary) } }
        }
        .navigationTitle("参考字典库")
        .searchable(text: $query, prompt: "搜索当前字典")
        .task(id: "\(kind)|\(query)") { await load() }
        .refreshable { await load() }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { AdminReferenceEditor(kind: kind, state: $0) }
        .sheet(isPresented: $importing, onDismiss: { Task { await load() } }) { AdminReferenceImporter(kind: kind) }
        .sheet(item: $registrationTools) { state in AdminRegistrationToolsView(state: state) }
        .confirmationDialog("确认删除该字典条目？若已被图片引用，服务端将阻止删除。", isPresented: Binding(get: { deletingID != nil }, set: { if !$0 { deletingID = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let id = deletingID { Task { await delete(id) } } }; Button("取消", role: .cancel) {}
        }
        .onChange(of: kind) { _ in response = nil; query = "" }
    }

    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { response = try await APIClient.shared.get("api/admin/reference/\(kind)", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "offset", value: "0")]) } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func delete(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/reference/\(kind)/\(id)", method: "DELETE"); deletingID = nil; await load() } catch { errorMessage = error.localizedDescription } }
    @MainActor private func backfill() async { do { let value: ReferenceBackfillResponse = try await APIClient.shared.send("api/admin/reference/backfill", method: "POST"); let filled = value.result.filter { $0.filled > 0 }; resultMessage = filled.isEmpty ? "回填完成，没有新增匹配" : filled.map { "\($0.field) \($0.filled)" }.joined(separator: "，") } catch { errorMessage = error.localizedDescription } }
}

private struct AdminReferenceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let kind: String; let state: ReferenceEditorState
    @State private var values: [String: String]
    @State private var picker: ReferencePickerState?
    @State private var mapPicker = false
    @State private var busy = false
    @State private var errorMessage: String?

    init(kind: String, state: ReferenceEditorState) {
        self.kind = kind; self.state = state
        var initial: [String: String] = [:]
        for column in state.response.columns { initial[column] = state.row?[column]?.display ?? ((kind == "registration" && column == "status") ? "active" : "") }
        _values = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            Form {
                ForEach(state.response.columns, id: \.self) { column in
                    if let targetKind = targetKind(for: column) {
                        Section(columnLabel(column)) {
                            Button { picker = ReferencePickerState(column: column, kind: targetKind) } label: { HStack { Text(values["\(column)__label"] ?? state.row?["\(column)__label"]?.display ?? (values[column].flatMap { $0.isEmpty ? nil : "#\($0)" } ?? "请选择")); Spacer(); Image(systemName: "chevron.right") } }
                            if !(values[column] ?? "").isEmpty { Button("清除关联", role: .destructive) { values[column] = ""; values["\(column)__label"] = "" } }
                        }
                    } else if column == "description" || column == "notes" {
                        Section(columnLabel(column)) { TextEditor(text: binding(column)).frame(minHeight: 90) }
                    } else if kind == "registration", column == "status" {
                        Picker(columnLabel(column), selection: binding(column)) { ForEach(aircraftStatuses, id: \.key) { Text($0.name).tag($0.key) } }
                    } else if let choices = referenceChoices(kind: kind, column: column) {
                        Picker(columnLabel(column), selection: binding(column)) {
                            Text("请选择").tag("")
                            ForEach(choices, id: \.key) { Text($0.name).tag($0.key) }
                        }
                    } else if column == "active" || column == "is_special_livery" {
                        Toggle(columnLabel(column), isOn: Binding(get: { values[column] == "1" || values[column]?.lowercased() == "true" }, set: { values[column] = $0 ? "1" : "0" }))
                    } else {
                        TextField(columnLabel(column), text: binding(column), axis: .vertical)
                            .keyboardType(state.response.intCols.contains(column) ? .numberPad : (column == "latitude" || column == "longitude" ? .decimalPad : .default))
                    }
                }
                if kind == "airport", state.response.columns.contains("latitude") { Section { Button("在地图上选取经纬度", systemImage: "map") { mapPicker = true } } }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(state.row == nil ? "新建\(kindName(kind))" : "编辑\(kindName(kind))").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled((values[state.response.nameCol] ?? "").trimmingCharacters(in: .whitespaces).isEmpty || busy) } }
            .sheet(item: $picker) { target in AdminReferencePicker(kind: target.kind) { id, name in values[target.column] = String(id); values["\(target.column)__label"] = name; picker = nil } }
            .sheet(isPresented: $mapPicker) { CoordinatePickerView(latitude: Double(values["latitude"] ?? ""), longitude: Double(values["longitude"] ?? "")) { lat, lon in values["latitude"] = String(format: "%.7f", lat); values["longitude"] = String(format: "%.7f", lon); mapPicker = false } }
        }
    }
    private func binding(_ column: String) -> Binding<String> { Binding(get: { values[column] ?? "" }, set: { values[column] = $0 }) }
    @MainActor private func save() async {
        busy = true; defer { busy = false }
        var body: [String: ReferenceValue] = [:]
        for column in state.response.columns { let raw = values[column] ?? ""; if state.response.intCols.contains(column), let value = Int(raw) { body[column] = .number(Double(value)) } else { body[column] = raw.isEmpty ? .null : .string(raw) } }
        do { let _: ReferenceMutationResponse; if let id = state.row?["id"]?.intValue { _ = try await APIClient.shared.send("api/admin/reference/\(kind)/\(id)", method: "PUT", body: body) as ReferenceMutationResponse } else { _ = try await APIClient.shared.send("api/admin/reference/\(kind)", body: body) as ReferenceMutationResponse }; dismiss() } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminReferencePicker: View {
    @Environment(\.dismiss) private var dismiss
    let kind: String; let select: (Int, String) -> Void
    @State private var query = ""; @State private var response: ReferenceResponse?; @State private var errorMessage: String?
    var body: some View { NavigationStack { List { if let response { ForEach(Array(response.items.enumerated()), id: \.offset) { _, row in if let id = row["id"]?.intValue { Button { select(id, row[response.nameCol]?.display ?? "#\(id)"); dismiss() } label: { VStack(alignment: .leading) { Text(row[response.nameCol]?.display ?? "#\(id)"); Text("#\(id)").font(.caption).foregroundStyle(.secondary) } } } } }; if let errorMessage { Text(errorMessage).foregroundStyle(.red) } }.searchable(text: $query).navigationTitle("选择\(kindName(kind))").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }.task(id: query) { await load() } } }
    @MainActor private func load() async { do { response = try await APIClient.shared.get("api/admin/reference/\(kind)", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "100")]); errorMessage = nil } catch { errorMessage = error.localizedDescription } }
}

private struct AdminReferenceImporter: View {
    @Environment(\.dismiss) private var dismiss; let kind: String
    @State private var text = ""; @State private var busy = false; @State private var errorMessage: String?; @State private var resultMessage: String?
    var body: some View { NavigationStack { Form { Section { TextEditor(text: $text).font(.system(.caption, design: .monospaced)).frame(minHeight: 220) } header: { Text("数据数组") } footer: { Text("内容使用结构化数据格式及服务端字段名；单次最多 5000 条。") }; if let resultMessage { Section { Text(resultMessage).foregroundStyle(.green) } }; if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } } }.navigationTitle("批量导入 · \(kindName(kind))").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("导入") { Task { await run() } }.disabled(text.isEmpty || busy) } } } }
    @MainActor private func run() async { busy = true; defer { busy = false }; do { guard let data = text.data(using: .utf8) else { throw APIClientError.invalidResponse }; let rows = try JSONDecoder().decode([[String: ReferenceValue]].self, from: data); let result: ReferenceImportResponse = try await APIClient.shared.send("api/admin/reference/\(kind)/import", body: ReferenceImportBody(rows: rows)); resultMessage = "已导入 \(result.imported) 条，跳过 \(result.skipped) 条"; errorMessage = nil } catch { errorMessage = error.localizedDescription } }
}

// MARK: - Registration operator and event history

private struct AdminRegistrationToolsView: View {
    let state: RegistrationToolState
    @State private var tab: RegistrationToolTab
    init(state: RegistrationToolState) { self.state = state; _tab = State(initialValue: state.tab) }
    var body: some View { NavigationStack { VStack(spacing: 0) { Picker("资料", selection: $tab) { Text("历任运营人").tag(RegistrationToolTab.operators); Text("飞机事件").tag(RegistrationToolTab.events) }.pickerStyle(.segmented).padding(); if tab == .operators { OperatorHistoryView(registrationID: state.id) } else { AircraftEventsView(registrationID: state.id) } }.navigationTitle(state.title).navigationBarTitleDisplayMode(.inline) } }
}

private struct OperatorHistoryView: View {
    let registrationID: Int
    @State private var response: OperatorHistoryResponse?; @State private var editor: OperatorEditorState?; @State private var errorMessage: String?
    var body: some View { List { if response?.ready == false { Section { Label("需先应用注册号档案数据库迁移", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }; Section { Button("添加运营人记录", systemImage: "plus") { editor = OperatorEditorState(item: nil) } }; ForEach(Array((response?.items ?? []).enumerated()), id: \.element.id) { index, item in VStack(alignment: .leading, spacing: 5) { HStack { Text(item.airline ?? "未命名航司").font(.headline); Spacer(); Menu { Button("编辑") { editor = OperatorEditorState(item: item) }; Button("删除", role: .destructive) { Task { await delete(item.id) } } } label: { Image(systemName: "ellipsis.circle") } }; Text("\(item.startDate ?? "未知") – \(item.endDate ?? "至今")").font(.caption).foregroundStyle(.secondary); if let remark = item.remark { Text(remark).font(.caption) }; HStack { Button("上移") { Task { await move(index, -1) } }.disabled(index == 0); Button("下移") { Task { await move(index, 1) } }.disabled(index == (response?.items.count ?? 0) - 1) }.font(.caption) }.padding(.vertical, 3) }; if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } } }.task { await load() }.refreshable { await load() }.sheet(item: $editor, onDismiss: { Task { await load() } }) { OperatorEditorView(registrationID: registrationID, state: $0) } }
    @MainActor private func load() async { do { response = try await APIClient.shared.get("api/admin/registration/\(registrationID)/operators"); errorMessage = nil } catch { errorMessage = error.localizedDescription } }
    @MainActor private func delete(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/registration/operators/\(id)", method: "DELETE"); await load() } catch { errorMessage = error.localizedDescription } }
    @MainActor private func move(_ index: Int, _ delta: Int) async { guard var items = response?.items, items.indices.contains(index + delta) else { return }; items.swapAt(index, index + delta); do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/registration/\(registrationID)/operators/order", method: "PUT", body: ReferenceOrderBody(ids: items.map(\.id))); response = OperatorHistoryResponse(ready: true, items: items) } catch { errorMessage = error.localizedDescription } }
}

private struct OperatorEditorView: View {
    @Environment(\.dismiss) private var dismiss; let registrationID: Int; let state: OperatorEditorState
    @State private var airlineID: String; @State private var airlineText: String; @State private var startDate: String; @State private var endDate: String; @State private var remark: String; @State private var picker = false; @State private var errorMessage: String?
    init(registrationID: Int, state: OperatorEditorState) { self.registrationID = registrationID; self.state = state; _airlineID = State(initialValue: state.item?.airlineId.map(String.init) ?? ""); _airlineText = State(initialValue: state.item?.airlineText ?? state.item?.airline ?? ""); _startDate = State(initialValue: state.item?.startDate ?? ""); _endDate = State(initialValue: state.item?.endDate ?? ""); _remark = State(initialValue: state.item?.remark ?? "") }
    var body: some View { NavigationStack { Form { Section("航司") { Button(airlineText.isEmpty ? "选择航司" : airlineText) { picker = true }; TextField("或填写航司自由文本", text: $airlineText) }; Section("任期") { TextField("开始日期 YYYY-MM-DD", text: $startDate); TextField("结束日期，留空表示至今", text: $endDate); TextField("备注", text: $remark, axis: .vertical) }; if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } } }.navigationTitle(state.item == nil ? "添加运营人" : "编辑运营人").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(airlineID.isEmpty && airlineText.trimmingCharacters(in: .whitespaces).isEmpty) } }.sheet(isPresented: $picker) { AdminReferencePicker(kind: "airline") { id, name in airlineID = String(id); airlineText = name; picker = false } } } }
    @MainActor private func save() async { do { let body = OperatorBody(airline_id: Int(airlineID), airline_text: airlineText.isEmpty ? nil : airlineText, start_date: startDate.isEmpty ? nil : startDate, end_date: endDate.isEmpty ? nil : endDate, remark: remark.isEmpty ? nil : remark); let _: ReferenceMutationResponse; if let id = state.item?.id { _ = try await APIClient.shared.send("api/admin/registration/operators/\(id)", method: "PUT", body: body) as ReferenceMutationResponse } else { _ = try await APIClient.shared.send("api/admin/registration/\(registrationID)/operators", body: body) as ReferenceMutationResponse }; dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct AircraftEventsView: View {
    let registrationID: Int
    @State private var items: [AircraftEvent] = []; @State private var editor: AircraftEventEditorState?; @State private var errorMessage: String?
    var body: some View { List { Section { Button("添加飞机事件", systemImage: "plus") { editor = AircraftEventEditorState(item: nil) } }; ForEach(items) { item in VStack(alignment: .leading, spacing: 5) { HStack { Text(item.title).font(.headline); Spacer(); Menu { Button("编辑") { editor = AircraftEventEditorState(item: item) }; Button("删除", role: .destructive) { Task { await delete(item.id) } } } label: { Image(systemName: "ellipsis.circle") } }; Text("\(eventName(item.eventType)) · \(item.eventDate ?? "日期待考")\(item.endDate.map { " 至 \($0)" } ?? "") · 可信度 \(item.confidence)%").font(.caption).foregroundStyle(.secondary); if let description = item.description { Text(description).font(.caption) } }.padding(.vertical, 3) }; if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } } }.task { await load() }.refreshable { await load() }.sheet(item: $editor, onDismiss: { Task { await load() } }) { AircraftEventEditorView(registrationID: registrationID, state: $0) } }
    @MainActor private func load() async { do { let response: AircraftEventsResponse = try await APIClient.shared.get("api/admin/registration/\(registrationID)/events"); items = response.items; errorMessage = nil } catch { errorMessage = error.localizedDescription } }
    @MainActor private func delete(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/registration/events/\(id)", method: "DELETE"); await load() } catch { errorMessage = error.localizedDescription } }
}

private struct AircraftEventEditorView: View {
    @Environment(\.dismiss) private var dismiss; let registrationID: Int; let state: AircraftEventEditorState
    @State private var type: String; @State private var eventDate: String; @State private var endDate: String; @State private var title: String; @State private var description: String; @State private var previous: String; @State private var next: String; @State private var source: String; @State private var confidence: Int; @State private var errorMessage: String?
    init(registrationID: Int, state: AircraftEventEditorState) { self.registrationID = registrationID; self.state = state; let item = state.item; _type = State(initialValue: item?.eventType ?? "livery"); _eventDate = State(initialValue: item?.eventDate ?? ""); _endDate = State(initialValue: item?.endDate ?? ""); _title = State(initialValue: item?.title ?? ""); _description = State(initialValue: item?.description ?? ""); _previous = State(initialValue: item?.previousRegistration ?? ""); _next = State(initialValue: item?.newRegistration ?? ""); _source = State(initialValue: item?.sourceUrl ?? ""); _confidence = State(initialValue: item?.confidence ?? 100) }
    var body: some View { NavigationStack { Form { Picker("事件类型", selection: $type) { ForEach(eventTypes, id: \.key) { Text($0.name).tag($0.key) } }; TextField("发生日期 YYYY-MM-DD", text: $eventDate); TextField("结束日期（可选）", text: $endDate); TextField("事件标题", text: $title); TextField("事件说明", text: $description, axis: .vertical).lineLimit(3...6); if type == "registration" { TextField("原注册号", text: $previous); TextField("新注册号", text: $next) }; TextField("资料来源链接", text: $source).textInputAutocapitalization(.never); Picker("可信度", selection: $confidence) { Text("100% 已确认").tag(100); Text("80% 较可信").tag(80); Text("60% 待核实").tag(60); Text("40% 线索").tag(40) }; if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } } }.navigationTitle(state.item == nil ? "添加事件" : "编辑事件").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) } } } }
    @MainActor private func save() async { do { let body = AircraftEventBody(event_type: type, event_date: eventDate.isEmpty ? nil : eventDate, end_date: endDate.isEmpty ? nil : endDate, title: title, description: description.isEmpty ? nil : description, previous_registration: previous.isEmpty ? nil : previous, new_registration: next.isEmpty ? nil : next, source_url: source.isEmpty ? nil : source, confidence: confidence); let _: ReferenceMutationResponse; if let id = state.item?.id { _ = try await APIClient.shared.send("api/admin/registration/events/\(id)", method: "PUT", body: body) as ReferenceMutationResponse } else { _ = try await APIClient.shared.send("api/admin/registration/\(registrationID)/events", body: body) as ReferenceMutationResponse }; dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct CoordinatePickerView: View {
    @Environment(\.dismiss) private var dismiss; @State private var coordinate: CLLocationCoordinate2D; let select: (Double, Double) -> Void
    init(latitude: Double?, longitude: Double?, select: @escaping (Double, Double) -> Void) { _coordinate = State(initialValue: CLLocationCoordinate2D(latitude: latitude ?? 35, longitude: longitude ?? 105)); self.select = select }
    var body: some View { NavigationStack { CoordinateMapView(coordinate: $coordinate).ignoresSafeArea(edges: .bottom).navigationTitle("地图选点").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("使用此坐标") { select(coordinate.latitude, coordinate.longitude); dismiss() } } }.safeAreaInset(edge: .bottom) { Text(String(format: "纬度 %.7f · 经度 %.7f", coordinate.latitude, coordinate.longitude)).font(.caption.monospaced()).padding(10).frame(maxWidth: .infinity).background(.bar) } } }
}
private struct CoordinateMapView: UIViewRepresentable { @Binding var coordinate: CLLocationCoordinate2D; func makeCoordinator() -> Coordinator { Coordinator(self) }; func makeUIView(context: Context) -> MKMapView { let map = MKMapView(); map.delegate = context.coordinator; map.setRegion(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)), animated: false); map.addAnnotation(context.coordinator.annotation); let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))); map.addGestureRecognizer(tap); return map }; func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.annotation.coordinate = coordinate }; final class Coordinator: NSObject, MKMapViewDelegate { var parent: CoordinateMapView; let annotation = MKPointAnnotation(); init(_ parent: CoordinateMapView) { self.parent = parent; annotation.coordinate = parent.coordinate }; @objc func tap(_ gesture: UITapGestureRecognizer) { guard let map = gesture.view as? MKMapView else { return }; let value = map.convert(gesture.location(in: map), toCoordinateFrom: map); parent.coordinate = value; annotation.coordinate = value } } }

// MARK: - Reference models

private let referenceKinds = [(key: "aircraft-type", name: "机型"), (key: "airline", name: "航空公司"), (key: "airport", name: "机场"), (key: "registration", name: "注册号"), (key: "train-model", name: "车型"), (key: "bureau", name: "路局"), (key: "line", name: "线路"), (key: "station", name: "车站")]
private let aircraftStatuses = [(key: "active", name: "正常运营"), (key: "maintenance", name: "维修中"), (key: "stored", name: "停场 / 封存"), (key: "retired", name: "退役"), (key: "written_off", name: "失事 / 全损"), (key: "scrapped", name: "拆解 / 报废"), (key: "registration_changed", name: "注册号已变更"), (key: "unknown", name: "状态不明")]
private let eventTypes = [(key: "livery", name: "涂装变化"), (key: "transfer", name: "转场 / 转手"), (key: "registration", name: "注册号变更"), (key: "conversion", name: "客改货 / 改装"), (key: "storage", name: "停场 / 封存"), (key: "retirement", name: "退役"), (key: "scrapped", name: "拆解 / 报废"), (key: "delivery", name: "交付"), (key: "first_flight", name: "首飞"), (key: "operator", name: "运营人变化"), (key: "other", name: "其他")]
private let aircraftCategories = [(key: "narrow_body", name: "窄体客机"), (key: "wide_body", name: "宽体客机"), (key: "regional", name: "支线客机"), (key: "cargo", name: "货机"), (key: "business_jet", name: "公务机"), (key: "general", name: "通用航空器"), (key: "helicopter", name: "直升机"), (key: "military", name: "军用航空器"), (key: "other", name: "其他")]
private let airportTypes = [(key: "airport", name: "机场"), (key: "spotting_point", name: "拍摄点"), (key: "other", name: "其他")]
private let trainCategories = [(key: "emu", name: "动车组"), (key: "locomotive", name: "机车"), (key: "passenger_car", name: "客车"), (key: "freight", name: "货车"), (key: "metro", name: "地铁"), (key: "tram", name: "有轨电车"), (key: "other", name: "其他")]
private let railwayLineTypes = [(key: "high_speed", name: "高速铁路"), (key: "intercity", name: "城际铁路"), (key: "conventional", name: "普速铁路"), (key: "metro", name: "地铁"), (key: "freight", name: "货运铁路"), (key: "other", name: "其他")]
private let referenceColumnLabels: [String: String] = ["icao_code":"ICAO", "iata_code":"IATA", "manufacturer":"制造商", "model":"型号", "name":"名称", "name_en":"英文名", "category":"类别", "engine_count":"发动机数", "typical_seats":"典型座位", "first_flight_year":"首飞年份", "description":"描述", "country":"国家", "callsign":"呼号", "active":"启用", "city":"城市", "province":"省份", "type":"类型", "registration":"注册号", "aircraft_type_id":"机型", "airline_id":"所属航司", "current_operator_id":"当前运营人", "serial_number":"序列号", "line_number":"线号", "status":"状态", "notes":"备注", "code":"代码", "power_type":"动力", "max_speed":"最高速度", "short_name":"简称", "line_type":"线路类型", "bureau_id":"路局", "start_station":"起点", "end_station":"终点", "pinyin":"拼音", "level":"等级", "manufacturing_date":"制造日期", "first_flight":"首飞日期", "delivery_date":"交付日期", "data_source":"数据来源", "is_special_livery":"是否彩绘", "special_livery_name":"彩绘名称", "latitude":"纬度", "longitude":"经度", "elevation":"海拔", "timezone":"时区"]
private func kindName(_ kind: String) -> String { referenceKinds.first { $0.key == kind }?.name ?? kind }
private func columnLabel(_ column: String) -> String { referenceColumnLabels[column] ?? column }
private func referenceDisplayValue(_ value: String, column: String) -> String {
    switch column {
    case "category", "type", "line_type", "status": adminSystemLabel(value)
    case "active", "is_special_livery": (value == "1" || value.lowercased() == "true") ? "是" : "否"
    default: value
    }
}
private func referenceChoices(kind: String, column: String) -> [(key: String, name: String)]? {
    switch (kind, column) {
    case ("aircraft-type", "category"): aircraftCategories
    case ("airport", "type"): airportTypes
    case ("train-model", "category"): trainCategories
    case ("line", "line_type"): railwayLineTypes
    default: nil
    }
}
private func targetKind(for column: String) -> String? { switch column { case "aircraft_type_id": "aircraft-type"; case "airline_id", "current_operator_id": "airline"; case "bureau_id": "bureau"; default: nil } }
private func eventName(_ type: String) -> String { eventTypes.first { $0.key == type }?.name ?? type }

private enum ReferenceValue: Codable, Hashable, Sendable { case string(String), number(Double), bool(Bool), null; init(from decoder: Decoder) throws { let box = try decoder.singleValueContainer(); if box.decodeNil() { self = .null } else if let value = try? box.decode(Bool.self) { self = .bool(value) } else if let value = try? box.decode(Double.self) { self = .number(value) } else { self = .string(try box.decode(String.self)) } }; func encode(to encoder: Encoder) throws { var box = encoder.singleValueContainer(); switch self { case .string(let value): try box.encode(value); case .number(let value): try box.encode(value); case .bool(let value): try box.encode(value); case .null: try box.encodeNil() } }; var display: String { switch self { case .string(let value): value; case .number(let value): value.rounded() == value ? String(Int(value)) : String(value); case .bool(let value): value ? "1" : "0"; case .null: "" } }; var intValue: Int? { switch self { case .number(let value): Int(value); case .string(let value): Int(value); default: nil } } }
private struct ReferenceResponse: Codable, Sendable { let kind: String; let table: String; let nameCol: String; let columns: [String]; let intCols: [String]; let fkCols: [String: String]; let items: [[String: ReferenceValue]]; let total: Int }
private struct ReferenceEditorState: Identifiable { let id = UUID(); let row: [String: ReferenceValue]?; let response: ReferenceResponse }
private struct ReferencePickerState: Identifiable { let id = UUID(); let column: String; let kind: String }
private struct ReferenceMutationResponse: Codable, Sendable { let ok: Bool; let id: Int?; let deleted: Bool? }
private struct ReferenceImportBody: Encodable, Sendable { let rows: [[String: ReferenceValue]] }
private struct ReferenceImportResponse: Codable, Sendable { let imported: Int; let skipped: Int }
private struct ReferenceBackfillResponse: Codable, Sendable { struct Item: Codable, Sendable { let field: String; let ref: String; let filled: Int }; let result: [Item] }

private enum RegistrationToolTab: String, Hashable { case operators, events }
private struct RegistrationToolState: Identifiable { let id: Int; let title: String; let tab: RegistrationToolTab }
private struct OperatorHistoryItem: Codable, Identifiable, Sendable { let id: Int; let airlineId: Int?; let airline: String?; let airlineText: String?; let startDate: String?; let endDate: String?; let remark: String?; let sortOrder: Int }
private struct OperatorHistoryResponse: Codable, Sendable { let ready: Bool; let items: [OperatorHistoryItem] }
private struct OperatorEditorState: Identifiable { let id = UUID(); let item: OperatorHistoryItem? }
private struct OperatorBody: Encodable, Sendable { let airline_id: Int?; let airline_text: String?; let start_date: String?; let end_date: String?; let remark: String? }
private struct ReferenceOrderBody: Encodable, Sendable { let ids: [Int] }
private struct AircraftEvent: Codable, Identifiable, Sendable { let id: Int; let eventType: String; let eventDate: String?; let endDate: String?; let title: String; let description: String?; let previousRegistration: String?; let newRegistration: String?; let sourceUrl: String?; let confidence: Int; enum CodingKeys: String, CodingKey { case id, title, description, confidence; case eventType = "event_type"; case eventDate = "event_date"; case endDate = "end_date"; case previousRegistration = "previous_registration"; case newRegistration = "new_registration"; case sourceUrl = "source_url" } }
private struct AircraftEventsResponse: Codable, Sendable { let items: [AircraftEvent] }
private struct AircraftEventEditorState: Identifiable { let id = UUID(); let item: AircraftEvent? }
private struct AircraftEventBody: Encodable, Sendable { let event_type: String; let event_date: String?; let end_date: String?; let title: String; let description: String?; let previous_registration: String?; let new_registration: String?; let source_url: String?; let confidence: Int }
