import SwiftUI

private enum DiscoverFilter: String, CaseIterable, Identifiable {
    case featured
    case aviation
    case railway
    case flightSim
    var id: String { rawValue }
    var title: String {
        switch self {
        case .featured: L10n.string("精选")
        case .aviation: L10n.string("航空")
        case .railway: L10n.string("铁路")
        case .flightSim: L10n.string("模拟飞行")
        }
    }
    var domain: PhotoDomain? {
        switch self {
        case .featured: nil
        case .aviation: .aviation
        case .railway: .railway
        case .flightSim: .flightSim
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var filter: DiscoverFilter = .featured
    @State private var featured: [Photo] = []
    @State private var photos: [Photo] = []
    @State private var stats: CommunityStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingSearch = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    filterPicker
                    if filter == .featured {
                        featuredContent
                    } else if let domain = filter.domain {
                        DomainSectionContent(domain: domain, photos: photos, featured: featured.first)
                    }
                    LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(filter == .featured ? L10n.string("发现") : filter.title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let user = appModel.sessionUser {
                        AvatarView(urlString: nil, name: user.displayName, size: 34)
                            .onTapGesture { appModel.select(.profile) }
                    }
                    Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                        .buttonBorderShape(.circle)
                }
            }
            .navigationDestination(isPresented: $showingSearch) { SearchView() }
            .refreshable { await load() }
            .task(id: filter) { await load() }
            .appScreenBackground()
        }
    }

    private var filterPicker: some View {
        Picker("内容分区", selection: $filter) {
            ForEach(DiscoverFilter.allCases) { item in Text(item.title).tag(item) }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var featuredContent: some View {
        if let hero = featured.first ?? photos.first {
            NavigationLink { PhotoDetailView(photoID: hero.id) } label: {
                HeroPhotoView(photo: hero, height: 360)
            }
            .buttonStyle(.plain)
        }

        if let stats { CommunityStatsCard(stats: stats) }

        HStack {
            Text("正在发生").font(.title2.bold())
            Spacer()
            NavigationLink { MapBrowserView() } label: {
                Label("地图", systemImage: "map.fill").font(.subheadline.weight(.semibold))
            }
        }

        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(photos) { photo in
                NavigationLink { PhotoDetailView(photoID: photo.id) } label: { PhotoGridCard(photo: photo) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func reload() { Task { await load() } }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let domainQuery = filter.domain.map { [URLQueryItem(name: "domain", value: $0.rawValue)] } ?? []
            featured = try await APIClient.shared.get("api/photos/featured", query: [URLQueryItem(name: "limit", value: "8")])
            photos = try await APIClient.shared.get(
                "api/photos",
                query: domainQuery + [URLQueryItem(name: "limit", value: "24"), URLQueryItem(name: "sort", value: "new")]
            )
            if filter == .featured {
                stats = try await APIClient.shared.get("api/stats")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct CommunityStatsCard: View {
    let stats: CommunityStats

    var body: some View {
        GlassPanel(cornerRadius: 22) {
            VStack(spacing: 14) {
                HStack {
                    Text("社区概况").font(.headline)
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("实时").font(.caption).foregroundStyle(.green)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                HStack {
                    metric(stats.pendingPhotos, L10n.string("待审核"))
                    Rectangle().fill(AppTheme.divider).frame(width: 1, height: 38)
                    metric(stats.totalUsers, L10n.string("用户"))
                    Rectangle().fill(AppTheme.divider).frame(width: 1, height: 38)
                    metric(stats.totalPhotos, L10n.string("作品"))
                }
                Divider()
                HStack {
                    Text("今日 ").foregroundStyle(.secondary) +
                    Text(L10n.format("+%d 作品 · +%d 用户", stats.todayPhotos, stats.todayUsers))
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                    Text(L10n.format("%d 位审核员在线", stats.onlineModerators.count))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .padding(18)
        }
    }

    private func metric(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value.formatted()).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
