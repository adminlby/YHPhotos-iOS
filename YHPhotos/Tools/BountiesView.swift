import SwiftUI

private struct BountyListItem: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let description: String?
    let creator: String
    let registration: String?
    let airport: String?
    let airline: String?
    let rewardText: String?
    let submissionCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, description, creator, registration, airport, airline
        case rewardText = "reward_text"
        case submissionCount = "submission_count"
    }

    var targetLine: String {
        [registration, airport, airline].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct BountyDetail: Decodable, Sendable {
    struct Submission: Decodable, Identifiable, Sendable {
        let id: Int
        let photoId: Int
        let photoTitle: String
        let aircraftRegistration: String?
        let airportName: String?
        let submitter: String
        let note: String?
        let status: String

        enum CodingKeys: String, CodingKey {
            case id, submitter, note, status
            case photoId = "photo_id"
            case photoTitle = "photo_title"
            case aircraftRegistration = "aircraft_registration"
            case airportName = "airport_name"
        }
    }

    let id: Int
    let title: String
    let description: String?
    let creator: String
    let registration: String?
    let airport: String?
    let airline: String?
    let dateFrom: String?
    let dateTo: String?
    let rewardText: String?
    let status: String
    let isOwner: Bool
    let submissions: [Submission]?

    enum CodingKeys: String, CodingKey {
        case id, title, description, creator, registration, airport, airline, status, isOwner, submissions
        case dateFrom = "date_from"
        case dateTo = "date_to"
        case rewardText = "reward_text"
    }
}

struct BountiesView: View {
    @State private var items: [BountyListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(items) { item in
                    NavigationLink {
                        BountyDetailView(bountyID: item.id)
                    } label: {
                        GlassPanel(cornerRadius: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(item.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                if let description = item.description, !description.isEmpty {
                                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                                if !item.targetLine.isEmpty {
                                    Text(item.targetLine).font(.caption2).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text(item.creator).font(.caption2).foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(L10n.format("%d 份投稿", item.submissionCount)).font(.caption2).foregroundStyle(.secondary)
                                }
                                if let reward = item.rewardText, !reward.isEmpty {
                                    Text(reward).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                                }
                            }
                            .padding(14)
                        }
                    }
                    .buttonStyle(.plain)
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage) {
                    Task { await load() }
                }
                if !isLoading && errorMessage == nil && items.isEmpty {
                    EmptyStateView(L10n.string("暂无悬赏"), systemImage: "gift", description: L10n.string("还没有开放中的缺口悬赏。"))
                        .padding(.vertical, 40)
                }
            }
            .padding(18)
        }
        .navigationTitle(L10n.string("缺口悬赏"))
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
            items = try await APIClient.shared.get("api/aviation-intel/bounties")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BountyDetailView: View {
    let bountyID: Int
    @State private var detail: BountyDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let detail {
                    GlassPanel(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(detail.title).font(.title3.bold())
                            StatusChip(text: detail.status)
                            if let description = detail.description, !description.isEmpty {
                                Text(description).font(.subheadline).foregroundStyle(.secondary)
                            }
                            let meta = [detail.registration, detail.airport, detail.airline].compactMap { $0 }
                            if !meta.isEmpty {
                                Text(meta.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            if detail.dateFrom != nil || detail.dateTo != nil {
                                Text("\(detail.dateFrom ?? "?") — \(detail.dateTo ?? "?")")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let reward = detail.rewardText, !reward.isEmpty {
                                Text(reward).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                            }
                            Text(L10n.format("发起人 %@", detail.creator)).font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(18)
                    }

                    if let submissions = detail.submissions, !submissions.isEmpty {
                        Text(L10n.string("投稿")).font(.title3.bold())
                        ForEach(submissions) { submission in
                            NavigationLink {
                                PhotoDetailView(photoID: submission.photoId)
                            } label: {
                                GlassPanel(cornerRadius: 16) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(submission.photoTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text([submission.submitter, submission.aircraftRegistration, submission.airportName].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                        StatusChip(text: submission.status)
                                    }
                                    .padding(14)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage) {
                    Task { await load() }
                }
            }
            .padding(18)
        }
        .navigationTitle(L10n.string("悬赏详情"))
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
            detail = try await APIClient.shared.get("api/aviation-intel/bounties/\(bountyID)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
