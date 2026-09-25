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

struct WikiHomeView: View {
    @State private var category: WikiCategory = .airlines
    @State private var entries: [WikiEntry] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
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
                        ForEach(entries) { entry in entryRow(entry) }
                    }
                    LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
            .navigationTitle("百科")
            .searchable(text: $query, prompt: L10n.format("搜索%@", category.title))
            .onSubmit(of: .search) { reload() }
            .onChange(of: category) { _, _ in query = ""; reload() }
            .task { await load() }
            .appScreenBackground()
        }
    }

    private var intro: some View {
        GlassPanel(cornerRadius: 24) {
            ZStack(alignment: .leading) {
                LinearGradient(colors: [AppTheme.accent.opacity(0.28), .purple.opacity(0.16), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "books.vertical.fill").font(.title).foregroundStyle(AppTheme.accent)
                    Text("由每一张作品构成的百科").font(.title3.bold())
                    Text("从航空公司、机场、机型到每一架飞机，资料与社区作品相互连接。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(20)
            }.frame(minHeight: 142)
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
