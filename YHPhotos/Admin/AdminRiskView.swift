import SwiftUI

struct AdminRiskView: View {
    let identity: AdminIdentity
    @State private var mode: RiskMode

    init(identity: AdminIdentity) {
        self.identity = identity
        if identity.can(anyOf: ["risk.keyword.manage"]) { _mode = State(initialValue: .keywords) }
        else if identity.can(anyOf: ["risk.ip.manage"]) { _mode = State(initialValue: .ip) }
        else { _mode = State(initialValue: .monitor) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("风控功能", selection: $mode) {
                if identity.can(anyOf: ["risk.keyword.manage"]) { Text("敏感词").tag(RiskMode.keywords) }
                if identity.can(anyOf: ["risk.ip.manage"]) { Text("IP 黑名单").tag(RiskMode.ip) }
                if identity.can(anyOf: ["risk.monitor.view"]) { Text("安全监控").tag(RiskMode.monitor) }
            }
            .pickerStyle(.segmented).padding()
            switch mode {
            case .keywords: AdminRiskKeywordsView()
            case .ip: AdminRiskIPView()
            case .monitor: AdminRiskMonitorView()
            }
        }
        .navigationTitle("风控安全")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminRiskKeywordsView: View {
    @State private var response: RiskKeywordsResponse?
    @State private var query = ""
    @State private var offset = 0
    @State private var editor: RiskKeywordEditorState?
    @State private var deleting: RiskKeyword?
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let limit = 50

    var body: some View {
        List {
            Section { Button("新增敏感词", systemImage: "plus.circle.fill") { editor = RiskKeywordEditorState(item: nil) } }
            if let response, !response.items.isEmpty {
                Section("共 \(response.total) 个敏感词") {
                    ForEach(response.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(item.keyword).font(.system(.subheadline, design: .monospaced).weight(.semibold)); Text(item.typeLabel).font(.caption2).foregroundStyle(item.typeColor); Text(item.scopeLabel).font(.caption2).foregroundStyle(.secondary); if !item.active { Text("停用").font(.caption2).foregroundStyle(.secondary) } }
                                HStack { Text("严重度 \(item.severity)"); if item.type == "replace", let replacement = item.replacement { Text("替换为：\(replacement)") } }.font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu { Button("编辑", systemImage: "pencil") { editor = RiskKeywordEditorState(item: item) }; Button("删除", systemImage: "trash", role: .destructive) { deleting = item } } label: { Image(systemName: "ellipsis.circle") }
                        }.opacity(item.active ? 1 : 0.6).padding(.vertical, 3)
                    }
                }
                RiskPager(offset: $offset, limit: limit, total: response.total)
            } else if !isLoading && errorMessage == nil { EmptyStateView("还没有敏感词", systemImage: "nosign").listRowBackground(Color.clear) }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .searchable(text: $query, prompt: "搜索敏感词")
        .task(id: "\(query)|\(offset)") { await load() }.refreshable { await load() }
        .onChange(of: query) { _ in offset = 0 }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { RiskKeywordEditor(state: $0) }
        .confirmationDialog("删除敏感词“\(deleting?.keyword ?? "")”？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }; Button("取消", role: .cancel) { deleting = nil }
        }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { response = try await APIClient.shared.get("api/admin/risk/keywords", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]) } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func delete(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/risk/keywords/\(id)", method: "DELETE"); deleting = nil; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct RiskKeywordEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: RiskKeywordEditorState
    @State private var keyword: String; @State private var type: String; @State private var scope: String; @State private var replacement: String; @State private var severity: Int; @State private var active: Bool; @State private var busy = false; @State private var errorMessage: String?
    init(state: RiskKeywordEditorState) { self.state = state; let item = state.item; _keyword = State(initialValue: item?.keyword ?? ""); _type = State(initialValue: item?.type ?? "block"); _scope = State(initialValue: item?.scope ?? "all"); _replacement = State(initialValue: item?.replacement ?? ""); _severity = State(initialValue: item?.severity ?? 1); _active = State(initialValue: item?.active ?? true) }
    var body: some View {
        NavigationStack {
            Form {
                Section("规则") { TextField("敏感词", text: $keyword); Picker("处理方式", selection: $type) { Text("拦截").tag("block"); Text("转人工审核").tag("review"); Text("替换").tag("replace") }; Picker("范围", selection: $scope) { Text("全部").tag("all"); Text("标题").tag("title"); Text("描述").tag("description"); Text("标签").tag("tag"); Text("评论").tag("comment"); Text("用户名").tag("username") }; if type == "replace" { TextField("替换为", text: $replacement) }; Stepper("严重度：\(severity)", value: $severity, in: 1...10); Toggle("启用", isOn: $active) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(state.item == nil ? "新增敏感词" : "编辑敏感词").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy) } }
        }
    }
    @MainActor private func save() async { busy = true; errorMessage = nil; defer { busy = false }; do { let body = RiskKeywordBody(keyword: keyword, type: type, scope: scope, replacement: replacement.isEmpty ? nil : replacement, severity: severity, active: active); if let id = state.item?.id { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/risk/keywords/\(id)", method: "PUT", body: body) } else { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/risk/keywords", body: body) }; dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminRiskIPView: View {
    @State private var response: RiskIPResponse?
    @State private var offset = 0
    @State private var adding = false
    @State private var deleting: RiskIPItem?
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let limit = 50

    var body: some View {
        List {
            Section { Button("添加 IP / CIDR", systemImage: "plus.circle.fill") { adding = true } }
            if let response, !response.items.isEmpty {
                Section("共 \(response.total) 条") {
                    ForEach(response.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(item.ipAddress ?? item.ipRange ?? "—").font(.system(.subheadline, design: .monospaced).weight(.semibold)); Text(item.type == "block" ? "拦截" : "观察").font(.caption2).foregroundStyle(item.type == "block" ? .red : .orange) }
                                if let reason = item.reason, !reason.isEmpty { Text(reason).font(.caption).foregroundStyle(.secondary) }
                                HStack { if let creator = item.creator { Text("添加人 \(creator)") }; if let expires = item.expiresAt { Text("到期 \(expires.prefix(16))") } }.font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer(); Button(role: .destructive) { deleting = item } label: { Image(systemName: "trash") }
                        }.padding(.vertical, 3)
                    }
                }
                RiskPager(offset: $offset, limit: limit, total: response.total)
            } else if !isLoading && errorMessage == nil { EmptyStateView("黑名单为空", systemImage: "globe").listRowBackground(Color.clear) }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .task(id: offset) { await load() }.refreshable { await load() }
        .sheet(isPresented: $adding, onDismiss: { Task { await load() } }) { RiskIPAddView() }
        .confirmationDialog("删除该 IP 风控规则？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("删除", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }; Button("取消", role: .cancel) { deleting = nil } }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { response = try await APIClient.shared.get("api/admin/risk/ip", query: [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]) } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func delete(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/risk/ip/\(id)", method: "DELETE"); deleting = nil; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct RiskIPAddView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""; @State private var range = ""; @State private var reason = ""; @State private var type = "block"; @State private var expiresAt = ""; @State private var busy = false; @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("目标（二选一）") { TextField("IP 地址", text: $address).textInputAutocapitalization(.never).keyboardType(.numbersAndPunctuation); TextField("CIDR 段，如 1.2.3.0/24", text: $range).textInputAutocapitalization(.never) }
                Section("规则") { Picker("类型", selection: $type) { Text("拦截").tag("block"); Text("观察").tag("watch") }; TextField("原因", text: $reason, axis: .vertical).lineLimit(2...5); TextField("到期时间（可空）", text: $expiresAt) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }.navigationTitle("添加 IP 风控规则").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("添加") { Task { await save() } }.disabled((address.trimmingCharacters(in: .whitespaces).isEmpty && range.trimmingCharacters(in: .whitespaces).isEmpty) || busy) } }
        }
    }
    @MainActor private func save() async { busy = true; defer { busy = false }; do { let body = RiskIPBody(ip_address: address.isEmpty ? nil : address, ip_range: range.isEmpty ? nil : range, reason: reason.isEmpty ? nil : reason, type: type, expires_at: expiresAt.isEmpty ? nil : expiresAt); let _: AdminActionResponse = try await APIClient.shared.send("api/admin/risk/ip", body: body); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminRiskMonitorView: View {
    @State private var mode = RiskMonitorMode.api
    @State private var response: RiskMonitorResponse?
    @State private var query = ""
    @State private var eventType = ""
    @State private var outcome = -1
    @State private var offset = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let limit = 50

    var body: some View {
        List {
            Section {
                Picker("记录类型", selection: $mode) { Text("接口违规").tag(RiskMonitorMode.api); Text("登录").tag(RiskMonitorMode.login); Text("验证码").tag(RiskMonitorMode.captcha); Text("设备").tag(RiskMonitorMode.devices) }.pickerStyle(.menu)
                if mode == .api { TextField("事件类型（可空）", text: $eventType).textInputAutocapitalization(.never); Picker("封禁状态", selection: $outcome) { Text("全部").tag(-1); Text("未封禁").tag(0); Text("已封禁").tag(1) } }
                if mode == .login { Picker("登录结果", selection: $outcome) { Text("全部").tag(-1); Text("失败").tag(0); Text("成功").tag(1) } }
            }
            if let response, !response.items.isEmpty {
                Section("共 \(response.total) 条记录") { ForEach(response.items) { row in monitorRow(row) } }
                RiskPager(offset: $offset, limit: limit, total: response.total)
            } else if !isLoading && errorMessage == nil { EmptyStateView("暂无记录", systemImage: "magnifyingglass.circle").listRowBackground(Color.clear) }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .searchable(text: $query, prompt: mode.searchPrompt)
        .task(id: "\(mode.rawValue)|\(query)|\(eventType)|\(outcome)|\(offset)") { await load() }.refreshable { await load() }
        .onChange(of: mode) { _ in offset = 0; outcome = -1; eventType = ""; query = "" }
        .onChange(of: query) { _ in offset = 0 }
    }

    private func monitorRow(_ row: RiskMonitorRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: row.resultSymbol).foregroundStyle(row.resultColor)
                Text(row.primary(mode)).font(.subheadline.weight(.semibold))
                Spacer()
                Text(row.createdAt?.replacingOccurrences(of: "T", with: " ").prefix(19).description ?? "—").font(.caption2).foregroundStyle(.tertiary)
            }
            if mode == .api { Text("\(row.httpMethod ?? "") \(row.apiPath ?? "—")").font(.system(.caption, design: .monospaced)).foregroundStyle(AppTheme.accent); if let reason = row.reason { Text(reason).font(.caption) }; HStack { Text(row.eventType ?? "未知事件"); if let severity = row.severity?.text { Text("严重度 \(severity)") }; if row.blocked == true { Text("已拦截") }; if row.banned == true { Text("已封禁") } }.font(.caption2).foregroundStyle(.secondary) }
            if mode == .login { Text(row.userAgent ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            if mode == .captcha { Text("用途 \(row.purpose ?? "—") · 难度 \(row.difficulty?.text ?? "—")").font(.caption).foregroundStyle(.secondary) }
            if mode == .devices { Text([row.deviceName, row.os, row.browser].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            if let ip = row.ip { Text("IP  \(ip)").font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled) }
        }.padding(.vertical, 4)
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do {
            var items = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]
            if !query.isEmpty, mode != .captcha { items.append(URLQueryItem(name: "q", value: query)) }
            if mode == .api, !eventType.isEmpty { items.append(URLQueryItem(name: "event_type", value: eventType)) }
            if outcome >= 0 { items.append(URLQueryItem(name: mode == .login ? "success" : "banned", value: String(outcome))) }
            response = try await APIClient.shared.get("api/admin/risk/\(mode.endpoint)", query: items)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct RiskPager: View {
    @Binding var offset: Int; let limit: Int; let total: Int
    var body: some View { if total > limit { Section { HStack { Button("上一页", systemImage: "chevron.left") { offset = max(0, offset - limit) }.disabled(offset == 0); Spacer(); Text("\(offset / limit + 1) / \(max(1, Int(ceil(Double(total) / Double(limit)))))").foregroundStyle(.secondary); Spacer(); Button("下一页") { offset += limit }.disabled(offset + limit >= total); Image(systemName: "chevron.right") } } } }
}

private enum RiskMode: Hashable { case keywords, ip, monitor }
private enum RiskMonitorMode: String, Hashable { case api, login, captcha, devices; var endpoint: String { switch self { case .api: "api-events"; case .login: "login-attempts"; case .captcha: "captcha-attempts"; case .devices: "devices" } }; var searchPrompt: String { switch self { case .api: "用户、IP、路径、原因"; case .login: "邮箱或 IP"; case .devices: "用户、设备或 IP"; case .captcha: "验证码记录不支持搜索" } } }
private struct RiskKeywordEditorState: Identifiable { let id = UUID(); let item: RiskKeyword? }
private struct RiskKeywordsResponse: Codable, Sendable { let items: [RiskKeyword]; let total: Int }
private struct RiskKeyword: Codable, Identifiable, Sendable { let id: Int; let keyword: String; let type: String; let scope: String; let replacement: String?; let severity: Int; let active: Bool; var typeLabel: String { switch type { case "block": "拦截"; case "review": "转人工"; case "replace": "替换"; default: type } }; var typeColor: Color { type == "block" ? .red : type == "review" ? .orange : .blue }; var scopeLabel: String { switch scope { case "all": "全部"; case "title": "标题"; case "description": "描述"; case "tag": "标签"; case "comment": "评论"; case "username": "用户名"; default: scope } } }
private struct RiskKeywordBody: Encodable, Sendable { let keyword: String; let type: String; let scope: String; let replacement: String?; let severity: Int; let active: Bool }
private struct RiskIPResponse: Codable, Sendable { let items: [RiskIPItem]; let total: Int }
private struct RiskIPItem: Codable, Identifiable, Sendable { let id: Int; let ipAddress: String?; let ipRange: String?; let reason: String?; let type: String; let creator: String?; let expiresAt: String? }
private struct RiskIPBody: Encodable, Sendable { let ip_address: String?; let ip_range: String?; let reason: String?; let type: String; let expires_at: String? }
private struct RiskMonitorResponse: Codable, Sendable { let total: Int; let items: [RiskMonitorRow] }
private struct RiskMonitorRow: Codable, Identifiable, Sendable {
    let id: Int; let eventType: String?; let severity: RiskScalar?; let userId: Int?; let username: String?; let displayName: String?; let ip: String?; let userAgent: String?; let apiPath: String?; let httpMethod: String?; let reason: String?; let blocked: Bool?; let banned: Bool?; let createdAt: String?; let email: String?; let success: Bool?; let difficulty: RiskScalar?; let purpose: String?; let passed: Bool?; let deviceName: String?; let os: String?; let browser: String?
    var resultSymbol: String { if banned == true { return "hand.raised.fill" }; if let success { return success ? "checkmark.circle.fill" : "xmark.circle.fill" }; if let passed { return passed ? "checkmark.circle.fill" : "xmark.circle.fill" }; return blocked == true ? "exclamationmark.shield.fill" : "desktopcomputer" }
    var resultColor: Color { if banned == true || success == false || passed == false { return .red }; if success == true || passed == true { return .green }; return blocked == true ? .orange : .blue }
    func primary(_ mode: RiskMonitorMode) -> String { switch mode { case .api: displayName ?? username ?? "未登录"; case .login: displayName ?? email ?? "未知账号"; case .captcha: purpose ?? "验证码"; case .devices: displayName ?? deviceName ?? "未知设备" } }
}
private enum RiskScalar: Codable, Sendable { case string(String), int(Int), double(Double); init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); if let v = try? c.decode(Int.self) { self = .int(v) } else if let v = try? c.decode(Double.self) { self = .double(v) } else { self = .string(try c.decode(String.self)) } }; func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); switch self { case .string(let v): try c.encode(v); case .int(let v): try c.encode(v); case .double(let v): try c.encode(v) } }; var text: String { switch self { case .string(let v): v; case .int(let v): String(v); case .double(let v): String(v) } } }
