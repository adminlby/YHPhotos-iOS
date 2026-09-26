import SwiftUI

private struct RankingActivityItem: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
    let type: String?
    let rankingMode: String?
    let domain: String?
    let domains: [String]?
    let status: String
    let cover: String?
    let startDate: String?
    let endDate: String?
    let entryCount: Int?
    let participantCount: Int?
    let description: String?
}

private struct ApprovedCountRank: Decodable, Identifiable, Sendable {
    let rank: Int
    let userId: Int
    let displayName: String?
    let avatar: String?
    let bio: String?
    let approvedCount: Int
    let rejectedCount: Int?
    let approvalRate: Double?
    var id: Int { userId }
}

private struct ApprovedCountEnvelope: Decodable, Sendable {
    let items: [ApprovedCountRank]
}

private struct ActivityDetailPayload: Decodable, Sendable {
    struct Entry: Decodable, Identifiable, Sendable {
        let entryId: Int
        let votes: Int
        let voted: Bool
        let mine: Bool
        let rank: Int
        let photo: Photo
        var id: Int { entryId }
    }
    struct LeaderRow: Decodable, Identifiable, Sendable {
        let rank: Int
        let userId: Int
        let displayName: String?
        let avatar: String?
        let uploadCount: Int?
        let approvedCount: Int?
        let rejectedCount: Int?
        let reviewedCount: Int?
        let pendingCount: Int?
        let approvalRate: Double?
        let eligible: Bool?
        var id: Int { userId }
    }

    let id: Int
    let name: String
    let type: String?
    let domain: String?
    let domains: [String]?
    let rankingMode: String
    let minSubmissions: Int?
    let description: String?
    let rules: String?
    let cover: String?
    let startDate: String?
    let endDate: String?
    let status: String
    let entryCount: Int
    let participantCount: Int
    let joined: Bool
    let canJoin: Bool
    let entries: [Entry]
    let leaderboard: [LeaderRow]
}

struct RankingHomeView: View {
    @State private var activities: [RankingActivityItem] = []
    @State private var approved: [ApprovedCountRank] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(L10n.string("排行榜"), L10n.string("过图贡献、热门作品与正在进行的征图活动。"))

