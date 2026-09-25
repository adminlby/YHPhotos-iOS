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

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        ScrollView {
            if let profile {
                VStack(spacing: 22) {
                    profileHeader(profile)
                    statistics(profile)
                    if !badges.isEmpty { badgeSection }
                    if let spotting { spottingSection(spotting) }
                    photoSection
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
                    Button("分享主页", systemImage: "square.and.arrow.up") { }
                    Button("举报", systemImage: "exclamationmark.bubble", role: .destructive) { }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .task { await load() }
        .appScreenBackground()
    }

    private func profileHeader(_ value: PublicProfile) -> some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [AppTheme.accent.opacity(0.55), .purple.opacity(0.28), AppTheme.canvas],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 168)
                AvatarView(urlString: value.avatar, name: value.displayName, size: 92)
                    .overlay(Circle().stroke(AppTheme.canvas, lineWidth: 5))
                    .offset(y: 28)
            }
            .padding(.bottom, 22)

            VStack(spacing: 5) {
                HStack(spacing: 7) {
                    Text(value.displayName).font(.title2.bold())
                    if value.role != "user" {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.accent)
                    }
                }
                Text("@\(value.username) · \(roleTitle(value.role))")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let bio = value.bio, !bio.isEmpty {
                    Text(bio).font(.subheadline).multilineTextAlignment(.center).padding(.horizontal, 28)
                }
            }

            if !value.isSelf {
                HStack(spacing: 12) {
                    Button { Task { await toggleFollow() } } label: {
                        Label(L10n.string(isFollowing ? "已关注" : "关注"), systemImage: isFollowing ? "checkmark" : "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { } label: {
                        Label("私信", systemImage: "bubble.left.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
            }
        }
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
                        GlassPanel(cornerRadius: 18) {
                            VStack(spacing: 8) {
                                Image(systemName: badge.icon ?? "medal.fill")
                                    .font(.title2).foregroundStyle(.yellow)
                                Text(badge.name).font(.caption.weight(.semibold)).lineLimit(1)
                                if let count = badge.count, count > 1 {
                                    Text("×\(count)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 92, height: 90)
                        }
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
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(L10n.string("作品"), detail: photos.count.formatted())
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(photos) { photo in
                    NavigationLink { PhotoDetailView(photoID: photo.id) } label: {
                        RemoteImage(url: photo.thumbnailURL)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack { Text(title).font(.title3.bold()); Spacer(); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            .padding(.horizontal, 18)
    }

    private func stat(_ value: Int, _ title: String) -> some View {
        VStack(spacing: 4) {
            Text(value.compactCount).font(.headline).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View { Rectangle().fill(AppTheme.divider).frame(width: 1, height: 36) }

    private func spottingCard(_ item: SpottingCard, color: Color) -> some View {
        GlassPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: item.kind.contains("airport") ? "airport.extreme.tower" : "scope")
                    .foregroundStyle(color)
                Text(item.label).font(.caption).foregroundStyle(.secondary)
                Text(item.got.formatted()).font(.title3.bold()).monospacedDigit()
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
            followerCount = loadedProfile.stats.followers
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func toggleFollow() async {
        guard appModel.sessionUser != nil else { appModel.showingLogin = true; return }
        do {
            let response: FollowResponse = try await APIClient.shared.send(
                "api/users/\(userID)/follow",
                method: isFollowing ? "DELETE" : "POST"
            )
            isFollowing = response.following
            followerCount = response.followers
        } catch { errorMessage = error.localizedDescription }
    }
}
