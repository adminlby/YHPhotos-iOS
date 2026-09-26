import SwiftUI

private struct ForecastSitePhoto: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String?
    let thumb: String?
    let href: String
    let author: String?
    let shotAt: String?
}

private struct ForecastItem: Decodable, Identifiable, Sendable {
    let flightNumber: String?
    let callsign: String?
    let mode: String
    let typecode: String?
    let typeText: String?
    let registration: String?
    let airlineCode: String?
    let airlineName: String?
    let origin: String?
    let destination: String?
    let status: String?
    let runway: String?
    let scheduledAtIso: String?
    let estimatedDepartureIso: String?
    let estimatedArrivalIso: String?
    let departureIso: String?
    let arrivalIso: String?
    let score: Double
    let tags: [String]
    let goodTypes: [String]?
    let reasons: [String]
    let liveryName: String?
    let isSpecialLivery: Bool?
    let photos: [ForecastSitePhoto]?
    let equipmentChange: EquipmentChange?

    struct EquipmentChange: Decodable, Sendable {
        let previousTypecode: String?
        let previousFlightNumber: String?
    }

    var id: String {
        [flightNumber, registration, mode, scheduledAtIso, String(score)].compactMap { $0 }.joined(separator: "|")
    }

    var title: String {
        flightNumber ?? callsign ?? registration ?? L10n.string("航班")
    }
}

private struct ForecastResp: Decodable, Sendable {
    struct AirportInfo: Decodable, Sendable {
        let id: Int
        let name: String?
        let nameEn: String?
        let city: String?
        let iata: String?
        let icao: String?
    }
    struct Cache: Decodable, Sendable {
        let hit: Bool
        let ttlSeconds: Int
        let partialHit: Bool?
    }

    let airport: String
    let airportInfo: AirportInfo?
    let day: String
    let mode: String
    let generatedAt: String
    let totalFlights: Int
    let goodCount: Int
    let minScore: Double
    let items: [ForecastItem]
    let cache: Cache
}

struct ForecastView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var airport = ""
    @State private var day = Date()
    @State private var includeArrivals = true
    @State private var includeDepartures = true
    @State private var result: ForecastResp?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if appModel.sessionUser == nil {
                    LoginRequiredCard(message: L10n.string("登录后可查询好货预报。"))
                } else {
                    queryCard
                    if let result {
                        summaryCard(result)
                        LazyVStack(spacing: 12) {
                            ForEach(result.items) { item in
                                forecastRow(item)
                            }
                        }
                        if result.items.isEmpty && !isLoading {
                            EmptyStateView(L10n.string("暂无好货"), systemImage: "airplane", description: L10n.string("试试换一天，或同时勾选进港与离港。"))
                                .padding(.vertical, 24)
                        }
                    }
                    LoadingOrErrorView(isLoading: isLoading, error: errorMessage) {
                        Task { await query(forceRefresh: false) }
                    }
                }
            }
            .padding(18)
        }
        .navigationTitle(L10n.string("好货预报"))
        .navigationBarTitleDisplayMode(.inline)
        .appScreenBackground()
    }

    private var queryCard: some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                SuggestField(title: L10n.string("机场"), type: "airport", text: $airport)
                DatePicker(L10n.string("日期"), selection: $day, displayedComponents: .date)
                HStack(spacing: 10) {
                    modeChip(L10n.string("进港"), isOn: $includeArrivals)
                    modeChip(L10n.string("离港"), isOn: $includeDepartures)
                }
                Button {
                    Task { await query(forceRefresh: false) }
                } label: {
                    Text(isLoading ? L10n.string("查询中…") : L10n.string("查询"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canQuery ? AppTheme.accent : AppTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(canQuery ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canQuery || isLoading)
            }
            .padding(18)
        }
    }


    private func modeChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isOn.wrappedValue ? AppTheme.accent : AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(isOn.wrappedValue ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var canQuery: Bool {
        !airport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (includeArrivals || includeDepartures)
    }

    private func summaryCard(_ result: ForecastResp) -> some View {
        GlassPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.format("%d 班航班 · %d 条好货", result.totalFlights, result.goodCount))
                    .font(.subheadline.weight(.semibold))
                Text(result.cache.hit
                     ? L10n.format("缓存命中，剩余 %d 秒", result.cache.ttlSeconds)
                     : L10n.string("已拉取最新数据并缓存"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private func forecastRow(_ item: ForecastItem) -> some View {
        GlassPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(item.title).font(.headline)
                    Spacer()
                    Text(String(format: "%.0f", item.score))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(AppTheme.accent)
                }
                Text([
                    item.airlineName ?? item.airlineCode,
                    item.typeText ?? item.typecode,
                    item.registration,
                    item.mode == "arrivals" ? L10n.string("进港") : L10n.string("离港"),
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)

                let times = [
                    ToolUI.clock(item.estimatedArrivalIso ?? item.arrivalIso).map { "ETA \($0)" },
                    ToolUI.clock(item.estimatedDepartureIso ?? item.departureIso).map { "ETD \($0)" },
                    item.runway.map { "\(L10n.string("跑道")) \($0)" },
                ].compactMap { $0 }
                if !times.isEmpty {
                    Text(times.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                }

                if !item.tags.isEmpty {
                    FlowChips(items: item.tags)
                }
                if !item.reasons.isEmpty {
                    Text(item.reasons.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let photos = item.photos, !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos) { photo in
                                NavigationLink {
                                    PhotoDetailView(photoID: photo.id)
                                } label: {
                                    RemoteImage(url: URL(string: photo.thumb ?? ""))
                                        .frame(width: 72, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    @MainActor
    private func query(forceRefresh: Bool) async {
        guard canQuery else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let mode: String
        switch (includeArrivals, includeDepartures) {
        case (true, true): mode = "both"
        case (true, false): mode = "arrivals"
        case (false, true): mode = "departures"
        default: return
        }
        let dayString: String = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: day)
        }()
        do {
            var query = [
                URLQueryItem(name: "airport", value: airport.trimmingCharacters(in: .whitespacesAndNewlines)),
                URLQueryItem(name: "day", value: dayString),
                URLQueryItem(name: "mode", value: mode),
            ]
            if forceRefresh { query.append(URLQueryItem(name: "refresh", value: "true")) }
            result = try await APIClient.shared.get("api/aviation-intel/forecast", query: query)
        } catch {
            errorMessage = error.localizedDescription
            result = nil
        }
    }
}

private struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlexibleChipWrap(items: items)
    }
}

private struct FlexibleChipWrap: View {
    let items: [String]
    var body: some View {
        // Simple wrapping via LazyVGrid for iOS 16+ without custom layout.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(AppTheme.elevated, in: Capsule())
            }
        }
    }
}