                if !approved.isEmpty {
                    Text(L10n.string("过图贡献榜")).font(.title3.bold())
                    ForEach(approved.prefix(10)) { row in
                        NavigationLink {
                            PublicProfileView(userID: row.userId)
                        } label: {
                            GlassPanel(cornerRadius: 16) {
                                HStack(spacing: 12) {
                                    Text("#\(row.rank)")
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(AppTheme.accent)
                                        .frame(width: 36, alignment: .leading)
                                    RemoteImage(url: URL(string: row.avatar ?? ""))
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.displayName ?? L10n.string("用户")).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text(L10n.format("%d 张过图", row.approvedCount)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(L10n.string("全部活动")).font(.title3.bold())
                activityList(activities)
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage) {
                    Task { await load() }
                }
            }
            .padding(18)
        }
        .navigationTitle(L10n.string("排行榜"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .appScreenBackground()
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let list: [RankingActivityItem] = APIClient.shared.get("api/ranking")
            async let board: ApprovedCountEnvelope = APIClient.shared.get(
                "api/ranking/approved-count",
                query: [URLQueryItem(name: "limit", value: "20")]
            )
            activities = try await list
            approved = (try? await board)?.items ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ActivitiesHomeView: View {
    @State private var activities: [RankingActivityItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(L10n.string("活动与领奖"), L10n.string("征图活动、参赛与领奖入口。"))
                activityList(activities, showDescription: true)
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage) {
                    Task { await load() }
                }
                if !isLoading && errorMessage == nil && activities.isEmpty {
                    EmptyStateView(L10n.string("暂无活动"), systemImage: "flag", description: L10n.string("目前没有开放中的活动。"))
                        .padding(.vertical, 30)
                }
            }
            .padding(18)
        }
        .navigationTitle(L10n.string("活动与领奖"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .appScreenBackground()
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            activities = try await APIClient.shared.get("api/ranking")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ActivityDetailView: View {
    let activityID: Int
    @EnvironmentObject private var appModel: AppModel
    @State private var detail: ActivityDetailPayload?
    @State private var entries: [ActivityDetailPayload.Entry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var joining = false
    @State private var votingID: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let detail {
                    cover(detail)
                    meta(detail)
                    if detail.canJoin || detail.joined {
                        joinButton(detail)
                    }
                    if detail.rankingMode == "photo_vote" {
                        Text(L10n.string("参赛作品")).font(.title3.bold())
                        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(entries) { entry in
                                entryCard(entry)
                            }
                        }
                    } else if !detail.leaderboard.isEmpty {
                        Text(L10n.string("排行")).font(.title3.bold())
                        ForEach(detail.leaderboard) { row in
                            leaderRow(row, mode: detail.rankingMode)
                        }
                    }
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage) {
                    Task { await load() }
                }
            }
            .padding(18)
        }
        .navigationTitle(detail?.name ?? L10n.string("活动详情"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .appScreenBackground()
    }

    private func cover(_ detail: ActivityDetailPayload) -> some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 0) {
                if let cover = detail.cover, let url = URL(string: cover) {
                    RemoteImage(url: url)
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusChip(text: ToolUI.statusLabel(detail.status))
                        StatusChip(text: ToolUI.rankingModeLabel(detail.rankingMode))
                    }
                    if let description = detail.description, !description.isEmpty {
                        Text(description).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let rules = detail.rules, !rules.isEmpty {
                        Text(rules).font(.caption).foregroundStyle(.tertiary)
                    }
                    Text([detail.startDate, detail.endDate].compactMap { $0 }.joined(separator: " — "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
    }

    private func meta(_ detail: ActivityDetailPayload) -> some View {
        Text(detail.rankingMode == "photo_vote"
             ? L10n.format("%d 件参赛作品 · %d 位参与者", detail.entryCount, detail.participantCount)
             : L10n.format("%d 位参与者", detail.participantCount))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func joinButton(_ detail: ActivityDetailPayload) -> some View {
        Button {
            guard appModel.sessionUser != nil else { appModel.showingLogin = true; return }
            Task { await join() }
        } label: {
            Text(detail.joined ? L10n.string("已参加") : L10n.string("参加活动"))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(detail.joined ? AppTheme.elevated : AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(detail.joined ? Color.secondary : Color.white)
        }
        .buttonStyle(.plain)
        .disabled(detail.joined || joining || !detail.canJoin)
    }

    private func entryCard(_ entry: ActivityDetailPayload.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                PhotoDetailView(photoID: entry.photo.id)
            } label: {
                RemoteImage(url: entry.photo.thumbnailURL)
                    .aspectRatio(4/3, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            HStack {
                Text("#\(entry.rank)").font(.caption.weight(.bold)).foregroundStyle(AppTheme.accent)
                Spacer()
                Button {
                    guard appModel.sessionUser != nil else { appModel.showingLogin = true; return }
                    Task { await toggleVote(entry) }
                } label: {
                    Label("\(entry.votes)", systemImage: entry.voted ? "heart.fill" : "heart")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.voted ? AppTheme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(votingID != nil)
            }
        }
    }

    private func leaderRow(_ row: ActivityDetailPayload.LeaderRow, mode: String) -> some View {
        NavigationLink {
            PublicProfileView(userID: row.userId)
        } label: {
            GlassPanel(cornerRadius: 16) {
                HStack(spacing: 12) {
                    Text("#\(row.rank)").font(.headline.monospacedDigit()).foregroundStyle(AppTheme.accent).frame(width: 36, alignment: .leading)
                    RemoteImage(url: URL(string: row.avatar ?? ""))
                        .frame(width: 40, height: 40).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.displayName ?? L10n.string("用户")).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if mode == "approval_rate" {
                            Text(String(format: "%.0f%%", (row.approvalRate ?? 0) * 100)).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(L10n.format("%d 张过图", row.approvedCount ?? 0)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let payload: ActivityDetailPayload = try await APIClient.shared.get("api/ranking/\(activityID)")
            detail = payload
            entries = payload.entries
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func join() async {
        joining = true
        defer { joining = false }
        struct EmptyBody: Encodable, Sendable {}
        do {
            _ = try await APIClient.shared.send(
                "api/ranking/\(activityID)/join",
                method: "POST",
                body: EmptyBody(),
                as: APIClient.EmptyResponse.self
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleVote(_ entry: ActivityDetailPayload.Entry) async {
        votingID = entry.entryId
        defer { votingID = nil }
        struct VoteResp: Decodable, Sendable { let voted: Bool; let votes: Int }
        do {
            let resp: VoteResp = try await APIClient.shared.send(
                "api/ranking/entries/\(entry.entryId)/vote",
                method: entry.voted ? "DELETE" : "POST",
                as: VoteResp.self
            )
            entries = entries.map {
                $0.entryId == entry.entryId
                    ? ActivityDetailPayload.Entry(entryId: $0.entryId, votes: resp.votes, voted: resp.voted, mine: $0.mine, rank: $0.rank, photo: $0.photo)
                    : $0
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@ViewBuilder
private func header(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.title2.bold())
        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
    }
}

@ViewBuilder
private func activityList(_ activities: [RankingActivityItem], showDescription: Bool = false) -> some View {
    LazyVStack(spacing: 12) {
        ForEach(activities) { activity in
            NavigationLink {
                ActivityDetailView(activityID: activity.id)
            } label: {
                GlassPanel(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let cover = activity.cover, let url = URL(string: cover) {
                            RemoteImage(url: url)
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipped()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(activity.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 8) {
                                StatusChip(text: ToolUI.statusLabel(activity.status))
                                if let mode = activity.rankingMode {
                                    StatusChip(text: ToolUI.rankingModeLabel(mode))
                                }
                            }
                            Text([activity.startDate, activity.endDate].compactMap { $0 }.joined(separator: " — "))
                                .font(.caption2).foregroundStyle(.secondary)
                            if showDescription, let description = activity.description, !description.isEmpty {
                                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
