import SwiftUI

struct EntityGalleryView: View {
    let kind: String
    let entityID: Int
    @State private var gallery: EntityGallery?
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let gallery {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(gallery.title).font(.title.bold())
                        if let subtitle = gallery.subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if !gallery.meta.isEmpty {
                        GlassPanel(cornerRadius: 20) {
                            VStack(spacing: 0) {
                                ForEach(Array(gallery.meta.enumerated()), id: \.element.id) { index, item in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(item.label).foregroundStyle(.secondary)
                                        Spacer()
                                        Text(item.value).multilineTextAlignment(.trailing)
                                    }
                                    .font(.subheadline).padding(.vertical, 10)
                                    if index < gallery.meta.count - 1 { Divider() }
                                }
                            }
                            .padding(.horizontal, 18).padding(.vertical, 8)
                        }
                    }
                    HStack {
                        Text(L10n.string("相关作品")).font(.title2.bold())
                        Spacer()
                        Text(L10n.format("%d 项", gallery.photos.count)).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(gallery.photos) { photo in
                            NavigationLink { PhotoDetailView(photoID: photo.id) } label: { PhotoGridCard(photo: photo) }
                                .buttonStyle(.plain)
                        }
                    }
                    if gallery.photos.isEmpty {
                        ContentUnavailableView(L10n.string("暂无相关作品"), systemImage: "photo.on.rectangle.angled")
                    }
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
            }
            .padding(18)
        }
        .navigationTitle(gallery?.title ?? L10n.string("实体图库"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(kind)-\(entityID)") { await load() }
        .appScreenBackground()
    }

    private func reload() { Task { await load() } }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            gallery = try await APIClient.shared.get("api/entity/\(kind)/\(entityID)")
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
