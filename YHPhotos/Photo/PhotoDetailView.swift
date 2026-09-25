import SwiftUI

struct PhotoDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let photoID: Int
    @State private var detail: PhotoDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var isFavorited = false

    var body: some View {
        ScrollView {
            if let detail {
                VStack(spacing: 20) {
                    RemoteImage(url: URL(string: detail.image), contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)

                    VStack(alignment: .leading, spacing: 16) {
                        identity(detail)
                        actionRow
                        metadata(detail)
                        if let description = detail.description, !description.isEmpty {
                            Text(description).font(.body).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
            LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
        }
        .navigationTitle("作品")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu { Button("举报", role: .destructive) { } } label: { Image(systemName: "ellipsis") }
            }
        }
        .task { await load() }
        .appScreenBackground()
    }

    private func identity(_ value: PhotoDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(value.title).font(.title2.bold())
            NavigationLink { PublicProfileView(userID: value.author.id) } label: {
                HStack(spacing: 10) {
                    AvatarView(urlString: value.author.avatar, name: value.author.displayName, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value.author.displayName).font(.headline)
                        Text(value.shotAt ?? value.domain.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        HStack {
            actionButton(isLiked ? "heart.fill" : "heart", "\(likeCount)", isLiked ? .red : .primary) { Task { await toggleLike() } }
            actionButton("bubble.left", detail.map { "\($0.comments)" } ?? "0", .primary) { }
            actionButton(isFavorited ? "bookmark.fill" : "bookmark", "收藏", AppTheme.accent) { Task { await toggleFavorite() } }
            ShareLink(item: detail?.image ?? "") { Label("分享", systemImage: "square.and.arrow.up") }
                .frame(maxWidth: .infinity)
        }
        .font(.subheadline)
    }

    private func actionButton(_ icon: String, _ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) { Image(systemName: icon).font(.title2); Text(title).font(.caption) }
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func metadata(_ value: PhotoDetail) -> some View {
        GlassPanel(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Text("拍摄信息").font(.headline).padding(.bottom, 8)
                switch value.domain {
                case .aviation:
                    infoRow("机型", value.aviation.aircraftType)
                    infoRow("注册号", value.aviation.registration)
                    infoRow("航空公司", value.aviation.operator)
                    infoRow("机场", [value.aviation.airport, value.aviation.airportCode].compactMap { $0 }.joined(separator: " · "))
                case .railway:
                    infoRow("车型", value.railway.trainModel)
                    infoRow("车次", value.railway.trainNumber)
                    infoRow("路局", value.railway.depot)
                    infoRow("车站", value.railway.station)
                case .flightSim:
                    infoRow("平台", value.sim.platform)
                    infoRow("机模", value.aviation.aircraftType)
                    infoRow("涂装", value.sim.livery)
                    infoRow("插件", value.sim.addon)
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value).multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
            .padding(.vertical, 10)
            Divider()
        }
    }

    private func reload() { Task { await load() } }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            let value: PhotoDetail = try await APIClient.shared.get("api/photos/\(photoID)")
            detail = value
            isLiked = value.liked
            likeCount = value.likes
            isFavorited = value.favorited
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func toggleLike() async {
        guard appModel.sessionUser != nil else { appModel.showingLogin = true; return }
        do {
            let response: LikeResponse = try await APIClient.shared.send(
                "api/photos/\(photoID)/like",
                method: isLiked ? "DELETE" : "POST"
            )
            isLiked = response.liked
            likeCount = response.likes
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func toggleFavorite() async {
        struct Favorite: Decodable, Sendable { let favorited: Bool }
        guard appModel.sessionUser != nil else { appModel.showingLogin = true; return }
        do {
            let response: Favorite = try await APIClient.shared.send(
                "api/photos/\(photoID)/favorite",
                method: isFavorited ? "DELETE" : "POST"
            )
            isFavorited = response.favorited
        } catch { errorMessage = error.localizedDescription }
    }
}
