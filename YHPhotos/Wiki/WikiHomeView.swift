import SwiftUI

private enum WikiCategory: String, CaseIterable, Identifiable {
    case airlines
    case airports
    case types
    case registrations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .airlines: L10n.string("航空公司")
        case .airports: L10n.string("机场")
        case .types: L10n.string("机型")
        case .registrations: L10n.string("飞机")
        }
    }
    var endpoint: String {
        switch self {
        case .airlines: "airlines"
        case .airports: "airports"
        case .types: "aircraft-types"
        case .registrations: "registrations"
        }
    }
    var icon: String {
        switch self {
        case .airlines: "bird.fill"
        case .airports: "airport.extreme.tower"
        case .types: "airplane"
        case .registrations: "number"
        }
    }
}

private struct WikiEntry: Decodable, Identifiable, Sendable {
    let name: String?
    let model: String?
    let registration: String?
    let cover: String?
    let photoCount: Int
    let airframeCount: Int?
    let airlineCount: Int?
    let typeCount: Int?
    let country: String?
    let city: String?
    let iata: String?
    let icao: String?
    let manufacturer: String?
    let type: String?
    let `operator`: String?

    var id: String { title }
    var title: String { name ?? model ?? registration ?? L10n.string("未知") }
    var subtitle: String {
        [manufacturer, `operator`, city, country, iata, icao, type].compactMap { $0 }.prefix(3).joined(separator: " · ")
    }
}

private struct WikiDetailPayload: Decodable, Sendable {
    struct Profile: Decodable, Sendable {
        let nameEn: String?
        let country: String?
        let city: String?
        let province: String?
        let iata: String?
        let icao: String?
        let callsign: String?
        let manufacturer: String?
        let type: String?
        let `operator`: String?
        let msn: String?
        let firstFlight: String?
        let delivery: String?
        let status: String?
        let description: String?
    }

    struct Stats: Decodable, Sendable {
        let photos: Int?
        let shooters: Int?
        let airframes: Int?
        let airlines: Int?
        let types: Int?
        let firstSeen: String?
        let lastSeen: String?
    }

    let name: String?
    let model: String?
    let registration: String?
    let profile: Profile?
    let stats: Stats?
    let photos: [Photo]?
    let recentPhotos: [Photo]?
    let currentOperator: String?
}

