import PhotosUI
import SwiftUI
import UIKit

struct AdminTeamView: View {
    @State private var mode = TeamAdminMode.members

    var body: some View {
        VStack(spacing: 0) {
            Picker("管理内容", selection: $mode) {
                Text("团队成员").tag(TeamAdminMode.members)
                Text("合作商").tag(TeamAdminMode.partners)
            }
            .pickerStyle(.segmented)
            .padding()

            if mode == .members { AdminTeamMembersPanel() }
            else { AdminPartnersPanel() }
        }
        .navigationTitle("团队与合作商")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminTeamMembersPanel: View {
    @State private var departments: [AdminTeamDepartment] = []
    @State private var members: [AdminTeamMember] = []
    @State private var memberEditor: TeamMemberEditorState?
    @State private var departmentEditor: DepartmentEditorState?
    @State private var deletingDepartment: AdminTeamDepartment?
    @State private var deletingMember: AdminTeamMember?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button("添加团队成员", systemImage: "person.badge.plus") { memberEditor = TeamMemberEditorState(member: nil) }
                Button("新建部门", systemImage: "folder.badge.plus") { departmentEditor = DepartmentEditorState(department: nil) }
            }

            Section("部门（拖动调整展示顺序）") {
                if departments.isEmpty && !isLoading { Text("暂无部门，成员可先放在未分组。").foregroundStyle(.secondary) }
                ForEach(departments) { department in
                    HStack {
                        Label(department.name, systemImage: "folder.fill")
                        Spacer()
                        Text("\(members.filter { $0.departmentId == department.id }.count) 人").font(.caption).foregroundStyle(.secondary)
                        Menu {
                            Button("重命名", systemImage: "pencil") { departmentEditor = DepartmentEditorState(department: department) }
                            Button("删除", systemImage: "trash", role: .destructive) { deletingDepartment = department }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
                .onMove { source, destination in
                    departments.move(fromOffsets: source, toOffset: destination)
                    Task { await saveDepartmentOrder() }
                }
            }

            ForEach(departmentSections, id: \.id) { section in
                Section(section.name) {
                    let group = members.filter { $0.departmentId == section.departmentID }
                    if group.isEmpty { Text("暂无成员").font(.caption).foregroundStyle(.secondary) }
                    ForEach(group) { member in memberRow(member) }
                        .onMove { source, destination in reorderMembers(in: section.departmentID, source: source, destination: destination) }
                }
            }

            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage {
                EmptyStateView("团队数据加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                }.listRowBackground(Color.clear)
            }
        }
        .environment(\.editMode, .constant(.active))
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $memberEditor, onDismiss: { Task { await load() } }) { AdminTeamMemberEditor(state: $0, departments: departments) }
        .sheet(item: $departmentEditor, onDismiss: { Task { await load() } }) { AdminDepartmentEditor(state: $0) }
        .confirmationDialog("删除部门“\(deletingDepartment?.name ?? "")”？其中成员会转到未分组。", isPresented: Binding(get: { deletingDepartment != nil }, set: { if !$0 { deletingDepartment = nil } }), titleVisibility: .visible) {
            Button("删除部门", role: .destructive) { if let id = deletingDepartment?.id { Task { await deleteDepartment(id) } } }
            Button("取消", role: .cancel) { deletingDepartment = nil }
        }
        .confirmationDialog("从团队移除“\(deletingMember?.displayName ?? "")”？不会删除其用户账号。", isPresented: Binding(get: { deletingMember != nil }, set: { if !$0 { deletingMember = nil } }), titleVisibility: .visible) {
            Button("移除成员", role: .destructive) { if let id = deletingMember?.id { Task { await deleteMember(id) } } }
            Button("取消", role: .cancel) { deletingMember = nil }
        }
    }

    private var departmentSections: [TeamMemberSection] {
        departments.map { TeamMemberSection(id: "dept-\($0.id)", name: $0.name, departmentID: $0.id) }
            + [TeamMemberSection(id: "ungrouped", name: "未分组", departmentID: nil)]
    }

    private func memberRow(_ member: AdminTeamMember) -> some View {
        HStack(spacing: 11) {
            TeamRemoteImage(url: member.avatar, symbol: "person.fill", width: 42, height: 42, cornerRadius: 21)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(member.displayName).font(.subheadline.weight(.semibold))
                    if !member.visible { Image(systemName: "eye.slash.fill").font(.caption).foregroundStyle(.secondary) }
                }
                Text("@\(member.username) · ID \(member.userId)\(member.position.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                if let bio = member.bio ?? member.userBio, !bio.isEmpty { Text(bio).font(.caption2).foregroundStyle(.tertiary).lineLimit(2) }
            }
            Spacer(minLength: 0)
            Menu {
                Button("编辑资料与部门", systemImage: "pencil") { memberEditor = TeamMemberEditorState(member: member) }
                Button(member.visible ? "从关于页隐藏" : "在关于页显示", systemImage: member.visible ? "eye.slash" : "eye") { Task { await toggleMember(member) } }
                Button("移除团队成员", systemImage: "trash", role: .destructive) { deletingMember = member }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .opacity(member.visible ? 1 : 0.6)
        .padding(.vertical, 3)
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { let response: AdminTeamResponse = try await APIClient.shared.get("api/admin/team-members"); departments = response.departments; members = response.items }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
    @MainActor private func saveDepartmentOrder() async {
        do { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/team-departments/order", method: "PUT", body: TeamOrderBody(ids: departments.map(\.id))) }
        catch { errorMessage = error.localizedDescription; await load() }
    }
    private func reorderMembers(in departmentID: Int?, source: IndexSet, destination: Int) {
        var reordered = members.filter { $0.departmentId == departmentID }
        reordered.move(fromOffsets: source, toOffset: destination)
        let groupIDs = Set(reordered.map(\.id)); var iterator = reordered.makeIterator()
        members = members.map { groupIDs.contains($0.id) ? (iterator.next() ?? $0) : $0 }
        Task { await saveMemberOrder(reordered.map(\.id)) }
    }
    @MainActor private func saveMemberOrder(_ ids: [Int]) async {
        do { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/team-members/order", method: "PUT", body: TeamOrderBody(ids: ids)) }
        catch { errorMessage = error.localizedDescription; await load() }
    }
    @MainActor private func toggleMember(_ member: AdminTeamMember) async {
        do { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/team-members/\(member.id)", method: "PUT", body: TeamMemberVisibilityBody(visible: !member.visible)); await load() }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func deleteDepartment(_ id: Int) async {
        do { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/team-departments/\(id)", method: "DELETE"); deletingDepartment = nil; await load() }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func deleteMember(_ id: Int) async {
        do { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/team-members/\(id)", method: "DELETE"); deletingMember = nil; await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminDepartmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: DepartmentEditorState
    @State private var name: String
    @State private var busy = false
    @State private var errorMessage: String?

    init(state: DepartmentEditorState) { self.state = state; _name = State(initialValue: state.department?.name ?? "") }
    var body: some View {
        NavigationStack {
            Form {
                Section("部门名称") { TextField("例如：技术组 / 审核组", text: $name) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(state.department == nil ? "新建部门" : "重命名部门").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy) }
            }
        }
    }
    @MainActor private func save() async {
        busy = true; defer { busy = false }; errorMessage = nil
        do {
            if let id = state.department?.id { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/team-departments/\(id)", method: "PUT", body: TeamDepartmentBody(name: name)) }
            else { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/team-departments", body: TeamDepartmentBody(name: name)) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminTeamMemberEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: TeamMemberEditorState
    let departments: [AdminTeamDepartment]
    @State private var query: String
    @State private var position: String
    @State private var bio: String
    @State private var departmentID: Int
    @State private var visible: Bool
    @State private var busy = false
    @State private var errorMessage: String?

    init(state: TeamMemberEditorState, departments: [AdminTeamDepartment]) {
        self.state = state; self.departments = departments; let member = state.member
        _query = State(initialValue: ""); _position = State(initialValue: member?.position ?? ""); _bio = State(initialValue: member?.bio ?? ""); _departmentID = State(initialValue: member?.departmentId ?? 0); _visible = State(initialValue: member?.visible ?? true)
    }
    var body: some View {
        NavigationStack {
            Form {
                if state.member == nil {
                    Section("注册用户") { TextField("用户 ID / 邮箱 / 用户名 / 昵称", text: $query).textInputAutocapitalization(.never) }
                } else if let member = state.member {
                    Section { LabeledContent("成员", value: "\(member.displayName) (@\(member.username))") }
                }
                Section("展示资料") {
                    TextField("职位 / 头衔", text: $position)
                    TextField("简介（留空使用用户自己的简介）", text: $bio, axis: .vertical).lineLimit(3...7)
                    Picker("所属部门", selection: $departmentID) { Text("未分组").tag(0); ForEach(departments) { Text($0.name).tag($0.id) } }
                    if state.member != nil { Toggle("在关于页显示", isOn: $visible) }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(state.member == nil ? "添加团队成员" : "编辑团队成员").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled((state.member == nil && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || busy) }
            }
        }
    }
    @MainActor private func save() async {
        busy = true; defer { busy = false }; errorMessage = nil
        do {
            if let id = state.member?.id {
                let body = TeamMemberUpdateBody(position: position, bio: bio, visible: visible, departmentId: departmentID)
                let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/team-members/\(id)", method: "PUT", body: body)
            } else {
                let body = TeamMemberAddBody(query: query, position: position.isEmpty ? nil : position, bio: bio.isEmpty ? nil : bio, departmentId: departmentID == 0 ? nil : departmentID)
                let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/team-members", body: body)
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminPartnersPanel: View {
    @State private var partners: [AdminPartner] = []
    @State private var editor: PartnerEditorState?
    @State private var deleting: AdminPartner?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section { Button("添加合作商", systemImage: "plus.circle.fill") { editor = PartnerEditorState(partner: nil) } }
            Section("合作商（拖动调整展示顺序）") {
                if partners.isEmpty && !isLoading { Text("还没有合作商").foregroundStyle(.secondary) }
                ForEach(partners) { partner in
                    HStack(spacing: 12) {
                        TeamRemoteImage(url: partner.logo, symbol: "building.2.fill", width: 54, height: 42, cornerRadius: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(partner.nameZh).font(.subheadline.weight(.semibold)); if !partner.visible { Image(systemName: "eye.slash.fill").font(.caption).foregroundStyle(.secondary) } }
                            Text(partner.nameEn).font(.caption).foregroundStyle(.secondary)
                            if let url = partner.websiteUrl { Text(url).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                        }
                        Spacer()
                        Menu {
                            Button("编辑", systemImage: "pencil") { editor = PartnerEditorState(partner: partner) }
                            Button("删除", systemImage: "trash", role: .destructive) { deleting = partner }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }.opacity(partner.visible ? 1 : 0.6)
                }
                .onMove { source, destination in partners.move(fromOffsets: source, toOffset: destination); Task { await saveOrder() } }
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage {
                EmptyStateView("合作商加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent) }.listRowBackground(Color.clear)
            }
        }
        .environment(\.editMode, .constant(.active))
        .task { await load() }.refreshable { await load() }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { AdminPartnerEditor(state: $0) }
        .confirmationDialog("删除合作商“\(deleting?.nameZh ?? "")”？其 Logo 文件也会被清理。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }; Button("取消", role: .cancel) { deleting = nil }
        }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { let response: AdminPartnersResponse = try await APIClient.shared.get("api/admin/partners"); partners = response.items } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func saveOrder() async { do { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/partners/order", method: "PUT", body: TeamOrderBody(ids: partners.map(\.id))) } catch { errorMessage = error.localizedDescription; await load() } }
    @MainActor private func delete(_ id: Int) async { do { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/partners/\(id)", method: "DELETE"); deleting = nil; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminPartnerEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: PartnerEditorState
    @State private var nameZh: String; @State private var nameEn: String; @State private var bioZh: String; @State private var bioEn: String; @State private var websiteURL: String; @State private var logoFilename: String; @State private var logoURL: String?; @State private var visible: Bool
    @State private var selectedLogo: PhotosPickerItem?; @State private var uploading = false; @State private var busy = false; @State private var errorMessage: String?

    init(state: PartnerEditorState) {
        self.state = state; let partner = state.partner
        _nameZh = State(initialValue: partner?.nameZh ?? ""); _nameEn = State(initialValue: partner?.nameEn ?? ""); _bioZh = State(initialValue: partner?.bioZh ?? ""); _bioEn = State(initialValue: partner?.bioEn ?? ""); _websiteURL = State(initialValue: partner?.websiteUrl ?? ""); _logoFilename = State(initialValue: partner?.logoFilename ?? ""); _logoURL = State(initialValue: partner?.logo); _visible = State(initialValue: partner?.visible ?? true)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("名称") { TextField("中文名称", text: $nameZh); TextField("英文名称", text: $nameEn).textInputAutocapitalization(.words) }
                Section("简介") { TextField("中文简介", text: $bioZh, axis: .vertical).lineLimit(3...7); TextField("英文简介", text: $bioEn, axis: .vertical).lineLimit(3...7) }
                Section("展示") { TextField("官网（http:// 或 https://）", text: $websiteURL).keyboardType(.URL).textInputAutocapitalization(.never); Toggle("在关于页显示", isOn: $visible) }
                Section("Logo") {
                    if let logoURL { TeamRemoteImage(url: logoURL, symbol: "building.2.fill", width: 160, height: 90, cornerRadius: 12) }
                    PhotosPicker(selection: $selectedLogo, matching: .images) { Label(logoFilename.isEmpty ? "选择 Logo" : "更换 Logo", systemImage: "photo.badge.plus") }.disabled(uploading)
                    if uploading { HStack { ProgressView(); Text("正在上传并处理…") } }
                    if !logoFilename.isEmpty { Button("移除 Logo", role: .destructive) { logoFilename = ""; logoURL = nil } }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(state.partner == nil ? "添加合作商" : "编辑合作商").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(nameZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nameEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || uploading || busy) } }
            .onChange(of: selectedLogo) { item in if let item { Task { await upload(item) } } }
        }
    }
    @MainActor private func upload(_ item: PhotosPickerItem) async {
        uploading = true; errorMessage = nil; defer { uploading = false; selectedLogo = nil }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self), let image = UIImage(data: raw), let data = image.jpegData(compressionQuality: 0.9), data.count <= 8 * 1024 * 1024 else { throw TeamImageError.invalidOrLarge }
            let response: TeamLogoUploadResponse = try await APIClient.shared.upload("api/admin/partners/logo", imageData: data, filename: "partner-logo.jpg", mimeType: "image/jpeg", fields: [:])
            logoFilename = response.filename; logoURL = response.url
        } catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func save() async {
        busy = true; errorMessage = nil; defer { busy = false }
        do {
            let body = TeamPartnerBody(nameZh: nameZh, nameEn: nameEn, bioZh: bioZh, bioEn: bioEn, logoFilename: logoFilename, websiteUrl: websiteURL, visible: visible)
            if let id = state.partner?.id { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/partners/\(id)", method: "PUT", body: body) }
            else { let _: TeamMutationResponse = try await APIClient.shared.send("api/admin/partners", body: body) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct TeamRemoteImage: View {
    let url: String?; let symbol: String; let width: CGFloat; let height: CGFloat; let cornerRadius: CGFloat
    var body: some View { AsyncImage(url: url.flatMap(URL.init(string:))) { phase in if case .success(let image) = phase { image.resizable().scaledToFill() } else { Image(systemName: symbol).foregroundStyle(AppTheme.accent) } }.frame(width: width, height: height).background(AppTheme.accent.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: cornerRadius)) }
}

private enum TeamAdminMode: Hashable { case members, partners }
private struct TeamMemberSection { let id: String; let name: String; let departmentID: Int? }
private struct DepartmentEditorState: Identifiable { let id = UUID(); let department: AdminTeamDepartment? }
private struct TeamMemberEditorState: Identifiable { let id = UUID(); let member: AdminTeamMember? }
private struct PartnerEditorState: Identifiable { let id = UUID(); let partner: AdminPartner? }

private struct AdminTeamResponse: Codable, Sendable { let departments: [AdminTeamDepartment]; let items: [AdminTeamMember] }
private struct AdminTeamDepartment: Codable, Identifiable, Sendable { let id: Int; let name: String; let sortOrder: Int }
private struct AdminTeamMember: Codable, Identifiable, Sendable { let id: Int; let userId: Int; let departmentId: Int?; let username: String; let displayName: String; let avatar: String?; let position: String?; let bio: String?; let userBio: String?; let visible: Bool; let sortOrder: Int; let createdAt: String? }
private struct AdminPartnersResponse: Codable, Sendable { let items: [AdminPartner] }
private struct AdminPartner: Codable, Identifiable, Sendable { let id: Int; let nameZh: String; let nameEn: String; let bioZh: String?; let bioEn: String?; let logoFilename: String?; let logo: String?; let websiteUrl: String?; let visible: Bool; let sortOrder: Int; let createdAt: String? }
private struct TeamMutationResponse: Codable, Sendable { let ok: Bool?; let id: Int?; let name: String?; let deleted: Bool? }
private struct TeamDepartmentBody: Encodable, Sendable { let name: String }
private struct TeamOrderBody: Encodable, Sendable { let ids: [Int] }
private struct TeamMemberVisibilityBody: Encodable, Sendable { let visible: Bool }
private struct TeamMemberAddBody: Encodable, Sendable { let query: String; let position: String?; let bio: String?; let departmentId: Int? }
private struct TeamMemberUpdateBody: Encodable, Sendable { let position: String; let bio: String; let visible: Bool; let departmentId: Int }
private struct TeamPartnerBody: Encodable, Sendable { let nameZh: String; let nameEn: String; let bioZh: String; let bioEn: String; let logoFilename: String; let websiteUrl: String; let visible: Bool }
private struct TeamLogoUploadResponse: Codable, Sendable { let filename: String; let url: String }
private enum TeamImageError: LocalizedError { case invalidOrLarge; var errorDescription: String? { "请选择有效图片，处理后大小不能超过 8 MB" } }
