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
    @ObservedObject private var appAttestStatus = AppAttestRecoveryStatus.shared
    @State private var filter: DiscoverFilter = .featured
    @State private var featured: [Photo] = []
    @State private var photos: [Photo] = []
    @State private var news: [NewsItem] = []
    @State private var isNewsLoading = false
    @State private var stats: CommunityStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingSearch = false
    @State private var showingAdmin = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init() {
#if DEBUG
        if AppStoreDemo.isEnabled, AppStoreDemo.screen == .aviation {
            _filter = State(initialValue: .aviation)
        }
#endif
    }

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
                    LoadingOrErrorView(
                        isLoading: isLoading,
                        error: errorMessage,
                        loadingMessage: appAttestStatus.message,
                        retry: reload
                    )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(filter == .featured ? L10n.string("发现") : filter.title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let user = appModel.sessionUser {
                        Button { appModel.select(.profile) } label: {
                            AvatarView(urlString: user.avatar, name: user.displayName, size: 34, filename: user.avatarFilename)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.string("个人中心"))
                    }
                    if let admin = appModel.adminIdentity {
                        Button { showingAdmin = true } label: {
                            Image(systemName: "lock.shield.fill")
                        }
                        .accessibilityLabel(L10n.string("管理后台"))
                        .help(L10n.format("管理后台 · %@", admin.roleLabel))
                    }
                    Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                }
            }
            .navigationDestination(isPresented: $showingSearch) { SearchView() }
            .fullScreenCover(isPresented: $showingAdmin, onDismiss: {
                // Closing the console must not put the whole app back into its
                // launch/restoration state. Only revalidate the admin entry in
                // case the current account's permissions changed.
                Task { await appModel.refreshAdminAccess() }
            }) {
                if let admin = appModel.adminIdentity {
                    AdminConsoleView(identity: admin)
                }
            }
            .refreshable {
                async let contentRefresh: Void = load()
                async let adminRefresh: Void = appModel.refreshAdminAccess()
                _ = await (contentRefresh, adminRefresh)
            }
            .task(id: filter) { await load() }
            .task(id: appModel.sessionUser?.id) { await appModel.refreshAdminAccess() }
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
        let heroPhotos = featured.isEmpty ? Array(photos.prefix(1)) : featured
        if !heroPhotos.isEmpty {
            HeroCarouselView(photos: heroPhotos)
        }

        if let stats { CommunityStatsCard(stats: stats) }

        HStack {
            Text("正在发生").font(.title2.bold())
            Spacer()
            NavigationLink { MapBrowserView() } label: {
                Label("地图", systemImage: "map.fill").font(.subheadline.weight(.semibold))
            }
        }

        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
            ForEach(photos) { photo in
                NavigationLink { PhotoDetailView(photoID: photo.id) } label: { PhotoGridCard(photo: photo) }
                    .buttonStyle(.plain)
            }
        }

        newsSection
    }

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.string("资讯"), systemImage: "newspaper.fill")
                    .font(.title2.bold())
                Spacer()
                Text(L10n.string("社区动态与行业消息"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isNewsLoading && news.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.string("正在加载资讯…"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18))
            } else if news.isEmpty {
                Label(L10n.string("暂时没有新资讯"), systemImage: "newspaper")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(news) { item in
                            NavigationLink {
                                NewsDetailView(item: item)
                            } label: {
                                NewsCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func reload() { Task { await load() } }

    @MainActor
    private func load() async {
        isLoading = true
        isNewsLoading = filter == .featured
        errorMessage = nil
        do {
            let domainQuery = filter.domain.map { [URLQueryItem(name: "domain", value: $0.rawValue)] } ?? []
            async let nextFeatured: [Photo] = APIClient.shared.get(
                "api/photos/featured",
                query: [URLQueryItem(name: "limit", value: "8")]
            )
            async let nextPhotos: [Photo] = APIClient.shared.get(
                "api/photos",
                query: domainQuery + [URLQueryItem(name: "limit", value: "24"), URLQueryItem(name: "sort", value: "new")]
            )
            if filter == .featured {
                async let nextStats: CommunityStats = APIClient.shared.get("api/stats")
                async let nextNews = fetchNews()
                let values = try await (nextFeatured, nextPhotos, nextStats, nextNews)
                featured = values.0
                photos = values.1
                stats = values.2
                news = values.3
            } else {
                let values = try await (nextFeatured, nextPhotos)
                featured = values.0
                photos = values.1
                stats = nil
                news = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        isNewsLoading = false
    }

    private func fetchNews() async -> [NewsItem] {
        let response: NewsResponse? = try? await APIClient.shared.get(
            "api/news",
            query: [URLQueryItem(name: "limit", value: "8")]
        )
        return response?.items ?? []
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
                    (Text("今日 ").foregroundColor(.secondary) +
                    Text(L10n.format("+%d 作品 · +%d 用户", stats.todayPhotos, stats.todayUsers))
                        .foregroundColor(AppTheme.accent))
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
