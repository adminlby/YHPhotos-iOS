import SwiftUI

private enum InboxSection: String, CaseIterable, Identifiable {
    case direct
    case notifications
    var id: String { rawValue }
    var title: String { self == .direct ? L10n.string("私信") : L10n.string("站内消息") }
}

private enum SiteMessageDestination {
    case photo(Int)
    case user(Int)
    case badges
    case settings
}

struct MessagesView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var section: InboxSection = .direct
    @State private var conversations: [Conversation] = []
    @State private var notifications: [SiteNotification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingComposer = false

    var body: some View {
        NavigationStack {
            Group {
                if appModel.sessionUser == nil { signedOut }
                else { content }
            }
            .navigationTitle(L10n.string("消息"))
            .toolbar {
                if appModel.sessionUser != nil, section == .direct {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingComposer = true } label: { Image(systemName: "square.and.pencil") }
                    }
                }
                if appModel.sessionUser != nil, section == .notifications, notifications.contains(where: { !$0.isRead }) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.string("全部已读")) { Task { await markAllRead() } }
                    }
                }
            }
            .sheet(isPresented: $showingComposer, onDismiss: { Task { await loadConversations() } }) {
                NavigationStack { NewConversationView() }
            }
            .task(id: appModel.sessionUser?.id) { if appModel.sessionUser != nil { await load() } }
            .appScreenBackground()
        }
    }

    private var signedOut: some View {
        EmptyStateView(
            L10n.string("登录后查看消息"),
            systemImage: "bubble.left.and.bubble.right",
            description: L10n.string("私信与站内消息会集中显示在这里。")
        ) {
            Button(L10n.string("登录")) { appModel.showingLogin = true }.buttonStyle(.borderedProminent)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Picker(L10n.string("消息类型"), selection: $section) {
                ForEach(InboxSection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 10)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.red).padding(.horizontal)
            }
            if section == .direct { conversationList } else { notificationList }
        }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var conversationList: some View {
        if conversations.isEmpty && !isLoading {
            EmptyStateView(L10n.string("还没有私信"), systemImage: "text.bubble", description: L10n.string("从摄影师主页或右上角发起对话。"))
        } else {
            List(conversations) { conversation in
                NavigationLink { ConversationView(conversation: conversation) } label: {
                    HStack(spacing: 12) {
                        AvatarView(urlString: conversation.other.avatar, name: conversation.other.displayName, size: 52)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(conversation.other.displayName).font(.headline)
                                Spacer()
                                Text(shortDate(conversation.lastMessageAt)).font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text((conversation.lastMessageMine ? L10n.string("我：") : "") + (conversation.lastMessage ?? L10n.string("开始对话")))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                if conversation.unread > 0 {
                                    Text(conversation.unread > 99 ? "99+" : "\(conversation.unread)")
                                        .font(.caption2.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 3).background(.red, in: Capsule())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var notificationList: some View {
        if notifications.isEmpty && !isLoading {
            EmptyStateView(L10n.string("还没有站内消息"), systemImage: "bell", description: L10n.string("审核结果、评论、关注和系统通知会显示在这里。"))
        } else {
            List(notifications) { item in
                if let destination = destination(for: item.link) {
                    NavigationLink { destinationView(destination) } label: { notificationRow(item) }
                        .simultaneousGesture(TapGesture().onEnded { Task { await markRead(item) } })
                } else {
                    Button {
                        Task { await markRead(item) }
                        if item.link?.hasPrefix("/me") == true { appModel.select(.profile) }
                    } label: { notificationRow(item) }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
    }

    private func notificationRow(_ item: SiteNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notificationIcon(item.type))
                .foregroundStyle(item.isRead ? Color.secondary : AppTheme.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.elevated, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.title ?? notificationType(item.type)).font(.headline)
                    Spacer()
                    Text(shortDate(item.createdAt)).font(.caption2).foregroundStyle(.secondary)
                }
                if let body = item.content { Text(body).font(.subheadline).foregroundStyle(.secondary) }
            }
            if !item.isRead { Circle().fill(AppTheme.accent).frame(width: 8, height: 8).padding(.top, 6) }
        }
        .padding(.vertical, 5).contentShape(Rectangle())
    }

    private func destination(for link: String?) -> SiteMessageDestination? {
        guard let link, let components = URLComponents(string: link) else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        if parts.count >= 3, parts[0] == "photo", let id = Int(parts[2]) { return .photo(id) }
        if parts.count >= 2, parts[0] == "user", let id = Int(parts[1]) { return .user(id) }
        if parts.first == "me" {
            let tab = components.queryItems?.first(where: { $0.name == "tab" })?.value
            if tab == "badges" { return .badges }
            if tab == "settings" || tab == "security" { return .settings }
        }
        return nil
    }

    @ViewBuilder private func destinationView(_ destination: SiteMessageDestination) -> some View {
        switch destination {
        case let .photo(id): PhotoDetailView(photoID: id)
        case let .user(id): PublicProfileView(userID: id)
        case .badges: ProfileLibraryView(kind: .badges)
        case .settings: AppSettingsView()
        }
    }

    private func shortDate(_ value: String?) -> String { value?.prefix(16).replacingOccurrences(of: "T", with: " ") ?? "" }
    private func notificationType(_ type: String) -> String {
        ["review_result": "审核结果", "comment": "评论", "system": "系统", "follow": "关注", "like": "点赞", "message": "私信", "badge": "徽章"][type].map(L10n.string) ?? type
    }
    private func notificationIcon(_ type: String) -> String {
        ["review_result": "checkmark.seal.fill", "comment": "bubble.left.fill", "follow": "person.badge.plus", "like": "heart.fill", "message": "envelope.fill", "badge": "medal.fill"][type] ?? "bell.fill"
    }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        await loadConversations()
        await loadNotifications()
    }

    @MainActor private func loadConversations() async {
        do {
            conversations = try await APIClient.shared.get("api/conversations")
            await appModel.refreshUnreadCount()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func loadNotifications() async {
        do {
            let response: SiteNotificationResponse = try await APIClient.shared.get("api/me/notifications", query: [URLQueryItem(name: "limit", value: "100")])
            notifications = response.items
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func markRead(_ item: SiteNotification) async {
        guard !item.isRead else { return }
        if let _: APIClient.EmptyResponse = try? await APIClient.shared.send("api/me/notifications/\(item.id)/read", method: "POST") {
            if let index = notifications.firstIndex(where: { $0.id == item.id }) { notifications[index].isRead = true }
            await appModel.refreshUnreadCount()
        }
    }

    @MainActor private func markAllRead() async {
        if let _: APIClient.EmptyResponse = try? await APIClient.shared.send("api/me/notifications/read-all", method: "POST") {
            for index in notifications.indices { notifications[index].isRead = true }
            await appModel.refreshUnreadCount()
        }
    }
}

private struct ConversationThread: Decodable, Sendable {
    struct Message: Decodable, Identifiable, Sendable {
        let id: Int
        let body: String
        let mine: Bool
        let isRead: Bool
        let createdAt: String?
    }
    let id: Int
    let other: Conversation.OtherUser
    var messages: [Message]
}

struct ConversationView: View {
    @EnvironmentObject private var appModel: AppModel
    let conversation: Conversation
    @State private var thread: ConversationThread?
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 11) {
                    ForEach(thread?.messages ?? []) { message in
                        HStack(alignment: .bottom) {
                            if message.mine { Spacer(minLength: 48) }
                            VStack(alignment: message.mine ? .trailing : .leading, spacing: 4) {
                                Text(message.body)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(message.mine ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.07)), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                    .foregroundStyle(message.mine ? Color(uiColor: .systemBackground) : .primary)
                                if let date = message.createdAt {
                                    Text(date.prefix(16).replacingOccurrences(of: "T", with: " ")).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            if !message.mine { Spacer(minLength: 48) }
                        }
                        .id(message.id)
                    }
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: thread?.messages.count) { _ in
                if let id = thread?.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
        .navigationTitle(conversation.other.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .task { await load() }
        .appScreenBackground()
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(L10n.string("写点什么…"), text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.bar)
    }

    @MainActor private func load() async {
        do {
            thread = try await APIClient.shared.get("api/conversations/\(conversation.id)/messages")
            await appModel.refreshUnreadCount()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func send() async {
        struct Body: Encodable, Sendable { let body: String }
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let sent: ConversationThread.Message = try await APIClient.shared.send("api/conversations/\(conversation.id)/messages", body: Body(body: value))
            draft = ""
            if thread != nil { thread?.messages.append(sent) } else { await load() }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct NewConversationView: View {
    struct Person: Decodable, Identifiable, Sendable {
        let id: Int
        let username: String
        let displayName: String
        let avatar: String?
        let email: String?
    }
    struct Started: Decodable, Sendable { let id: Int }

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var people: [Person] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if query.count < 2 {
                EmptyStateView(L10n.string("查找摄影师"), systemImage: "person.crop.circle.badge.plus", description: L10n.string("输入昵称、用户名或邮箱的至少两个字符。"))
            }
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            ForEach(people) { person in
                Button { Task { await start(person) } } label: {
                    HStack(spacing: 12) {
                        AvatarView(urlString: person.avatar, name: person.displayName, size: 46)
                        VStack(alignment: .leading) {
                            Text(person.displayName).font(.headline)
                            Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle(L10n.string("发起私信"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L10n.string("昵称、用户名或邮箱"))
        .onSubmit(of: .search) { Task { await search() } }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.string("取消")) { dismiss() } } }
    }

    @MainActor private func search() async {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { people = []; return }
        isLoading = true
        defer { isLoading = false }
        do {
            people = try await APIClient.shared.get("api/users/search", query: [URLQueryItem(name: "q", value: query)])
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func start(_ person: Person) async {
        struct Body: Encodable, Sendable { let user_id: Int }
        do {
            let _: Started = try await APIClient.shared.send("api/conversations/start", body: Body(user_id: person.id))
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
