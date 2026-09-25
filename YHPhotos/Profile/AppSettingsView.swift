import SwiftUI
import UIKit

struct AppSettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openURL) private var openURL
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    var body: some View {
        List {
            Section(L10n.string("外观")) {
                Picker(L10n.string("显示模式"), selection: $appearance) {
                    ForEach(AppAppearance.allCases) { value in
                        Label(value.title, systemImage: value.icon).tag(value.rawValue)
                    }
                }
                NavigationLink { ThemePreviewView() } label: { Label(L10n.string("颜色预览"), systemImage: "paintpalette.fill") }
            }

            Section {
                Button { openSystemSettings() } label: {
                    HStack {
                        Label(L10n.string("App 语言"), systemImage: "globe")
                        Spacer()
                        Text(L10n.string("在系统设置中修改")).font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            } header: {
                Text(L10n.string("语言"))
            } footer: {
                Text(L10n.string("YHPhotos 跟随 iOS 的单独 App 语言设置，更改后重新打开 App 生效。"))
            }

            if appModel.sessionUser != nil {
                Section(L10n.string("账号")) {
                    NavigationLink { AccountSecurityView() } label: { Label(L10n.string("SSO 账号与安全"), systemImage: "person.badge.key.fill") }
                    NavigationLink { LoginSessionsView() } label: { Label(L10n.string("登录设备"), systemImage: "laptopcomputer.and.iphone") }
                    NavigationLink { NotificationPreferencesView() } label: { Label(L10n.string("通知偏好"), systemImage: "bell.badge.fill") }
                    NavigationLink { BlockedUsersView() } label: { Label(L10n.string("黑名单"), systemImage: "person.crop.circle.badge.xmark") }
                    NavigationLink { SavedSearchesView() } label: { Label(L10n.string("搜索订阅"), systemImage: "magnifyingglass.circle.fill") }
                    NavigationLink { APIPublishingSettingsView() } label: { Label(L10n.string("API 图片发布"), systemImage: "network") }
                }
                Section {
                    Button(role: .destructive) { Task { await appModel.logout() } } label: {
                        Label(L10n.string("退出登录"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }

            Section {
                SiteLegalFooter(compact: true)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(L10n.string("设置"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .appScreenBackground()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct LoginSession: Decodable, Identifiable, Sendable {
    let id: Int
    let ip: String?
    let userAgent: String?
    let lastActive: String?
    let createdAt: String?
    let current: Bool
}

private struct LoginSessionsView: View {
    @State private var sessions: [LoginSession] = []
    @State private var isLoading = true
    @State private var busyID: Int?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(sessions) { session in
                HStack(spacing: 13) {
                    Image(systemName: deviceIcon(session.userAgent)).font(.title3).foregroundStyle(AppTheme.accent).frame(width: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(deviceName(session.userAgent)).font(.headline)
                            if session.current { Text(L10n.string("当前")).font(.caption2.bold()).foregroundStyle(.green) }
                        }
                        Text("\(session.ip ?? L10n.string("未知 IP")) · \(shortDate(session.lastActive))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !session.current {
                        Button(role: .destructive) { Task { await revoke(session.id) } } label: {
                            if busyID == session.id { ProgressView() } else { Image(systemName: "rectangle.portrait.and.arrow.right") }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 4)
            }
            LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
        }
        .navigationTitle(L10n.string("登录设备"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sessions.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("退出其他设备"), role: .destructive) { Task { await revokeOthers() } }
                }
            }
        }
        .task { await load() }
    }

    private func deviceName(_ ua: String?) -> String {
        guard let ua, !ua.isEmpty else { return L10n.string("未知设备") }
        let os = ua.contains("iPhone") || ua.contains("iPad") || ua.contains("iOS") ? "iOS" : ua.contains("Macintosh") || ua.contains("Mac OS X") ? "macOS" : ua.contains("Android") ? "Android" : ua.contains("Windows") ? "Windows" : L10n.string("其他设备")
        let browser = ua.contains("Edg") ? "Edge" : ua.contains("Chrome") ? "Chrome" : ua.contains("Firefox") ? "Firefox" : ua.contains("Safari") ? "Safari" : L10n.string("客户端")
        return "\(browser) · \(os)"
    }
    private func deviceIcon(_ ua: String?) -> String {
        guard let ua else { return "desktopcomputer" }
        return ua.contains("iPhone") || ua.contains("Android") ? "iphone" : ua.contains("iPad") ? "ipad" : "desktopcomputer"
    }
    private func shortDate(_ value: String?) -> String { value.map { String($0.prefix(16)).replacingOccurrences(of: "T", with: " ") } ?? L10n.string("时间未知") }
    private func reload() { Task { await load() } }
    @MainActor private func load() async {
        isLoading = true; defer { isLoading = false }
        do { sessions = try await APIClient.shared.get("api/me/sessions"); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func revoke(_ id: Int) async {
        busyID = id; defer { busyID = nil }
        do { let _: APIClient.EmptyResponse = try await APIClient.shared.send("api/me/sessions/\(id)", method: "DELETE"); await load() }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func revokeOthers() async {
        do { let _: APIClient.EmptyResponse = try await APIClient.shared.send("api/me/sessions/revoke-others", method: "POST"); await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct BlockedUser: Decodable, Identifiable, Sendable {
    let id: Int
    let displayName: String
    let avatar: String?
    let createdAt: String?
}

private struct BlockedUsersView: View {
    @State private var users: [BlockedUser] = []
    @State private var isLoading = true
    @State private var busyID: Int?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(users) { user in
                HStack(spacing: 12) {
                    NavigationLink { PublicProfileView(userID: user.id) } label: {
                        HStack(spacing: 12) {
                            AvatarView(urlString: user.avatar, name: user.displayName, size: 42)
                            Text(user.displayName).font(.headline)
                        }
                    }
                    Spacer()
                    Button(L10n.string("解除")) { Task { await unblock(user.id) } }
                        .buttonStyle(.bordered).disabled(busyID == user.id)
                }
            }
            if users.isEmpty && !isLoading && errorMessage == nil {
                EmptyStateView(L10n.string("没有已拉黑的用户"), systemImage: "person.crop.circle.badge.checkmark")
            }
            LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
        }
        .navigationTitle(L10n.string("黑名单"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func reload() { Task { await load() } }
    @MainActor private func load() async {
        isLoading = true; defer { isLoading = false }
        do { users = try await APIClient.shared.get("api/me/blocks"); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func unblock(_ id: Int) async {
        busyID = id; defer { busyID = nil }
        do { let _: APIClient.EmptyResponse = try await APIClient.shared.send("api/users/\(id)/block", method: "DELETE"); users.removeAll { $0.id == id } }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct SavedSearch: Decodable, Identifiable, Sendable {
    struct Query: Decodable, Sendable { let q: String? }
    let id: Int
    let name: String?
    let query: Query
    let domain: String
    var alertEnabled: Bool
    let alertFrequency: String
    let createdAt: String?
}

private struct SavedSearchesView: View {
    @State private var searches: [SavedSearch] = []
    @State private var isLoading = true
    @State private var busyID: Int?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(searches) { search in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayName(search)).font(.headline)
                            Text(domainTitle(search.domain)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { search.alertEnabled },
                            set: { enabled in Task { await setAlert(search, enabled: enabled) } }
                        ))
                        .labelsHidden().disabled(busyID == search.id)
                    }
                    HStack {
                        if let query = search.query.q, !query.isEmpty {
                            NavigationLink {
                                SearchView(
                                    domain: PhotoDomain(rawValue: search.domain),
                                    title: displayName(search),
                                    query: query
                                )
                            } label: {
                                Label(L10n.string("查看搜索结果"), systemImage: "magnifyingglass")
                            }
                            .font(.caption)
                        }
                        Spacer()
                        Button(role: .destructive) { Task { await remove(search) } } label: {
                            Label(L10n.string("删除"), systemImage: "trash")
                        }
                        .font(.caption).buttonStyle(.borderless).disabled(busyID == search.id)
                    }
                }
                .padding(.vertical, 4)
            }
            if searches.isEmpty && !isLoading && errorMessage == nil {
                EmptyStateView(L10n.string("暂无搜索订阅"), systemImage: "magnifyingglass.circle")
            }
            LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
        }
        .navigationTitle(L10n.string("搜索订阅"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func displayName(_ value: SavedSearch) -> String {
        if let name = value.name, !name.isEmpty { return name }
        if let query = value.query.q, !query.isEmpty { return query }
        return L10n.string("未命名搜索")
    }
    private func domainTitle(_ value: String) -> String {
        switch value {
        case "aviation": L10n.string("航空")
        case "railway": L10n.string("铁路")
        case "flight_sim": L10n.string("模拟飞行")
        default: L10n.string("全部分区")
        }
    }
    private func reload() { Task { await load() } }
    @MainActor private func load() async {
        isLoading = true; defer { isLoading = false }
        do { searches = try await APIClient.shared.get("api/me/saved-searches"); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func setAlert(_ search: SavedSearch, enabled: Bool) async {
        struct Body: Encodable, Sendable { let alert_enabled: Bool }
        busyID = search.id; defer { busyID = nil }
        if let index = searches.firstIndex(where: { $0.id == search.id }) { searches[index].alertEnabled = enabled }
        do {
            let _: APIClient.EmptyResponse = try await APIClient.shared.send(
                "api/me/saved-searches/\(search.id)", method: "PUT", body: Body(alert_enabled: enabled)
            )
        } catch {
            if let index = searches.firstIndex(where: { $0.id == search.id }) { searches[index].alertEnabled = !enabled }
            errorMessage = error.localizedDescription
        }
    }
    @MainActor private func remove(_ search: SavedSearch) async {
        busyID = search.id; defer { busyID = nil }
        do {
            let _: APIClient.EmptyResponse = try await APIClient.shared.send("api/me/saved-searches/\(search.id)", method: "DELETE")
            searches.removeAll { $0.id == search.id }
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ThemePreviewView: View {
    var body: some View {
        VStack(spacing: 18) {
            GlassPanel(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.string("主要文字")).font(.title3.bold()).foregroundStyle(.primary)
                    Text(L10n.string("次要文字会自动适配浅色和深色背景。"))
                        .foregroundStyle(.secondary)
                    Label(L10n.string("强调色示例"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            Spacer()
        }
        .padding(18).navigationTitle(L10n.string("颜色预览")).appScreenBackground()
    }
}

private struct NotificationPreferencesView: View {
    private struct Item: Identifiable {
        let key: String
        let title: String
        var id: String { key }
    }
    private struct Channel: Identifiable {
        let title: String
        let icon: String
        let items: [Item]
        var id: String { title }
    }

    private static let channels = [
        Channel(title: L10n.string("邮件通知"), icon: "envelope.fill", items: [
            Item(key: "email_on_review", title: L10n.string("审核结果")),
            Item(key: "email_on_comment", title: L10n.string("评论与回复")),
            Item(key: "email_on_follow", title: L10n.string("新增关注")),
            Item(key: "email_on_message", title: L10n.string("新私信")),
            Item(key: "email_on_like", title: L10n.string("点赞")),
            Item(key: "email_on_saved_search", title: L10n.string("保存的搜索")),
            Item(key: "email_newsletter", title: L10n.string("社区通讯")),
        ]),
        Channel(title: L10n.string("站内通知"), icon: "bell.fill", items: [
            Item(key: "site_on_review", title: L10n.string("审核结果")),
            Item(key: "site_on_comment", title: L10n.string("评论与回复")),
            Item(key: "site_on_follow", title: L10n.string("新增关注")),
            Item(key: "site_on_message", title: L10n.string("新私信")),
            Item(key: "site_on_like", title: L10n.string("点赞")),
            Item(key: "site_on_saved_search", title: L10n.string("保存的搜索")),
            Item(key: "site_on_newsletter", title: L10n.string("社区通讯")),
            Item(key: "site_on_system", title: L10n.string("系统与安全")),
        ]),
        Channel(title: L10n.string("App 推送"), icon: "app.badge.fill", items: [
            Item(key: "push_on_review", title: L10n.string("审核结果")),
            Item(key: "push_on_comment", title: L10n.string("评论与回复")),
            Item(key: "push_on_follow", title: L10n.string("新增关注")),
            Item(key: "push_on_message", title: L10n.string("新私信")),
            Item(key: "push_on_like", title: L10n.string("点赞")),
            Item(key: "push_on_saved_search", title: L10n.string("保存的搜索")),
            Item(key: "push_on_newsletter", title: L10n.string("社区通讯")),
            Item(key: "push_on_system", title: L10n.string("系统与安全")),
        ]),
    ]

    @State private var preferences: [String: Bool]?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @StateObject private var pushManager = PushNotificationManager.shared

    var body: some View {
        Form {
            if preferences != nil {
                Section {
                    Toggle(L10n.string("全部通知"), isOn: bulkBinding(keys: allKeys))
                        .fontWeight(.semibold)
                }
                ForEach(Self.channels) { channel in
                    Section {
                        Toggle(L10n.string("本渠道全部通知"), isOn: bulkBinding(keys: channel.items.map(\.key)))
                            .fontWeight(.semibold)
                        ForEach(channel.items) { item in
                            Toggle(item.title, isOn: preferenceBinding(item.key))
                        }
                    } header: {
                        Label(channel.title, systemImage: channel.icon)
                    } footer: {
                        if channel.title == L10n.string("App 推送") {
                            pushAuthorizationFooter
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle(L10n.string("通知偏好"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) { if isSaving { ProgressView().padding(8) } }
        .task { await load(); await pushManager.refreshAuthorizationStatus() }
    }

    @ViewBuilder private var pushAuthorizationFooter: some View {
        switch pushManager.authorizationStatus {
        case .denied:
            Button(L10n.string("系统通知已关闭，前往设置开启")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        case .notDetermined:
            Button(L10n.string("允许系统推送通知")) { Task { _ = await pushManager.requestAuthorizationAndRegister() } }
        default:
            Text(L10n.string("推送内容会遵循上述开关和系统锁屏预览设置。"))
        }
    }

    private var allKeys: [String] { Self.channels.flatMap { $0.items.map(\.key) } }

    private func preferenceBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { preferences?[key] ?? false },
            set: { value in
                preferences?[key] = value
                Task {
                    if value, key.hasPrefix("push_") { _ = await pushManager.requestAuthorizationAndRegister() }
                    await save([key: value])
                }
            }
        )
    }

    private func bulkBinding(keys: [String]) -> Binding<Bool> {
        Binding(
            get: { keys.allSatisfy { preferences?[$0] == true } },
            set: { value in
                let updates = Dictionary(uniqueKeysWithValues: keys.map { ($0, value) })
                for key in keys { preferences?[key] = value }
                Task {
                    if value, keys.contains(where: { $0.hasPrefix("push_") }) {
                        _ = await pushManager.requestAuthorizationAndRegister()
                    }
                    await save(updates)
                }
            }
        )
    }

    @MainActor private func load() async {
        do { preferences = try await APIClient.shared.get("api/me/notification-preferences") }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func save(_ updates: [String: Bool]) async {
        struct Body: Encodable, Sendable { let prefs: [String: Bool] }
        isSaving = true; defer { isSaving = false }
        do {
            self.preferences = try await APIClient.shared.send("api/me/notification-preferences", method: "PUT", body: Body(prefs: updates))
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct APIPublishingStatus: Codable, Sendable {
    let schemaReady: Bool
    var enabled: Bool
    let approvedCount: Int
    let includedCount: Int
    let excludedCount: Int
}

private struct APIPublishingSettingsView: View {
    @State private var status: APIPublishingStatus?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let status {
                Section {
                    Toggle(L10n.string("允许通过公开 API 发布我的作品"), isOn: Binding(
                        get: { status.enabled },
                        set: { value in Task { await update(value) } }
                    ))
                    .disabled(!status.schemaReady || isSaving)
                } footer: {
                    Text(L10n.string("关闭后，合作方 API 将不再返回你的作品；单张作品的排除设置仍会保留。"))
                }
                Section(L10n.string("当前统计")) {
                    LabeledContent(L10n.string("已通过"), value: status.approvedCount.formatted())
                    LabeledContent(L10n.string("已包含"), value: status.includedCount.formatted())
                    LabeledContent(L10n.string("已排除"), value: status.excludedCount.formatted())
                }
            } else { ProgressView().frame(maxWidth: .infinity) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle(L10n.string("API 图片发布"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @MainActor private func load() async {
        do { status = try await APIClient.shared.get("api/me/api-publishing") }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor private func update(_ enabled: Bool) async {
        struct Body: Encodable, Sendable { let enabled: Bool }
        isSaving = true; defer { isSaving = false }
        do {
            status = try await APIClient.shared.send("api/me/api-publishing", method: "PUT", body: Body(enabled: enabled))
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
