import SwiftUI

enum ProfileLibraryKind: String, Identifiable {
    case favorites
    case collections
    case badges
    case spotting
    var id: String { rawValue }
    var title: String {
        switch self {
        case .favorites: L10n.string("收藏")
        case .collections: L10n.string("图集")
        case .badges: L10n.string("徽章")
        case .spotting: L10n.string("收集册")
        }
    }
}

private struct PhotoCollection: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let visibility: String
    let photoCount: Int
    let cover: String?
}

private struct PhotoCollectionDetail: Decodable, Sendable {
    let id: Int
    let title: String
    let description: String?
    let visibility: String
    let photoCount: Int
    let photos: [Photo]
}

private struct SpottingSummary: Decodable, Sendable {
    let domain: String
    let cards: [SpottingCard]
}

private struct SpottingList: Decodable, Sendable {
    struct Item: Decodable, Identifiable, Sendable {
        let id: Int?
        let title: String
        let sub: String?
        let myCount: Int
        let thumb: String?
        var stableID: String { "\(id.map(String.init) ?? "text")-\(title)" }
    }
    let kind: String
    let label: String
    let domain: String
    let total: Int
    let items: [Item]
}

struct ProfileLibraryView: View {
    let kind: ProfileLibraryKind
    @State private var photos: [Photo] = []
    @State private var collections: [PhotoCollection] = []
    @State private var badges: [UserBadge] = []
    @State private var spotting: [SpottingCard] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                switch kind {
                case .favorites:
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(photos) { photo in
                            NavigationLink { PhotoDetailView(photoID: photo.id) } label: { PhotoGridCard(photo: photo) }
                                .buttonStyle(.plain)
                        }
                    }
                case .collections:
                    ForEach(collections) { collection in
                        NavigationLink { CollectionDetailView(collection: collection) } label: { collectionRow(collection) }
                            .buttonStyle(.plain)
                    }
                case .badges:
                    ForEach(badges) { badge in
                        NavigationLink { BadgeDetailView(badge: badge) } label: { badgeRow(badge) }.buttonStyle(.plain)
                    }
                case .spotting:
                    ForEach(spotting) { item in
                        NavigationLink { SpottingDetailView(card: item) } label: { spottingRow(item) }
                            .buttonStyle(.plain)
                    }
                }
                if isEmpty && !isLoading && errorMessage == nil {
                    EmptyStateView(L10n.string("暂无内容"), systemImage: emptyIcon)
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
            }
            .padding(18)
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .appScreenBackground()
    }

    private var isEmpty: Bool {
        switch kind {
        case .favorites: photos.isEmpty
        case .collections: collections.isEmpty
        case .badges: badges.isEmpty
        case .spotting: spotting.isEmpty
        }
    }
    private var emptyIcon: String {
        switch kind { case .favorites: "bookmark"; case .collections: "square.stack.3d.up"; case .badges: "medal"; case .spotting: "scope" }
    }

    private func collectionRow(_ value: PhotoCollection) -> some View {
        HStack(spacing: 13) {
            RemoteImage(url: URL(string: value.cover ?? ""))
                .frame(width: 96, height: 70).clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) {
                Text(value.title).font(.headline)
                Label(L10n.format("%d 件作品", value.photoCount), systemImage: "photo.on.rectangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: value.visibility == "public" ? "globe" : "lock.fill").foregroundStyle(.secondary)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(10).background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18))
    }

    private func badgeRow(_ badge: UserBadge) -> some View {
        HStack(spacing: 14) {
            BadgeIconView(icon: badge.icon, size: 26)
                .frame(width: 48, height: 48).background(Color.yellow.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(badge.name).font(.headline)
                if let description = badge.description { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(14).background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18))
    }

    private func spottingRow(_ item: SpottingCard) -> some View {
        HStack {
            Image(systemName: "scope").foregroundStyle(AppTheme.accent)
            Text(item.label).font(.headline)
            Spacer()
            Text(item.total.map { "\(item.got) / \($0)" } ?? item.got.formatted()).monospacedDigit()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16).background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18))
    }

    private func reload() { Task { await load() } }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            switch kind {
            case .favorites:
                photos = try await APIClient.shared.get("api/me/favorites")
            case .collections:
                collections = try await APIClient.shared.get("api/me/collections")
            case .badges:
                badges = try await APIClient.shared.get("api/me/badges")
            case .spotting:
                let aviation: SpottingSummary = try await APIClient.shared.get("api/me/spotting", query: [URLQueryItem(name: "domain", value: "aviation")])
                let railway: SpottingSummary = try await APIClient.shared.get("api/me/spotting", query: [URLQueryItem(name: "domain", value: "railway")])
                spotting = aviation.cards + railway.cards
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct SpottingDetailView: View {
    let card: SpottingCard
    @State private var result: SpottingList?
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(result?.items ?? [], id: \.stableID) { item in
                    NavigationLink {
                        if let id = item.id {
                            EntityGalleryView(kind: card.kind, entityID: id)
                        } else {
                            SearchView(
                                domain: result?.domain == "railway" ? .railway : .aviation,
                                kind: searchKind(card.kind),
                                title: item.title,
                                prompt: item.title,
                                query: item.title
                            )
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack(alignment: .topTrailing) {
                                RemoteImage(url: URL(string: item.thumb ?? ""))
                                    .aspectRatio(4 / 3, contentMode: .fill)
                                    .clipped()
                                Text("×\(item.myCount)")
                                    .font(.caption.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.black.opacity(0.58), in: Capsule())
                                    .padding(8)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.subheadline.bold()).lineLimit(1)
                                if let sub = item.sub, !sub.isEmpty {
                                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .padding(10)
                        }
                        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
                .padding(.top, 12)
            if (result?.items.isEmpty == true) && !isLoading {
                EmptyStateView(L10n.string("暂无收集记录"), systemImage: "scope")
            }
        }
        .padding(18)
        .navigationTitle(card.label)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .appScreenBackground()
    }

    private func reload() { Task { await load() } }
    private func searchKind(_ kind: String) -> String {
        switch kind {
        case "registration": "registration"
        case "aircraft-type": "aircraft_type"
        case "airline": "airline"
        case "airport": "airport"
        default: "train"
        }
    }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            result = try await APIClient.shared.get(
                "api/me/spotting/\(card.kind)",
                query: [URLQueryItem(name: "limit", value: "120")]
            )
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct CollectionDetailView: View {
    let collection: PhotoCollection
    @State private var detail: PhotoCollectionDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let description = detail?.description, !description.isEmpty {
                    Text(description).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(detail?.photos ?? []) { photo in
                        NavigationLink { PhotoDetailView(photoID: photo.id) } label: { PhotoGridCard(photo: photo) }
                            .buttonStyle(.plain)
                    }
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
            }
            .padding(18)
        }
        .navigationTitle(detail?.title ?? collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .appScreenBackground()
    }

    private func reload() { Task { await load() } }
    @MainActor private func load() async {
        isLoading = true; defer { isLoading = false }
        do { detail = try await APIClient.shared.get("api/collections/\(collection.id)"); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
