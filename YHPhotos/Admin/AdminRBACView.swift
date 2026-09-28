import SwiftUI

private struct RBACPermission: Decodable, Identifiable, Hashable, Sendable {
    let permKey: String
    let name: String
    let category: String
    let categoryLabel: String
    let description: String
    var id: String { permKey }
}

private struct RBACGroup: Decodable, Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let level: Int
    let system: Bool
    let sortOrder: Int
    let editable: Bool
    let userCount: Int
    var id: String { key }
}

private struct RBACMatrix: Decodable, Sendable {
    let permissions: [RBACPermission]
    let groups: [RBACGroup]
    let roles: [String: [String]]
    let seeded: Bool
    let groupsReady: Bool
}

private struct RBACPermissionsBody: Encodable, Sendable {
    let permissionKeys: [String]
    enum CodingKeys: String, CodingKey { case permissionKeys = "perm_keys" }
}

private struct RBACCreateGroupBody: Encodable, Sendable {
    let key: String
    let name: String
    let level: Int
    let permissionKeys: [String]
    enum CodingKeys: String, CodingKey {
        case key, name, level
        case permissionKeys = "perm_keys"
    }
}

struct AdminRBACView: View {
    @State private var matrix: RBACMatrix?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingCreate = false

    var body: some View {
        List {
            Section {
                Text("创建后台权限组并维护每组的权限。管理员恒为全权；用户级授权与拒绝在用户管理中维护。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let matrix {
                if !matrix.groupsReady {
                    Section {
                        Label("权限组数据表尚未创建，请先应用最新数据库迁移。", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                if !matrix.seeded {
                    Section {
                        Label("权限点尚未初始化，目前不能创建或保存权限组。", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("权限组（\(matrix.groups.count)）") {
                    ForEach(matrix.groups) { group in
                        NavigationLink {
                            RBACGroupPermissionsView(
                                group: group,
                                permissions: matrix.permissions,
                                initialKeys: Set(matrix.roles[group.key] ?? []),
                                canSave: matrix.seeded && matrix.groupsReady,
                                onSaved: { Task { await load() } }
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: group.system ? "lock.shield.fill" : "person.3.fill")
                                    .foregroundStyle(group.editable ? AppTheme.accent : .orange)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.name).font(.headline)
                                    Text("\(group.key) · L\(group.level) · \(group.userCount) 人")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(group.editable ? "可编辑" : "全权")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(group.editable ? .blue : .orange)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
            } else if let errorMessage {
                EmptyStateView("权限矩阵加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("权限管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
                    .disabled(matrix?.seeded != true || matrix?.groupsReady != true)
                    .accessibilityLabel("新建权限组")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await load() } }) {
            NavigationStack { RBACCreateGroupView() }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        do { matrix = try await APIClient.shared.get("api/admin/rbac/matrix") }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct RBACGroupPermissionsView: View {
    let group: RBACGroup
    let permissions: [RBACPermission]
    let initialKeys: Set<String>
    let canSave: Bool
    let onSaved: () -> Void

    @State private var selected: Set<String>
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    init(
        group: RBACGroup,
        permissions: [RBACPermission],
        initialKeys: Set<String>,
        canSave: Bool,
        onSaved: @escaping () -> Void
    ) {
        self.group = group
        self.permissions = permissions
        self.initialKeys = initialKeys
        self.canSave = canSave
        self.onSaved = onSaved
        _selected = State(initialValue: initialKeys)
    }

    private var categories: [(key: String, label: String, items: [RBACPermission])] {
        let visible = searchText.isEmpty ? permissions : permissions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.permKey.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
        }
        let grouped = Dictionary(grouping: visible, by: \.category)
        var seen = Set<String>()
        return visible.compactMap { permission in
            guard seen.insert(permission.category).inserted else { return nil }
            return (permission.category, permission.categoryLabel, grouped[permission.category] ?? [])
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("标识", value: group.key)
                LabeledContent("管理等级", value: "L\(group.level)")
                LabeledContent("成员", value: "\(group.userCount) 人")
                LabeledContent("已授予", value: "\(selected.count) / \(permissions.count)")
            }

            ForEach(categories, id: \.key) { category in
                Section {
                    if group.editable && searchText.isEmpty {
                        Button(category.items.allSatisfy { selected.contains($0.permKey) } ? "取消本类全部" : "选择本类全部") {
                            toggleCategory(category.items)
                        }
                        .font(.caption.weight(.semibold))
                    }
                    ForEach(category.items) { permission in
                        Toggle(isOn: binding(for: permission.permKey)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(permission.name)
                                Text(permission.permKey)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                if !permission.description.isEmpty {
                                    Text(permission.description)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .disabled(!group.editable)
                    }
                } header: {
                    Text(category.label)
                }
            }

            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索权限点")
        .toolbar {
            if group.editable {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving || !canSave || selected == initialKeys)
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { group.key == "admin" || selected.contains(key) },
            set: { enabled in if enabled { selected.insert(key) } else { selected.remove(key) } }
        )
    }

    private func toggleCategory(_ items: [RBACPermission]) {
        if items.allSatisfy({ selected.contains($0.permKey) }) {
            selected.subtract(items.map(\.permKey))
        } else {
            selected.formUnion(items.map(\.permKey))
        }
    }

    @MainActor private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let body = RBACPermissionsBody(permissionKeys: selected.sorted())
            let _: AdminActionResponse = try await APIClient.shared.send(
                "api/admin/rbac/roles/\(group.key)/permissions", method: "PUT", body: body
            )
            errorMessage = nil
            onSaved()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct RBACCreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var key = ""
    @State private var level = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let levelLabels = ["普通", "初级", "中级", "高级"]
    private var keyIsValid: Bool {
        key.range(of: "^[a-z][a-z0-9_]{2,49}$", options: .regularExpression) != nil
    }

    var body: some View {
        Form {
            Section {
                TextField("名称，例如：内容运营", text: $name)
                TextField("唯一标识，例如：content_ops", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: key) { key = $0.lowercased() }
                Picker("管理等级", selection: $level) {
                    ForEach(0..<levelLabels.count, id: \.self) { value in
                        Text("\(value) · \(levelLabels[value])").tag(value)
                    }
                }
            } header: {
                Text("权限组")
            } footer: {
                Text("标识须为 3–50 位小写字母、数字或下划线，并以字母开头。创建后可配置权限并分配给用户。")
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("新建权限组")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") { Task { await create() } }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !keyIsValid)
            }
        }
    }

    @MainActor private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let body = RBACCreateGroupBody(
                key: key, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                level: level, permissionKeys: []
            )
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/rbac/groups", body: body)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
