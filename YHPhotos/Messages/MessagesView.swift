import SwiftUI

struct MessagesView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var conversations: [Conversation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if appModel.sessionUser == nil { signedOut }
                else if conversations.isEmpty && !isLoading && errorMessage == nil { empty }
                else { list }
            }
            .navigationTitle("消息")
            .toolbar {
                if appModel.sessionUser != nil {
                    ToolbarItem(placement: .topBarTrailing) { Button { } label: { Image(systemName: "square.and.pencil") } }
                }
            }
            .task(id: appModel.sessionUser?.id) { if appModel.sessionUser != nil { await load() } }
            .appScreenBackground()
        }
    }

    private var signedOut: some View {
        ContentUnavailableView {
            Label("登录后查看私信", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("与社区摄影师保持联系。")
        } actions: {
            Button("登录") { appModel.showingLogin = true }.buttonStyle(.borderedProminent)
        }
    }

    private var empty: some View {
        ContentUnavailableView("还没有私信", systemImage: "text.bubble", description: Text("从摄影师主页发起一段对话。"))
    }

    private var list: some View {
        List {
            ForEach(conversations) { conversation in
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
                                Text((conversation.lastMessageMine ? L10n.string("我：") : "") +
                                     (conversation.lastMessage ?? L10n.string("开始对话")))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                if conversation.unread > 0 {
                                    Text(conversation.unread > 99 ? "99+" : "\(conversation.unread)")
                                        .font(.caption2.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 3).background(.red, in: Capsule())
                                }
                            }
                        }
                    }.padding(.vertical, 5)
                }
            }
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .listStyle(.plain)
        .refreshable { await load() }
    }

    private func shortDate(_ value: String?) -> String { value?.prefix(10).description ?? "" }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            conversations = try await APIClient.shared.get("api/conversations")
            await appModel.refreshUnreadCount()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
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
    let messages: [Message]
}

private struct ConversationView: View {
    let conversation: Conversation
    @State private var thread: ConversationThread?
    @State private var draft = ""
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(thread?.messages ?? []) { message in
                            HStack {
                                if message.mine { Spacer(minLength: 50) }
                                Text(message.body)
                                    .padding(.horizontal, 13).padding(.vertical, 9)
                                    .background(message.mine ? AppTheme.accent : AppTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
                                    .foregroundStyle(message.mine ? .white : .primary)
                                if !message.mine { Spacer(minLength: 50) }
                            }.id(message.id)
                        }
                    }.padding()
                }
                .onChange(of: thread?.messages.count) { _, _ in if let id = thread?.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            HStack(spacing: 10) {
                TextField("写点什么…", text: $draft, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }.padding().background(.ultraThinMaterial)
        }
        .navigationTitle(conversation.other.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .appScreenBackground()
    }

    @MainActor private func load() async { thread = try? await APIClient.shared.get("api/conversations/\(conversation.id)/messages") }

    @MainActor
    private func send() async {
        struct Body: Encodable, Sendable { let body: String }
        struct Sent: Decodable, Sendable { let id: Int }
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isSending = true
        if let _: Sent = try? await APIClient.shared.send("api/conversations/\(conversation.id)/messages", body: Body(body: value)) {
            draft = ""
            await load()
        }
        isSending = false
    }
}
