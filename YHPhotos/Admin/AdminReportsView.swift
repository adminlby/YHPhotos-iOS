import SwiftUI

struct AdminReportsView: View {
    let identity: AdminIdentity

    @State private var tab: ReportTab
    @State private var status = "open"
    @State private var photoResponse: AdminPhotoReportsResponse?
    @State private var userResponse: AdminUserReportsResponse?
    @State private var selectedPhoto: AdminPhotoReport?
    @State private var selectedUser: AdminUserReport?
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(identity: AdminIdentity) {
        self.identity = identity
        _tab = State(initialValue: identity.can("report.photo.handle") ? .photos : .users)
    }

    private var allowedTabs: [ReportTab] {
        ReportTab.allCases.filter {
            switch $0 {
            case .photos: identity.can("report.photo.handle")
            case .users: identity.can("report.user.handle")
            }
        }
    }

    var body: some View {
        List {
            Section {
                if allowedTabs.count > 1 {
                    Picker("举报类型", selection: $tab) {
                        ForEach(allowedTabs) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Picker("状态", selection: $status) {
                    Text("待处理").tag("open")
                    Text("已核实").tag("resolved")
                    Text("不成立").tag("rejected")
                    Text("全部").tag("all")
                }
                .pickerStyle(.segmented)
            }

            if tab == .photos, let response = photoResponse {
                Section("共 \(response.total) 条") {
                    ForEach(response.items) { report in
                        Button { selectedPhoto = report } label: {
                            AdminPhotoReportRow(report: report)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if tab == .users, let response = userResponse {
                Section("共 \(response.total) 条") {
                    ForEach(response.items) { report in
                        Button { selectedUser = report } label: {
                            AdminUserReportRow(report: report)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let errorMessage {
                EmptyStateView("举报加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else if currentItemsAreEmpty {
                EmptyStateView("没有匹配的举报", systemImage: "flag.slash")
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("举报")
        .task(id: "\(tab.rawValue)|\(status)") { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedPhoto, onDismiss: { Task { await load() } }) { report in
            NavigationStack { AdminPhotoReportDetailView(report: report, identity: identity) }
        }
        .sheet(item: $selectedUser, onDismiss: { Task { await load() } }) { report in
            NavigationStack { AdminUserReportDetailView(report: report) }
        }
    }

    private var currentItemsAreEmpty: Bool {
        if tab == .photos { return photoResponse?.items.isEmpty == true }
        return userResponse?.items.isEmpty == true
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let query = [
                URLQueryItem(name: "status", value: status),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "offset", value: "0"),
            ]
            if tab == .photos {
                photoResponse = try await APIClient.shared.get("api/admin/reports/photos", query: query)
            } else {
                userResponse = try await APIClient.shared.get("api/admin/reports/users", query: query)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private enum ReportTab: String, CaseIterable, Identifiable {
    case photos, users
    var id: String { rawValue }
    var title: String { self == .photos ? "图片举报" : "用户举报" }
}

private struct AdminReportPerson: Codable, Sendable {
    let id: Int
    let displayName: String
}

private struct AdminPhotoReport: Codable, Identifiable, Sendable {
    struct Photo: Codable, Sendable {
        struct Owner: Codable, Sendable { let id: Int; let displayName: String }
        let id: Int
        let title: String
        let domain: String
        let status: String
        let thumb: String?
        let owner: Owner
    }
    let id: Int
    let status: String
    let reasonType: String?
    let reason: String?
    let resolution: String?
    let createdAt: String?
    let handledAt: String?
    let handler: String?
    let photo: Photo
    let reporter: AdminReportPerson?
}

private struct AdminPhotoReportsResponse: Codable, Sendable {
    let items: [AdminPhotoReport]
    let total: Int
}

private struct AdminUserReport: Codable, Identifiable, Sendable {
    struct Target: Codable, Sendable {
        let id: Int
        let username: String
        let displayName: String
        let avatar: String?
        let banned: Bool
    }
    let id: Int
    let status: String
    let reasonType: String?
    let reason: String?
    let resolution: String?
    let createdAt: String?
    let handledAt: String?
    let handler: String?
    let target: Target
    let reporter: AdminReportPerson?
}

private struct AdminUserReportsResponse: Codable, Sendable {
    let items: [AdminUserReport]
    let total: Int
}

private struct AdminReportResolveBody: Encodable, Sendable {
    let action: String
    let resolution: String?
}

private struct AdminPhotoReportRow: View {
    let report: AdminPhotoReport

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(urlString: report.photo.thumb)
                .frame(width: 86, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(report.photo.title.isEmpty ? "（无标题）" : report.photo.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    ReportStatusBadge(status: report.status)
                }
                Text("\(domainName(report.photo.domain)) · 上传者 \(report.photo.owner.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(report.reason ?? "（未填写理由）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct AdminUserReportRow: View {
    let report: AdminUserReport

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(urlString: report.target.avatar, name: report.target.displayName, size: 44, filename: report.target.avatar)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(report.target.displayName).font(.subheadline.weight(.semibold))
                    if report.target.banned {
                        Text("已封禁").font(.caption2).foregroundStyle(.red)
                    }
                }
                Text("@\(report.target.username)").font(.caption).foregroundStyle(.secondary)
                Text(report.reason ?? "（未填写理由）")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            ReportStatusBadge(status: report.status)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct AdminPhotoReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let report: AdminPhotoReport
    let identity: AdminIdentity

    @State private var resolution = ""
    @State private var status: String
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmAction: String?
    @State private var showingInspector = false

    init(report: AdminPhotoReport, identity: AdminIdentity) {
        self.report = report
        self.identity = identity
        _status = State(initialValue: report.status)
        _resolution = State(initialValue: report.resolution ?? "")
    }

    private var isOpen: Bool { status == "pending" || status == "reviewing" }
    private var inspectorEndpoint: String? {
        if identity.can(anyOf: ["content.photo.edit", "content.photo.requery", "content.photo.delete"]) {
            return "api/admin/content/photos/\(report.photo.id)/inspect"
        }
        if identity.can("review.queue.view") {
            return "api/admin/review/photos/\(report.photo.id)"
        }
        return nil
    }

    var body: some View {
        Form {
            Section("被举报图片") {
                Button { showingInspector = true } label: {
                    RemoteImage(urlString: report.photo.thumb, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(inspectorEndpoint == nil)
                LabeledContent("标题", value: report.photo.title.isEmpty ? "（无标题）" : report.photo.title)
                LabeledContent("领域", value: domainName(report.photo.domain))
                LabeledContent("上传者", value: report.photo.owner.displayName)
                if inspectorEndpoint != nil {
                    Button("打开检查工具", systemImage: "magnifyingglass") { showingInspector = true }
                } else {
                    Label("当前账号没有原图检查权限", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            reportInformation

            if isOpen {
                if status == "pending" {
                    Section {
                        Button("认领处理", systemImage: "hand.raised.fill") { Task { await simpleAction("claim") } }
                            .disabled(busy)
                    }
                } else {
                    Section("处理说明（选填）") {
                        TextEditor(text: $resolution).frame(minHeight: 88)
                    }
                    Section("处理操作") {
                        if identity.can("content.photo.delete") {
                            Button("举报属实 · 删除图片", systemImage: "trash.fill", role: .destructive) {
                                confirmAction = "delete_photo"
                            }
                        }
                        Button("举报属实 · 保留图片", systemImage: "checkmark.circle.fill") {
                            confirmAction = "resolve"
                        }
                        .foregroundStyle(.green)
                        Button("举报不成立", systemImage: "xmark.circle.fill") {
                            confirmAction = "dismiss"
                        }
                        Button("解锁并退回待处理", systemImage: "lock.open.fill") { Task { await simpleAction("release") } }
                    }
                    .disabled(busy)
                }
            }

            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("图片举报 #\(report.id)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        .fullScreenCover(isPresented: $showingInspector) {
            if let endpoint = inspectorEndpoint { AdminPhotoInspectionLoaderView(endpoint: endpoint) }
        }
        .confirmationDialog(
            confirmAction == "delete_photo" ? "确认永久删除这张图片？此操作不可恢复。" : "确认提交处理结果？",
            isPresented: Binding(get: { confirmAction != nil }, set: { if !$0 { confirmAction = nil } }),
            titleVisibility: .visible
        ) {
            Button(confirmAction == "delete_photo" ? "永久删除图片" : "确认提交", role: confirmAction == "delete_photo" ? .destructive : nil) {
                guard let action = confirmAction else { return }
                Task { await resolve(action) }
            }
            Button("取消", role: .cancel) { confirmAction = nil }
        }
    }

    @ViewBuilder private var reportInformation: some View {
        Section("举报信息") {
            ReportStatusBadge(status: status)
            if let type = report.reasonType { LabeledContent("类型", value: type) }
            Text(report.reason ?? "（未填写理由）")
            LabeledContent("举报人", value: report.reporter?.displayName ?? "匿名举报")
            if let handler = report.handler { LabeledContent("处理人", value: handler) }
            if !resolution.isEmpty, !isOpen { LabeledContent("处理说明", value: resolution) }
        }
    }

    @MainActor private func simpleAction(_ action: String) async {
        busy = true
        defer { busy = false }
        do {
            let result: AdminActionResponse = try await APIClient.shared.send("api/admin/reports/photos/\(report.id)/\(action)", method: "POST")
            status = result.status ?? (action == "claim" ? "reviewing" : "pending")
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func resolve(_ action: String) async {
        busy = true
        defer { busy = false }
        do {
            let body = AdminReportResolveBody(action: action, resolution: resolution.trimmedOrNil)
            let result: AdminActionResponse = try await APIClient.shared.send("api/admin/reports/photos/\(report.id)/resolve", body: body)
            status = result.status ?? (action == "dismiss" ? "rejected" : "resolved")
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminUserReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let report: AdminUserReport

    @State private var resolution: String
    @State private var status: String
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmAction: String?

    init(report: AdminUserReport) {
        self.report = report
        _resolution = State(initialValue: report.resolution ?? "")
        _status = State(initialValue: report.status)
    }

    private var isOpen: Bool { status == "pending" || status == "reviewing" }

    var body: some View {
        Form {
            Section("被举报用户") {
                HStack(spacing: 12) {
                    AvatarView(urlString: report.target.avatar, name: report.target.displayName, size: 52, filename: report.target.avatar)
                    VStack(alignment: .leading) {
                        Text(report.target.displayName).font(.headline)
                        Text("@\(report.target.username)").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("用户 ID", value: String(report.target.id))
                LabeledContent("账号状态", value: report.target.banned ? "已封禁" : "正常")
                NavigationLink("打开原生用户管理") {
                    AdminUserDetailLoaderView(userID: report.target.id)
                }
            }
            Section("举报信息") {
                ReportStatusBadge(status: status)
                if let type = report.reasonType { LabeledContent("类型", value: type) }
                Text(report.reason ?? "（未填写理由）")
                LabeledContent("举报人", value: report.reporter?.displayName ?? "匿名举报")
                if let handler = report.handler { LabeledContent("处理人", value: handler) }
            }
            if isOpen {
                if status == "pending" {
                    Section { Button("认领处理", systemImage: "hand.raised.fill") { Task { await simpleAction("claim") } } }
                } else {
                    Section("处理说明（选填）") { TextEditor(text: $resolution).frame(minHeight: 88) }
                    Section("处理操作") {
                        Button("已核实并处理", systemImage: "checkmark.circle.fill") { confirmAction = "resolve" }
                            .foregroundStyle(.green)
                        Button("举报不成立", systemImage: "xmark.circle.fill") { confirmAction = "dismiss" }
                        Button("解锁并退回待处理", systemImage: "lock.open.fill") { Task { await simpleAction("release") } }
                    }
                }
            } else if !resolution.isEmpty {
                Section("处理说明") { Text(resolution) }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .disabled(busy)
        .navigationTitle("用户举报 #\(report.id)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        .confirmationDialog("确认提交处理结果？", isPresented: Binding(get: { confirmAction != nil }, set: { if !$0 { confirmAction = nil } }), titleVisibility: .visible) {
            Button("确认提交") {
                guard let action = confirmAction else { return }
                Task { await resolve(action) }
            }
            Button("取消", role: .cancel) { confirmAction = nil }
        }
    }

    @MainActor private func simpleAction(_ action: String) async {
        busy = true
        defer { busy = false }
        do {
            let result: AdminActionResponse = try await APIClient.shared.send("api/admin/reports/users/\(report.id)/\(action)", method: "POST")
            status = result.status ?? (action == "claim" ? "reviewing" : "pending")
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func resolve(_ action: String) async {
        busy = true
        defer { busy = false }
        do {
            let body = AdminReportResolveBody(action: action, resolution: resolution.trimmedOrNil)
            let result: AdminActionResponse = try await APIClient.shared.send("api/admin/reports/users/\(report.id)/resolve", body: body)
            status = result.status ?? (action == "dismiss" ? "rejected" : "resolved")
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ReportStatusBadge: View {
    let status: String
    var body: some View {
        Text(label).font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
    private var label: String {
        switch status {
        case "pending": "待处理"
        case "reviewing": "处理中"
        case "resolved": "已核实"
        case "rejected": "不成立"
        default: status
        }
    }
    private var color: Color {
        switch status { case "resolved": .green; case "rejected": .secondary; case "reviewing": .blue; default: .orange }
    }
}

private extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
