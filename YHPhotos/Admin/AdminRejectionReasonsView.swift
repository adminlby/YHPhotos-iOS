import SwiftUI

private struct ManagedRejectionReason: Codable, Identifiable, Sendable {
    let id: Int
    let code: String?
    let title: String
    let content: String?
    let category: String?
    let scope: [String]
    let sortOrder: Int
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id, code, title, content, category, scope, active
        case sortOrder = "sort_order"
    }
}

private struct ManagedRejectionReasonsResponse: Decodable, Sendable {
    let items: [ManagedRejectionReason]
    let scopes: [String]
}

private struct ManagedRejectionReasonBody: Encodable, Sendable {
    let title: String
    let content: String?
    let code: String?
    let category: String?
    let scope: [String]
    let sortOrder: Int
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case title, content, code, category, scope, active
        case sortOrder = "sort_order"
    }
}

struct AdminRejectionReasonsView: View {
    @State private var items: [ManagedRejectionReason] = []
    @State private var filter = "all"
    @State private var editing: ManagedRejectionReason?
    @State private var creating = false
    @State private var deleting: ManagedRejectionReason?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var shown: [ManagedRejectionReason] {
        filter == "all" ? items : items.filter { $0.scope.contains(filter) }
    }

    var body: some View {
        List {
            Section {
                Picker("使用场景", selection: $filter) {
                    Text("全部").tag("all")
                    Text("初审 / 驳回").tag("first")
                    Text("申诉").tag("appeal")
                    Text("管理").tag("admin")
                }
                .pickerStyle(.segmented)
            }

            Section("共 \(shown.count) 条") {
                ForEach(shown) { reason in
                    Button { editing = reason } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(reason.title).font(.headline).foregroundStyle(.primary)
                                Spacer()
                                Text(reason.active ? "启用" : "停用")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(reason.active ? .green : .secondary)
                            }
                            if let content = reason.content, !content.isEmpty {
                                Text(content).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                            }
                            HStack(spacing: 6) {
                                ForEach(reason.scope, id: \.self) { scope in
                                    Text(scopeTitle(scope))
                                        .font(.caption2)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(scopeColor(scope).opacity(0.12), in: Capsule())
                                        .foregroundStyle(scopeColor(scope))
                                }
                                Spacer()
                                if let category = reason.category { Text(category).font(.caption).foregroundStyle(.secondary) }
                                Text("#\(reason.sortOrder)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) { deleting = reason }
                    }
                }
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
            } else if let errorMessage {
                EmptyStateView("驳回理由加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else if shown.isEmpty {
                EmptyStateView("暂无驳回理由", systemImage: "nosign", description: "点右上角添加预设理由")
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("驳回理由")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新建驳回理由")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: Binding(
            get: { creating || editing != nil },
            set: { if !$0 { creating = false; editing = nil } }
        ), onDismiss: { Task { await load() } }) {
            NavigationStack {
                AdminRejectionReasonEditor(reason: editing)
            }
        }
        .confirmationDialog(
            "删除驳回理由“\(deleting?.title ?? "")”？历史审核记录不受影响。",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let deleting else { return }
                Task { await delete(deleting) }
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: ManagedRejectionReasonsResponse = try await APIClient.shared.get("api/admin/review/reasons")
            items = response.items
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func delete(_ reason: ManagedRejectionReason) async {
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/review/reasons/\(reason.id)", method: "DELETE")
            deleting = nil
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminRejectionReasonEditor: View {
    @Environment(\.dismiss) private var dismiss
    let reason: ManagedRejectionReason?

    @State private var title: String
    @State private var content: String
    @State private var code: String
    @State private var category: String
    @State private var scopes: Set<String>
    @State private var sortOrder: Int
    @State private var active: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(reason: ManagedRejectionReason?) {
        self.reason = reason
        _title = State(initialValue: reason?.title ?? "")
        _content = State(initialValue: reason?.content ?? "")
        _code = State(initialValue: reason?.code ?? "")
        _category = State(initialValue: reason?.category ?? "")
        _scopes = State(initialValue: Set(reason?.scope ?? ["first"]))
        _sortOrder = State(initialValue: reason?.sortOrder ?? 0)
        _active = State(initialValue: reason?.active ?? true)
    }

    var body: some View {
        Form {
            Section("内容") {
                TextField("标题（必填）", text: $title)
                TextField("详细说明（展示给用户）", text: $content, axis: .vertical).lineLimit(3...8)
            }
            Section("使用场景") {
                scopeToggle("初审 / 驳回", key: "first")
                scopeToggle("申诉", key: "appeal")
                scopeToggle("管理", key: "admin")
            }
            Section("分类与排序") {
                TextField("分类", text: $category)
                TextField("代码 code", text: $code)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Stepper("排序：\(sortOrder)", value: $sortOrder, in: -10_000...10_000)
                Toggle("启用", isOn: $active)
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle(reason == nil ? "新建驳回理由" : "编辑驳回理由")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { await save() } }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scopes.isEmpty)
            }
        }
    }

    private func scopeToggle(_ label: String, key: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { scopes.contains(key) },
            set: { enabled in if enabled { scopes.insert(key) } else { scopes.remove(key) } }
        ))
    }

    @MainActor private func save() async {
        isSaving = true
        defer { isSaving = false }
        let body = ManagedRejectionReasonBody(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: cleaned(content), code: cleaned(code), category: cleaned(category),
            scope: ["first", "appeal", "admin"].filter(scopes.contains),
            sortOrder: sortOrder, active: active
        )
        do {
            let _: AdminActionResponse
            if let reason {
                let result: AdminActionResponse = try await APIClient.shared.send(
                    "api/admin/review/reasons/\(reason.id)", method: "PUT", body: body
                )
                _ = result
            } else {
                let result: AdminActionResponse = try await APIClient.shared.send("api/admin/review/reasons", body: body)
                _ = result
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func cleaned(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

private func scopeTitle(_ scope: String) -> String {
    switch scope { case "first": "初审 / 驳回"; case "appeal": "申诉"; case "admin": "管理"; default: scope }
}

private func scopeColor(_ scope: String) -> Color {
    switch scope { case "first": .red; case "appeal": .blue; case "admin": .purple; default: .secondary }
}
