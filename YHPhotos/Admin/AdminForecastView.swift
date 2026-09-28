import SwiftUI

struct AdminForecastView: View {
    let identity: AdminIdentity
    @State private var tab: ForecastTab
    init(identity: AdminIdentity) { self.identity = identity; _tab = State(initialValue: identity.can("forecast.settings.view") ? .settings : .cache) }
    private var tabs: [ForecastTab] { ForecastTab.allCases.filter { $0 == .settings ? identity.can("forecast.settings.view") : identity.can("forecast.cache.view") } }
    var body: some View { VStack(spacing: 0) { if tabs.count > 1 { Picker("管理类别", selection: $tab) { ForEach(tabs) { Text($0.title).tag($0) } }.pickerStyle(.segmented).padding() }; if tab == .settings { AdminForecastSettingsView(identity: identity) } else { AdminForecastCacheView(identity: identity) } }.navigationTitle("好货预报").navigationBarTitleDisplayMode(.inline) }
}
private enum ForecastTab: String, CaseIterable, Identifiable { case settings, cache; var id: String { rawValue }; var title: String { self == .settings ? "设置与凭证" : "Redis 缓存" } }

private struct AdminForecastSettingsView: View {
    let identity: AdminIdentity
    @State private var settings: ForecastSettings?
    @State private var cacheHours = ""; @State private var equipmentHours = ""; @State private var rate = ""; @State private var minScore = ""; @State private var pageLimit = ""; @State private var rareTypes = ""
    @State private var username = ""; @State private var password = ""; @State private var pending: ForecastLoginResult?
    @State private var busy = false; @State private var errorMessage: String?; @State private var confirmClear = false
    var body: some View {
        Form {
            if let settings {
                Section("运行状态") {
                    Toggle("开放前台好货预报", isOn: Binding(get: { settings.enabled }, set: { value in self.settings = settings.with(enabled: value) })).disabled(!identity.can("forecast.settings.edit"))
                    LabeledContent("FR24 鉴权", value: authName(settings.authMode))
                    LabeledContent("Redis", value: settings.redis.ok ? "已连接" : "不可用")
                    if let host = settings.redis.urlHost { LabeledContent("Redis 主机", value: host) }
                    if let error = settings.redis.error { Text(error).font(.caption).foregroundStyle(.red) }
                    if identity.can("forecast.settings.edit") { Button("保存开关") { Task { await save() } } }
                    if identity.can("forecast.cache.flush") { Button("重连 Redis") { Task { await reconnect() } } }
                }
                Section("缓存与限流") {
                    TextField("时刻表缓存小时", text: $cacheHours).keyboardType(.decimalPad)
                    TextField("换机快照保留小时", text: $equipmentHours).keyboardType(.decimalPad)
                    TextField("每用户每分钟查询上限", text: $rate).keyboardType(.numberPad)
                    TextField("FR24 每页条数（10–100）", text: $pageLimit).keyboardType(.numberPad)
                }
                Section("打分规则") { TextField("最低分数门槛", text: $minScore).keyboardType(.numberPad); TextField("稀有机型 ICAO，逗号或空格分隔", text: $rareTypes, axis: .vertical).lineLimit(3...6); if identity.can("forecast.settings.edit") { Button("保存规则和限流") { Task { await save() } } } }
                Section("当前 FR24 凭证") {
                    SecretRow("Token", settings.fr24Token); SecretRow("Subscription Key", settings.fr24SubscriptionKey); SecretRow("账号", settings.fr24Username)
                    LabeledContent("出站代理", value: settings.fr24HttpProxy ?? "未配置")
                    if identity.can("forecast.settings.edit") { Button("清空已入库凭证", role: .destructive) { confirmClear = true } }
                }
                if identity.can("forecast.settings.edit") {
                    Section("登录并抓取 Token") { TextField("用户名 / 邮箱", text: $username).textInputAutocapitalization(.never); SecureField("FR24 密码", text: $password); Button("登录并抓取 Token", systemImage: "key.fill") { Task { await login() } }.disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || busy) }
                }
                if let pending {
                    Section("二次确认") {
                        if let hint = pending.hint { Text(hint).font(.caption).foregroundStyle(.orange) }
                        LabeledContent("账号", value: pending.preview.username)
                        if let type = pending.preview.accountType { LabeledContent("账户类型", value: type) }
                        if let expiry = pending.preview.dateExpiresIso { LabeledContent("到期时间", value: expiry) }
                        Text("Access Token").font(.caption).foregroundStyle(.secondary); Text(pending.preview.accessToken).font(.caption.monospaced()).textSelection(.enabled)
                        Text("Subscription Key").font(.caption).foregroundStyle(.secondary); Text(pending.preview.subscriptionKey).font(.caption.monospaced()).textSelection(.enabled)
                        Button("确认无误，写入数据库", systemImage: "checkmark.shield.fill") { Task { await confirmLogin() } }.foregroundStyle(.green)
                        Button("放弃本次抓取", role: .cancel) { self.pending = nil }
                    }
                }
            } else if errorMessage == nil { ProgressView().frame(maxWidth: .infinity) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .disabled(busy)
        .task { await load() }.refreshable { await load() }
        .confirmationDialog("确认清空 FR24 凭证并退回匿名模式？", isPresented: $confirmClear, titleVisibility: .visible) { Button("清空凭证", role: .destructive) { Task { await clearCredentials() } }; Button("取消", role: .cancel) {} }
    }
    @ViewBuilder private func SecretRow(_ title: String, _ secret: ForecastSecret) -> some View { LabeledContent(title, value: secret.set ? secret.preview : "未设置") }
    @MainActor private func load() async { do { let value: ForecastSettings = try await APIClient.shared.get("api/admin/forecast/settings"); settings = value; cacheHours = decimalHours(value.cacheTtlSeconds); equipmentHours = decimalHours(value.equipTtlSeconds); rate = String(value.ratePerMinute); minScore = String(value.minScore); pageLimit = String(value.pageLimit); rareTypes = value.rareTypecodes.joined(separator: ", "); errorMessage = nil } catch { errorMessage = error.localizedDescription } }
    @MainActor private func save(extra: ForecastSettingsBody? = nil) async { guard let settings else { return }; busy = true; defer { busy = false }; do { let body = extra ?? ForecastSettingsBody(enabled: settings.enabled, cacheTtlSeconds: max(60, Int((Double(cacheHours) ?? 0) * 3600)), equipTtlSeconds: max(3600, Int((Double(equipmentHours) ?? 0) * 3600)), ratePerMinute: Int(rate), minScore: Int(minScore), pageLimit: Int(pageLimit), rareTypecodes: rareTypes.split(whereSeparator: { $0 == "," || $0 == "，" || $0.isWhitespace }).map { $0.uppercased() }, fr24Token: nil, fr24SubscriptionKey: nil, fr24Username: nil, fr24Password: nil); let value: ForecastSettings = try await APIClient.shared.send("api/admin/forecast/settings", method: "PUT", body: body); self.settings = value; errorMessage = nil } catch { errorMessage = error.localizedDescription } }
    @MainActor private func login() async { busy = true; defer { busy = false }; do { pending = try await APIClient.shared.send("api/admin/forecast/fr24/login", body: ForecastLoginBody(username: username, password: password)); password = ""; errorMessage = nil } catch { errorMessage = error.localizedDescription } }
    @MainActor private func confirmLogin() async { guard let pending else { return }; busy = true; defer { busy = false }; do { let value: ForecastConfirmResponse = try await APIClient.shared.send("api/admin/forecast/fr24/confirm", body: ForecastConfirmBody(pendingId: pending.pendingId)); settings = value.settings; self.pending = nil; errorMessage = nil } catch { errorMessage = error.localizedDescription } }
    @MainActor private func clearCredentials() async { await save(extra: ForecastSettingsBody(enabled: nil, cacheTtlSeconds: nil, equipTtlSeconds: nil, ratePerMinute: nil, minScore: nil, pageLimit: nil, rareTypecodes: nil, fr24Token: "", fr24SubscriptionKey: "", fr24Username: "", fr24Password: "")); await load() }
    @MainActor private func reconnect() async { busy = true; defer { busy = false }; do { let _: ForecastRedis = try await APIClient.shared.send("api/admin/forecast/redis/reconnect", method: "POST"); await load() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminForecastCacheView: View {
    let identity: AdminIdentity
    @State private var pattern = "*"; @State private var response: ForecastCacheResponse?; @State private var inspected: ForecastCacheValue?; @State private var deleting: ForecastCacheEntry?; @State private var flushScope: String?; @State private var isLoading = true; @State private var errorMessage: String?
    var body: some View {
        List {
            Section { TextField("键名模式", text: $pattern).textInputAutocapitalization(.never); Button("刷新列表", systemImage: "arrow.clockwise") { Task { await load() } }; if identity.can("forecast.cache.flush") { Button("清空时刻表缓存") { flushScope = "schedule" }; Button("清空换机快照") { flushScope = "equipment" }; Button("全部清空", role: .destructive) { flushScope = "all" } } }
            if let redis = response?.redis { Section("Redis") { LabeledContent("连接", value: redis.ok ? "正常" : "不可用"); if let host = redis.urlHost { LabeledContent("主机", value: host) }; if let version = redis.version { LabeledContent("版本", value: version) } } }
            if let response { Section("缓存条目（\(response.items.count)）") { ForEach(response.items) { item in VStack(alignment: .leading, spacing: 5) { Text(item.key).font(.caption.monospaced()).textSelection(.enabled); Text("\(cacheKind(item.kind)) · 剩余 \(item.ttlSeconds) 秒 · \(ByteCountFormatter.string(fromByteCount: Int64(item.bytes), countStyle: .file))").font(.caption2).foregroundStyle(.secondary); HStack { Button("查看") { Task { await inspect(item.key) } }; if identity.can("forecast.cache.delete") { Button("删除", role: .destructive) { deleting = item } } }.font(.caption) }.padding(.vertical, 3) } } }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .task { await load() }.refreshable { await load() }
        .sheet(item: $inspected) { value in NavigationStack { ScrollView { Text(value.value.pretty).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }.navigationTitle(value.key).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { inspected = nil } } } } }
        .confirmationDialog("确认删除缓存键？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("删除", role: .destructive) { if let key = deleting?.key { Task { await delete(key) } } }; Button("取消", role: .cancel) {} }
        .confirmationDialog("确认清空缓存？", isPresented: Binding(get: { flushScope != nil }, set: { if !$0 { flushScope = nil } }), titleVisibility: .visible) { Button("清空", role: .destructive) { if let scope = flushScope { Task { await flush(scope) } } }; Button("取消", role: .cancel) {} }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { response = try await APIClient.shared.get("api/admin/forecast/cache", query: [URLQueryItem(name: "pattern", value: pattern), URLQueryItem(name: "limit", value: "1000")]) } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func inspect(_ key: String) async { do { inspected = try await APIClient.shared.get("api/admin/forecast/cache/entry", query: [URLQueryItem(name: "key", value: key)]) } catch { errorMessage = error.localizedDescription } }
    @MainActor private func delete(_ key: String) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/forecast/cache/entry", method: "DELETE", query: [URLQueryItem(name: "key", value: key)]); deleting = nil; await load() } catch { errorMessage = error.localizedDescription } }
    @MainActor private func flush(_ scope: String) async { do { let _: ForecastFlushResponse = try await APIClient.shared.send("api/admin/forecast/cache/flush", method: "POST", query: [URLQueryItem(name: "scope", value: scope)]); flushScope = nil; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct ForecastSecret: Codable, Sendable { let set: Bool; let preview: String }
private struct ForecastRedis: Codable, Sendable { let enabled: Bool; let ok: Bool; let urlHost: String?; let version: String?; let error: String? }
private struct ForecastSettings: Codable, Sendable {
    let enabled: Bool; let cacheTtlSeconds: Int; let equipTtlSeconds: Int; let ratePerMinute: Int; let minScore: Int; let pageLimit: Int; let rareTypecodes: [String]
    let fr24Token: ForecastSecret; let fr24SubscriptionKey: ForecastSecret; let fr24Username: ForecastSecret; let fr24Password: ForecastSecret; let fr24HttpProxy: String?; let authMode: String; let redis: ForecastRedis
    func with(enabled: Bool) -> Self { .init(enabled: enabled, cacheTtlSeconds: cacheTtlSeconds, equipTtlSeconds: equipTtlSeconds, ratePerMinute: ratePerMinute, minScore: minScore, pageLimit: pageLimit, rareTypecodes: rareTypecodes, fr24Token: fr24Token, fr24SubscriptionKey: fr24SubscriptionKey, fr24Username: fr24Username, fr24Password: fr24Password, fr24HttpProxy: fr24HttpProxy, authMode: authMode, redis: redis) }
}
private struct ForecastSettingsBody: Encodable, Sendable { let enabled: Bool?; let cacheTtlSeconds: Int?; let equipTtlSeconds: Int?; let ratePerMinute: Int?; let minScore: Int?; let pageLimit: Int?; let rareTypecodes: [String]?; let fr24Token: String?; let fr24SubscriptionKey: String?; let fr24Username: String?; let fr24Password: String? }
private struct ForecastLoginBody: Encodable, Sendable { let username: String; let password: String }
private struct ForecastConfirmBody: Encodable, Sendable { let pendingId: String }
private struct ForecastLoginResult: Codable, Sendable { struct Preview: Codable, Sendable { let accessToken: String; let subscriptionKey: String; let username: String; let identity: JSONValue?; let accountType: String?; let dateExpiresIso: String?; let userAgent: String? }; let pendingId: String; let expiresInSeconds: Int; let preview: Preview; let hint: String? }
private struct ForecastConfirmResponse: Codable, Sendable { let settings: ForecastSettings }
private struct ForecastCacheEntry: Codable, Identifiable, Sendable { var id: String { key }; let key: String; let kind: String; let ttlSeconds: Int; let bytes: Int }
private struct ForecastCacheResponse: Codable, Sendable { let items: [ForecastCacheEntry]; let redis: ForecastRedis }
private struct ForecastCacheValue: Codable, Identifiable, Sendable { var id: String { key }; let key: String; let ttlSeconds: Int; let value: JSONValue }
private struct ForecastFlushResponse: Codable, Sendable { let ok: Bool; let deleted: Int; let scope: String }

private enum JSONValue: Codable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws { let box = try decoder.singleValueContainer(); if box.decodeNil() { self = .null } else if let value = try? box.decode(Bool.self) { self = .bool(value) } else if let value = try? box.decode(Double.self) { self = .number(value) } else if let value = try? box.decode(String.self) { self = .string(value) } else if let value = try? box.decode([String: JSONValue].self) { self = .object(value) } else { self = .array(try box.decode([JSONValue].self)) } }
    func encode(to encoder: Encoder) throws { var box = encoder.singleValueContainer(); switch self { case .string(let value): try box.encode(value); case .number(let value): try box.encode(value); case .bool(let value): try box.encode(value); case .object(let value): try box.encode(value); case .array(let value): try box.encode(value); case .null: try box.encodeNil() } }
    var foundation: Any { switch self { case .string(let value): value; case .number(let value): value; case .bool(let value): value; case .object(let value): value.mapValues(\.foundation); case .array(let value): value.map(\.foundation); case .null: NSNull() } }
    var pretty: String { guard JSONSerialization.isValidJSONObject(foundation), let data = try? JSONSerialization.data(withJSONObject: foundation, options: [.prettyPrinted, .sortedKeys]), let string = String(data: data, encoding: .utf8) else { return String(describing: foundation) }; return string }
}
private func decimalHours(_ seconds: Int) -> String { String(format: "%.1f", Double(seconds) / 3600) }
private func authName(_ mode: String) -> String { switch mode { case "username_password": "用户名 + 密码"; case "token_subscription": "已入库 Token"; case "anonymous": "匿名"; default: mode } }
private func cacheKind(_ kind: String) -> String { switch kind { case "schedule": "时刻表"; case "equipment": "换机快照"; default: "其他" } }
