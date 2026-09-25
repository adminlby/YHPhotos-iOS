import SwiftUI

struct DomainSectionContent: View {
    let domain: PhotoDomain
    let photos: [Photo]
    let featured: Photo?
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        if let hero = featured ?? photos.first {
            NavigationLink { PhotoDetailView(photoID: hero.id) } label: {
                HeroPhotoView(photo: hero, height: 340)
            }
            .buttonStyle(.plain)
        }

        GlassPanel(cornerRadius: 20) {
            HStack(spacing: 0) {
                ForEach(shortcuts, id: \.0) { title, icon in
                    Button { } label: {
                        VStack(spacing: 8) {
                            Image(systemName: icon).font(.title2).foregroundStyle(AppTheme.accent)
                            Text(title).font(.caption).foregroundStyle(.primary)
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
            Menu("最新", systemImage: "arrow.up.arrow.down") {
                Button("最新") { }
                Button("热门") { }
                Button("最多喜欢") { }
            }
            .font(.subheadline)
        }

        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(photos) { photo in
                NavigationLink { PhotoDetailView(photoID: photo.id) } label: { PhotoGridCard(photo: photo) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var shortcuts: [(String, String)] {
        switch domain {
        case .aviation:
            [(L10n.string("机型"), "airplane"), (L10n.string("注册号"), "list.clipboard"),
             (L10n.string("航空公司"), "bird.fill"), (L10n.string("机场"), "airport.extreme.tower")]
        case .railway:
            [(L10n.string("车型"), "tram.fill"), (L10n.string("车次"), "list.clipboard"),
             (L10n.string("路局"), "building.2.fill"), (L10n.string("车站"), "building.columns.fill")]
        case .flightSim:
            [(L10n.string("平台"), "gamecontroller.fill"), (L10n.string("机模"), "airplane"),
             (L10n.string("涂装"), "paintbrush.fill"), (L10n.string("场景"), "mountain.2.fill")]
        }
    }
}
