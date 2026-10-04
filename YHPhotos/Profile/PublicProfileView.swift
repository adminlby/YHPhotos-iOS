import SwiftUI

struct PublicProfileView: View {
    @EnvironmentObject private var appModel: AppModel
    let userID: Int
    @State private var profile: PublicProfile?
    @State private var badges: [UserBadge] = []
    @State private var photos: [Photo] = []
    @State private var spotting: PublicSpottingSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFollowing = false
    @State private var followerCount = 0
    @State private var startedConversation: Conversation?
    @State private var isStartingConversation = false
    @State private var showingReport = false
    @State private var isBlocked = false
    @State private var isMutatingBlock = false
    @State private var showingBlockConfirmation = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            if let profile {
                VStack(spacing: 22) {
                    profileHeader(profile)
                    if isBlocked {
                        blockedNotice
                    } else {
                        statistics(profile)
                        if !badges.isEmpty { badgeSection }
                        if let spotting { spottingSection(spotting) }
                        photoSection
                    }
                }
                .padding(.bottom, 28)
            }
            LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
        }
        .navigationTitle(profile?.displayName ?? L10n.string("用户"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: URL(string: "https://www.yhphotos.top/user/\(userID)")!) {
                        Label(L10n.string("分享主页"), systemImage: "square.and.arrow.up")
                    }
                    if let profile, !profile.isSelf {
                        Button(L10n.string("举报用户"), systemImage: "exclamationmark.bubble", role: .destructive) {
                            if appModel.sessionUser == nil { appModel.showingLogin = true } else { showingReport = true }
                        }
                        Button(
                            L10n.string(isBlocked ? "解除屏蔽" : "屏蔽用户"),
                            systemImage: isBlocked ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark",
                            role: isBlocked ? nil : .destructive
                        ) {
                            requestBlockChange()
                        }
                        .disabled(isMutatingBlock)
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingReport) { NavigationStack { ReportView(target: .user(userID)) } }
        .confirmationDialog(
            L10n.string("屏蔽此用户？"),
            isPresented: $showingBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.string("屏蔽用户"), role: .destructive) { Task { await setBlocked(true) } }
            Button(L10n.string("取消"), role: .cancel) { }
        } message: {
            Text(L10n.string("屏蔽后你们将互相取消关注，无法再发起或发送私信；该用户的内容也会在此页面隐藏。你可以稍后在设置中解除屏蔽。"))
        }
        .navigationDestination(isPresented: Binding(
            get: { startedConversation != nil },
            set: { if !$0 { startedConversation = nil } }
        )) {
            if let startedConversation { ConversationView(conversation: startedConversation, onRead: {}) }
        }
        .appScreenBackground()
    }

    private func profileHeader(_ value: PublicProfile) -> some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [AppTheme.accent.opacity(0.45), Color.cyan.opacity(0.16), AppTheme.canvas],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity)
                .frame(height: 168)
                .clipped()
                AvatarView(urlString: value.avatar, name: value.displayName, size: 92)
                    .overlay(Circle().stroke(AppTheme.canvas, lineWidth: 5))
                    .offset(y: 28)
            }
            .padding(.bottom, 22)

            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    Text(value.displayName).font(.title2.bold()).foregroundStyle(AppTheme.primaryText)
                    if value.role != "user" {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.accent)
                    }
                }
                Text("@\(value.username) · \(roleTitle(value.role))")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                if let bio = value.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }

            if !value.isSelf {
                if isBlocked {
                    Label(L10n.string("你已屏蔽此用户"), systemImage: "person.crop.circle.badge.xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 24)
                } else {
                    HStack(spacing: 12) {
                        Button { Task { await toggleFollow() } } label: {
                            Label(L10n.string(isFollowing ? "已关注" : "关注"), systemImage: isFollowing ? "checkmark" : "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button { Task { await startConversation(with: value) } } label: {
                            if isStartingConversation {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Label("私信", systemImage: "bubble.left.fill").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isStartingConversation)
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private var blockedNotice: some View {
        EmptyStateView(
            L10n.string("已隐藏此用户的内容"),
            systemImage: "eye.slash.fill",
            description: L10n.string("屏蔽关系会阻止双方发起或发送私信，并隐藏此页面上的作品与公开动态。")
        ) {
            Button {
                Task { await setBlocked(false) }
            } label: {
                if isMutatingBlock {
                    ProgressView()
                } else {
                    Label(L10n.string("解除屏蔽"), systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isMutatingBlock)
        }
        .padding(.horizontal, 18)
    }

    private func statistics(_ value: PublicProfile) -> some View {
        GlassPanel(cornerRadius: 22) {
            HStack(spacing: 0) {
                stat(value.stats.approvedPhotos, L10n.string("作品"))
                divider
                stat(value.stats.totalViews, L10n.string("浏览"))
                divider
                stat(value.stats.totalLikes, L10n.string("获赞"))
                divider
                stat(followerCount, L10n.string("关注者"))
            }
            .padding(.vertical, 18)
        }
        .padding(.horizontal, 18)
    }

    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L10n.string("徽章"), detail: L10n.format("%d 枚", badges.count))
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(badges) { badge in
                        NavigationLink {
                            BadgeDetailView(badge: badge)
                        } label: {
                            GlassPanel(cornerRadius: 18) {
                                VStack(spacing: 8) {
                                    BadgeIconView(icon: badge.icon, size: 26)
                                    Text(badge.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.primaryText)
                                        .lineLimit(1)
                                    if let count = badge.count, count > 1 {
                                        Text("×\(count)").font(.caption2).foregroundStyle(AppTheme.secondaryText)
                                    }
                                }
                                .frame(width: 92, height: 90)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func spottingSection(_ value: PublicSpottingSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L10n.string("收集进度"), detail: L10n.string("公开"))
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(value.aviation.prefix(3)) { item in spottingCard(item, color: AppTheme.accent) }
                    ForEach(value.railway.prefix(2)) { item in spottingCard(item, color: .orange) }
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(L10n.string("作品"), detail: photos.count.formatted())
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(photos) { photo in
                    NavigationLink { PhotoDetailView(photoID: photo.id) } label: {
                        PhotoGridCard(photo: photo)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.title3.bold()).foregroundStyle(AppTheme.primaryText)
            Spacer()
            Text(detail).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
        }
            .padding(.horizontal, 18)
    }

    private func stat(_ value: Int, _ title: String) -> some View {
        VStack(spacing: 4) {
            Text(value.compactCount).font(.headline).foregroundStyle(AppTheme.primaryText).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View { Rectangle().fill(AppTheme.divider).frame(width: 1, height: 36) }

    private func spottingCard(_ item: SpottingCard, color: Color) -> some View {
        GlassPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: item.kind.contains("airport") ? "airport.extreme.tower" : "scope")
                    .foregroundStyle(color)
                Text(item.label).font(.caption).foregroundStyle(AppTheme.secondaryText)
                Text(item.got.formatted()).font(.title3.bold()).foregroundStyle(AppTheme.primaryText).monospacedDigit()
            }
            .frame(width: 104, alignment: .leading)
            .padding(14)
        }
    }

    private func roleTitle(_ role: String) -> String {
        let key = ["admin": "管理员", "super_admin": "超级管理员", "moderator": "审核员"][role] ?? "摄影师"
        return L10n.string(key)
    }

    private func reload() { Task { await load() } }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            async let profileRequest: PublicProfile = APIClient.shared.get("api/users/\(userID)")
            async let badgesRequest: [UserBadge] = APIClient.shared.get("api/users/\(userID)/badges")
            async let photosRequest: [Photo] = APIClient.shared.get("api/users/\(userID)/photos", query: [URLQueryItem(name: "limit", value: "30")])
            async let spottingRequest: PublicSpottingSummary = APIClient.shared.get("api/users/\(userID)/spotting")
            let loadedProfile = try await profileRequest
            profile = loadedProfile
            badges = (try? await badgesRequest) ?? []
            photos = (try? await photosRequest) ?? []
            spotting = try? await spottingRequest
            isFollowing = loadedProfile.isFollowing
            isBlocked = loadedProfile.isBlocked
            followerCount = loadedProfile.stats.followers
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func toggleFollow() async {
        guard appModel.sessionUser != nil else { appModel.showingLogin = true; return }
        guard !isBlocked else { return }
        do {
            let response: FollowResponse = try await APIClient.shared.send(
                "api/users/\(userID)/follow",
                method: isFollowing ? "DELETE" : "POST"
            )
            isFollowing = response.following
            followerCount = response.followers
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func startConversation(with profile: PublicProfile) async {
        guard appModel.sessionUser != nil else { appModel.showingLogin = true; return }
        guard !isBlocked else { return }
        struct Body: Encodable, Sendable { let user_id: Int }
        struct Started: Decodable, Sendable { let id: Int }
        isStartingConversation = true
        defer { isStartingConversation = false }
        do {
            let result: Started = try await APIClient.shared.send("api/conversations/start", body: Body(user_id: profile.id))
            startedConversation = Conversation(
                id: result.id,
                other: .init(id: profile.id, displayName: profile.displayName, avatar: profile.avatar),
                lastMessage: nil,
                lastMessageMine: false,
                lastMessageAt: nil,
                unread: 0
            )
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func requestBlockChange() {
        guard appModel.sessionUser != nil else {
            appModel.showingLogin = true
            return
        }
        if isBlocked {
            Task { await setBlocked(false) }
        } else {
            showingBlockConfirmation = true
        }
    }

    @MainActor
    private func setBlocked(_ blocked: Bool) async {
        struct Response: Decodable, Sendable { let blocked: Bool }
        guard appModel.sessionUser != nil, !isMutatingBlock else { return }
        isMutatingBlock = true
        defer { isMutatingBlock = false }
        do {
            let response: Response = try await APIClient.shared.send(
                "api/users/\(userID)/block",
                method: blocked ? "POST" : "DELETE"
            )
            isBlocked = response.blocked
            if response.blocked {
                if isFollowing { followerCount = max(0, followerCount - 1) }
                isFollowing = false
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BadgeDetailView: View {
    let badge: UserBadge

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                BadgeIconView(icon: badge.icon, size: 64)
                    .frame(width: 128, height: 128)
                    .background(Color.yellow.opacity(0.13), in: Circle())
                Text(badge.name).font(.title.bold()).multilineTextAlignment(.center)
                if let description = badge.description, !description.isEmpty {
                    Text(description).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                GlassPanel(cornerRadius: 20) {
                    VStack(spacing: 12) {
                        if let category = badge.category { detailRow(L10n.string("类别"), category) }
                        if let count = badge.count { detailRow(L10n.string("获得次数"), count.formatted()) }
                        if let awardedAt = badge.awardedAt { detailRow(L10n.string("最近获得"), awardedAt.prefix(10).description) }
                    }
                    .padding(18)
                }
            }
            .padding(24)
        }
        .navigationTitle(L10n.string("徽章详情"))
        .navigationBarTitleDisplayMode(.inline)
        .appScreenBackground()
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value) }
            .font(.subheadline)
    }
}
