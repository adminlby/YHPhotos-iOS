import SwiftUI

struct DomainSectionContent: View {
    let domain: PhotoDomain
    let photos: [Photo]
    let featured: Photo?
    @State private var sort = "new"
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        if let hero = featured ?? photos.first {
            NavigationLink { PhotoDetailView(photoID: hero.id) } label: {
                HeroPhotoView(photo: hero)
            }
            .buttonStyle(.plain)
        }

        GlassPanel(cornerRadius: 20) {
            HStack(spacing: 0) {
                ForEach(shortcuts, id: \.title) { shortcut in
                    NavigationLink {
                        SearchView(
                            domain: domain,
                            kind: shortcut.searchKind,
                            title: shortcut.title,
                            prompt: shortcut.prompt
                        )
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: shortcut.icon).font(.title2).foregroundStyle(AppTheme.accent)
                            Text(shortcut.title).font(.caption).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 16)
        }

        HStack {
            Text(L10n.format("最新%@作品", domain.title)).font(.title2.bold())
            Spacer()
            Menu(sortTitle, systemImage: "arrow.up.arrow.down") {
                Button("最新") { sort = "new" }
                Button("热门") { sort = "views" }
                Button("最多喜欢") { sort = "likes" }
            }
            .font(.subheadline)
        }

        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(sortedPhotos) { photo in
                NavigationLink { PhotoDetailView(photoID: photo.id) } label: { PhotoGridCard(photo: photo) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var sortTitle: String { ["new": "最新", "views": "热门", "likes": "最多喜欢"][sort].map(L10n.string) ?? L10n.string("最新") }
    private var sortedPhotos: [Photo] {
        switch sort {
        case "views": photos.sorted { $0.views > $1.views }
        case "likes": photos.sorted { $0.likes > $1.likes }
        default: photos.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private struct Shortcut {
        let title: String
        let icon: String
        let searchKind: String
        let prompt: String
    }

    private var shortcuts: [Shortcut] {
        switch domain {
        case .aviation:
            [Shortcut(title: L10n.string("机型"), icon: "airplane", searchKind: "aircraft_type", prompt: L10n.string("搜索机型")),
             Shortcut(title: L10n.string("注册号"), icon: "list.clipboard", searchKind: "registration", prompt: L10n.string("搜索注册号")),
             Shortcut(title: L10n.string("航空公司"), icon: "bird.fill", searchKind: "airline", prompt: L10n.string("搜索航空公司")),
             Shortcut(title: L10n.string("机场"), icon: "airport.extreme.tower", searchKind: "airport", prompt: L10n.string("搜索机场"))]
        case .railway:
            [Shortcut(title: L10n.string("车型"), icon: "tram.fill", searchKind: "train", prompt: L10n.string("搜索车型")),
             Shortcut(title: L10n.string("车次"), icon: "list.clipboard", searchKind: "train", prompt: L10n.string("搜索车次")),
             Shortcut(title: L10n.string("路局"), icon: "building.2.fill", searchKind: "train", prompt: L10n.string("搜索路局")),
             Shortcut(title: L10n.string("车站"), icon: "building.columns.fill", searchKind: "train", prompt: L10n.string("搜索车站"))]
        case .flightSim:
            [Shortcut(title: L10n.string("平台"), icon: "gamecontroller.fill", searchKind: "title", prompt: L10n.string("搜索模拟平台")),
             Shortcut(title: L10n.string("机模"), icon: "airplane", searchKind: "aircraft_type", prompt: L10n.string("搜索机模")),
             Shortcut(title: L10n.string("涂装"), icon: "paintbrush.fill", searchKind: "title", prompt: L10n.string("搜索涂装")),
             Shortcut(title: L10n.string("场景"), icon: "mountain.2.fill", searchKind: "title", prompt: L10n.string("搜索场景"))]
        }
    }
}
