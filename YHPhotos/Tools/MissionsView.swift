import SwiftUI

private struct MissionItem: Decodable, Identifiable, Sendable {
    let id: Int
    let registration: String
    let `operator`: String?
    let aircraftType: String?
    let status: String?
    let captured: Bool
    let rarityScore: Double
    let historyScore: Double
    let priorityScore: Double
    let reasons: [String]
    let eventType: String?
    let eventDate: String?

    enum CodingKeys: String, CodingKey {
        case id, registration, status, captured, rarityScore, historyScore, priorityScore, reasons
        case `operator`
        case aircraftType = "aircraft_type"
        case eventType = "event_type"
        case eventDate = "event_date"
    }
}

private struct CoverageGap: Decodable, Identifiable, Sendable {
    let registration: String
    let `operator`: String?
    let aircraftType: String?
    let photoCount: Int
    let coveredYears: Int

    var id: String { registration }

    enum CodingKeys: String, CodingKey {
        case registration
        case `operator`
        case aircraftType = "aircraft_type"
        case photoCount = "photo_count"
        case coveredYears = "covered_years"
    }
}

private struct MissionResp: Decodable, Sendable {
    struct Progress: Decodable, Sendable {
        let total: Int
        let captured: Int
        let missing: Int
        let percent: Double
        let airline: String?
    }
    struct AirportType: Decodable, Identifiable, Sendable {
        let aircraftType: String
        let recentPhotos: Int
        let airframes: Int
        let captured: Bool
        let priorityScore: Double
        let reason: String
        var id: String { aircraftType }

        enum CodingKeys: String, CodingKey {
            case captured, priorityScore, reason
            case aircraftType = "aircraft_type"
            case recentPhotos = "recent_photos"
            case airframes
        }
    }

    let fleet: [MissionItem]
    let fleetProgress: Progress
    let airportTypes: [AirportType]
    let upcoming: [MissionItem]
    let coverageGaps: [CoverageGap]
    let authenticated: Bool
}

private struct WatchItem: Decodable, Identifiable, Sendable {
    let registryId: Int
    let registration: String
    let `operator`: String?
    let status: String?
    let note: String?
    let completedAt: String?

    var id: Int { registryId }

    enum CodingKeys: String, CodingKey {
        case registration, status, note
        case `operator`
        case registryId = "registry_id"
        case completedAt = "completed_at"
    }
}

struct MissionsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var airline = ""
    @State private var airport = ""
    @State private var data: MissionResp?
    @State private var watchlist: [WatchItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                filterCard
                if let data {
                    progressCard(data.fleetProgress)
                    section(L10n.string("机队缺口"), items: data.fleet.filter { !$0.captured })
                    if !data.upcoming.isEmpty {
                        section(L10n.string("近期动态"), items: data.upcoming)
                    }
                    if !data.coverageGaps.isEmpty {
                        gapsSection(data.coverageGaps)
                    }
                    if !watchlist.isEmpty {
                        watchSection
                    }
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage) {
                    Task { await load() }
                }
            }
            .padding(18)
        }
        .navigationTitle(L10n.string("拍摄任务"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .appScreenBackground()
    }

    private var filterCard: some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SuggestField(title: L10n.string("航空公司（可选）"), type: "airline", text: $airline)
                SuggestField(title: L10n.string("机场（可选）"), type: "airport", text: $airport)
                Button {
                    Task { await load() }
                } label: {
                    Text(L10n.string("刷新任务"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
        }
    }

    private func progressCard(_ progress: MissionResp.Progress) -> some View {
        GlassPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(progress.airline ?? L10n.string("机队进度")).font(.headline)
                ProgressView(value: min(max(progress.percent / 100, 0), 1))
                Text(L10n.format("已拍 %d / 共 %d · 缺口 %d", progress.captured, progress.total, progress.missing))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private func section(_ title: String, items: [MissionItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            if items.isEmpty {
                Text(L10n.string("暂无条目")).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(40)) { item in
                    missionRow(item)
                }
            }
        }
    }

    private func missionRow(_ item: MissionItem) -> some View {
        GlassPanel(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.registration).font(.headline)
                    Spacer()
                    Text(String(format: "%.0f", item.priorityScore))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                }
                Text([item.operator, item.aircraftType, item.status].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if !item.reasons.isEmpty {
                    Text(item.reasons.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                }
                if let event = item.eventType {
                    Text([event, item.eventDate].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if appModel.sessionUser != nil {
                    Button {
                        Task { await toggleWatch(item) }
                    } label: {
                        Label(
                            watchlist.contains(where: { $0.registryId == item.id }) ? L10n.string("取消关注") : L10n.string("加入追踪"),
                            systemImage: "bell"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
        }
    }

    private func gapsSection(_ gaps: [CoverageGap]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("覆盖缺口")).font(.title3.bold())
            ForEach(gaps.prefix(20)) { gap in
                GlassPanel(cornerRadius: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gap.registration).font(.subheadline.weight(.semibold))
                        Text([gap.operator, gap.aircraftType].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(L10n.format("%d 张作品 · 覆盖 %d 年", gap.photoCount, gap.coveredYears))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(14)
                }
            }
        }
    }

    private var watchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("我的追踪")).font(.title3.bold())
            ForEach(watchlist) { item in
                GlassPanel(cornerRadius: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.registration).font(.subheadline.weight(.semibold))
                            Text([item.operator, item.status].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.string("移除")) {
                            Task { await removeWatch(item.registryId) }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(14)
                }
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var query: [URLQueryItem] = []
            let airlineQ = airline.trimmingCharacters(in: .whitespacesAndNewlines)
            let airportQ = airport.trimmingCharacters(in: .whitespacesAndNewlines)
            if !airlineQ.isEmpty { query.append(URLQueryItem(name: "airline", value: airlineQ)) }
            if !airportQ.isEmpty { query.append(URLQueryItem(name: "airport", value: airportQ)) }
            data = try await APIClient.shared.get("api/aviation-intel/missions", query: query)
            if appModel.sessionUser != nil {
                watchlist = (try? await APIClient.shared.get("api/aviation-intel/watchlist")) ?? []
            } else {
                watchlist = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleWatch(_ item: MissionItem) async {
        if watchlist.contains(where: { $0.registryId == item.id }) {
            await removeWatch(item.id)
            return
        }
        struct Body: Encodable, Sendable { let registryId: Int }
        _ = try? await APIClient.shared.send(
            "api/aviation-intel/watchlist",
            method: "POST",
            body: Body(registryId: item.id),
            as: APIClient.EmptyResponse.self
        )
        await load()
    }

    @MainActor
    private func removeWatch(_ registryId: Int) async {
        _ = try? await APIClient.shared.send(
            "api/aviation-intel/watchlist/\(registryId)",
            method: "DELETE",
            as: APIClient.EmptyResponse.self
        )
        await load()
    }
}