struct WikiHomeView: View {
    @State private var category: WikiCategory = .airlines
    @State private var entries: [WikiEntry] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                intro
                categoryStrip
                HStack {
                    Text(category.title).font(.title2.bold())
                    Spacer()
                    Text("按社区作品自动更新").font(.caption).foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 12) {
                    ForEach(entries) { entry in
                        NavigationLink {
                            WikiEntryDetailView(category: category, entry: entry)
                        } label: {
                            entryRow(entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
        }
        .navigationTitle(L10n.string("百科"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L10n.format("搜索%@", category.title))
        .onSubmit(of: .search) { reload() }
        .onChange(of: category) { _ in query = ""; reload() }
        .task { await load() }
        .appScreenBackground()
    }

    private var intro: some View {
        GlassPanel(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "books.vertical.fill").font(.title).foregroundStyle(AppTheme.accent)
                Text("由每一张作品构成的百科").font(.title3.bold())
                Text("从航空公司、机场、机型到每一架飞机，资料与社区作品相互连接。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [AppTheme.accent.opacity(0.22), Color.cyan.opacity(0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }.padding(.top, 4)
    }

    private var categoryStrip: some View {
        HStack(spacing: 9) {
            ForEach(WikiCategory.allCases) { item in
                Button { category = item } label: {
                    VStack(spacing: 7) {
                        Image(systemName: item.icon).font(.title3)
                        Text(item.title).font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(category == item ? .white : .secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(category == item ? AppTheme.accent : AppTheme.elevated, in: RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain)
            }
        }
    }

    private func entryRow(_ entry: WikiEntry) -> some View {
        HStack(spacing: 13) {
            RemoteImage(url: URL(string: entry.cover ?? ""))
                .frame(width: 104, height: 74).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title).font(.headline).lineLimit(1)
                if !entry.subtitle.isEmpty { Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 12) {
                    Label(L10n.format("%d 作品", entry.photoCount), systemImage: "photo")
                    if let count = entry.airframeCount { Label(L10n.format("%d 架", count), systemImage: "airplane") }
                    if let count = entry.airlineCount { Label(L10n.format("%d 航司", count), systemImage: "building.2") }
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(10).background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18))
    }

    private func reload() { Task { await load() } }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            entries = try await APIClient.shared.get(
                "api/wiki/\(category.endpoint)",
                query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "40")]
            )
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct WikiEntryDetailView: View {
    let category: WikiCategory
    let entry: WikiEntry
    @State private var payload: WikiDetailPayload?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let payload {
                    if let stats = payload.stats { statistics(stats) }
                    profile(payload.profile)
                    let photos = payload.photos ?? payload.recentPhotos ?? []
                    if !photos.isEmpty {
                        Text(L10n.string("相关作品")).font(.title2.bold())
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(photos) { photo in
                                NavigationLink { PhotoDetailView(photoID: photo.id) } label: {
                                    PhotoGridCard(photo: photo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
            }
            .padding(18)
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .appScreenBackground()
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { RemoteImage(url: URL(string: entry.cover ?? "")) }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(.title.bold()).foregroundStyle(.white)
                if !entry.subtitle.isEmpty {
                    Text(entry.subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.78))
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func statistics(_ stats: WikiDetailPayload.Stats) -> some View {
        GlassPanel(cornerRadius: 20) {
            HStack(spacing: 0) {
                stat(stats.photos, L10n.string("作品"))
                stat(stats.airframes ?? stats.shooters, stats.airframes == nil ? L10n.string("摄影师") : L10n.string("飞机"))
                stat(stats.airlines ?? stats.types, stats.airlines == nil ? L10n.string("机型") : L10n.string("航空公司"))
            }
            .padding(.vertical, 16)
        }
    }

    private func stat(_ value: Int?, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text((value ?? 0).formatted()).font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func profile(_ value: WikiDetailPayload.Profile?) -> some View {
        if let value {
            let rows: [(String, String?)] = [
                (L10n.string("英文名"), value.nameEn), ("IATA / ICAO", [value.iata, value.icao].compactMap { $0 }.joined(separator: " / ")),
                (L10n.string("制造商"), value.manufacturer), (L10n.string("国家或地区"), value.country),
                (L10n.string("城市"), value.city), (L10n.string("运营方"), value.operator),
                ("MSN", value.msn), (L10n.string("首飞"), value.firstFlight),
                (L10n.string("交付"), value.delivery), (L10n.string("状态"), value.status),
            ].filter { !($0.1 ?? "").isEmpty }
            if !rows.isEmpty || value.description != nil {
                GlassPanel(cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.0).foregroundStyle(.secondary)
                                Spacer()
                                Text(row.1 ?? "").multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline).padding(.vertical, 9)
                            Divider()
                        }
                        if let description = value.description, !description.isEmpty {
                            Text(description).font(.subheadline).foregroundStyle(.secondary).padding(.top, 12)
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private func reload() { Task { await load() } }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let endpoint: String
        let parameter: URLQueryItem
        switch category {
        case .airlines:
            endpoint = "airline"; parameter = URLQueryItem(name: "name", value: entry.title)
        case .airports:
            endpoint = "airport"; parameter = URLQueryItem(name: "key", value: entry.title)
        case .types:
            endpoint = "aircraft-type"; parameter = URLQueryItem(name: "model", value: entry.title)
        case .registrations:
            endpoint = "aircraft"; parameter = URLQueryItem(name: "registration", value: entry.title)
        }
        do {
            payload = try await APIClient.shared.get("api/wiki/\(endpoint)", query: [parameter])
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
