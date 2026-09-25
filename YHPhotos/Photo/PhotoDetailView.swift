import SwiftUI

struct PhotoDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let photoID: Int
    @State private var detail: PhotoDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var commentCount = 0
    @State private var isFavorited = false
    @State private var isMutatingLike = false
    @State private var showingComments = false
    @State private var showingReport = false

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
                Menu {
                    Button(L10n.string("举报"), systemImage: "exclamationmark.bubble", role: .destructive) {
                        if appModel.sessionUser == nil { appModel.showingLogin = true } else { showingReport = true }
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingComments) {
            NavigationStack { PhotoCommentsView(photoID: photoID, commentCount: $commentCount) }
        }
        .sheet(isPresented: $showingReport) { NavigationStack { ReportView(target: .photo(photoID)) } }
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
            actionButton(isLiked ? "heart.fill" : "heart", "\(likeCount)", isLiked ? .red : .primary) { toggleLike() }
                .disabled(isMutatingLike)
            actionButton("bubble.left", "\(commentCount)", .primary) { showingComments = true }
            actionButton(isFavorited ? "bookmark.fill" : "bookmark", L10n.string("收藏"), AppTheme.accent) { Task { await toggleFavorite() } }
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
                    entityInfoRow("机型", value.aviation.aircraftType, kind: "aircraft-type", id: value.entities?.aircraftType, searchKind: "aircraft_type", domain: .aviation)
                    entityInfoRow("注册号", value.aviation.registration, kind: "registration", id: value.entities?.registration, searchKind: "registration", domain: .aviation)
                    entityInfoRow("航空公司", value.aviation.operator, kind: "airline", id: value.entities?.airline, searchKind: "airline", domain: .aviation)
                    entityInfoRow("机场", [value.aviation.airport, value.aviation.airportCode].compactMap { $0 }.joined(separator: " · "), searchValue: value.aviation.airport, kind: "airport", id: value.entities?.airport, searchKind: "airport", domain: .aviation)
                case .railway:
                    entityInfoRow("车型", value.railway.trainModel, kind: "train-model", id: value.entities?.trainModel, searchKind: "train", domain: .railway)
                    entityInfoRow("车次", value.railway.trainNumber, kind: nil, id: nil, searchKind: "train", domain: .railway)
                    entityInfoRow("路局", value.railway.depot, kind: "bureau", id: value.entities?.bureau, searchKind: "train", domain: .railway)
                    entityInfoRow("线路", value.railway.line, kind: "line", id: value.entities?.line, searchKind: "train", domain: .railway)
                    entityInfoRow("车站", value.railway.station, kind: "station", id: value.entities?.station, searchKind: "train", domain: .railway)
                case .flightSim:
                    entityInfoRow("平台", value.sim.platform, kind: nil, id: nil, searchKind: "title", domain: .flightSim)
                    entityInfoRow("机模", value.aviation.aircraftType, kind: "aircraft-type", id: value.entities?.aircraftType, searchKind: "aircraft_type", domain: .flightSim)
                    entityInfoRow("涂装", value.sim.livery, kind: nil, id: nil, searchKind: "title", domain: .flightSim)
                    entityInfoRow("插件", value.sim.addon, kind: nil, id: nil, searchKind: "title", domain: .flightSim)
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func entityInfoRow(
        _ label: String,
        _ value: String?,
        searchValue: String? = nil,
        kind: String?,
        id: Int?,
        searchKind: String,
        domain: PhotoDomain
    ) -> some View {
        if let value, !value.isEmpty {
            NavigationLink {
                if let kind, let id {
                    EntityGalleryView(kind: kind, entityID: id)
                } else {
                    SearchView(
                        domain: domain,
                        kind: searchKind,
                        title: value,
                        prompt: value,
                        query: searchValue ?? value
                    )
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.string(label)).foregroundStyle(.secondary)
                    Spacer()
                    Text(value).multilineTextAlignment(.trailing).foregroundStyle(AppTheme.accent)
                    Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
            commentCount = value.comments
            isFavorited = value.favorited
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func toggleLike() {
        guard appModel.sessionUser != nil else { appModel.showingLogin = true; return }
        guard !isMutatingLike else { return }
        let previousLiked = isLiked
        let previousCount = likeCount
        isLiked.toggle()
        likeCount = max(0, likeCount + (isLiked ? 1 : -1))
        isMutatingLike = true
        Task {
            do {
                let response: LikeResponse = try await APIClient.shared.send(
                    "api/photos/\(photoID)/like",
                    method: previousLiked ? "DELETE" : "POST"
                )
                isLiked = response.liked
                likeCount = response.likes
            } catch {
                isLiked = previousLiked
                likeCount = previousCount
                errorMessage = error.localizedDescription
            }
            isMutatingLike = false
        }
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

private struct PhotoComment: Decodable, Identifiable, Sendable {
    struct Author: Decodable, Sendable {
        let id: Int?
        let displayName: String?
        let avatar: String?
    }
    let id: Int
    let content: String
    let createdAt: String?
    let parentId: Int?
    let author: Author
}

private struct PhotoCommentsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    let photoID: Int
    @Binding var commentCount: Int
    @State private var comments: [PhotoComment] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if isLoading { ProgressView().frame(maxWidth: .infinity) }
                ForEach(comments) { comment in
                    HStack(alignment: .top, spacing: 11) {
                        AvatarView(urlString: comment.author.avatar, name: comment.author.displayName ?? "?", size: 38)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(comment.author.displayName ?? L10n.string("已注销用户"))
                                .font(.subheadline.weight(.semibold))
                            Text(comment.content).font(.body).textSelection(.enabled)
                            if let date = comment.createdAt {
                                Text(date.prefix(16).replacingOccurrences(of: "T", with: " "))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .id(comment.id)
                }
                if !isLoading && comments.isEmpty {
                    EmptyStateView(L10n.string("还没有评论"), systemImage: "bubble.left", description: L10n.string("来发表第一条评论吧。"))
                }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
            .listStyle(.plain)
            .onChange(of: comments.count) { _ in
                if let id = comments.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .navigationTitle(L10n.string("评论"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.string("完成")) { dismiss() } } }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .task { await load() }
        .appScreenBackground()
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(appModel.sessionUser == nil ? L10n.string("登录后发表评论") : L10n.string("友善地说点什么…"), text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .disabled(appModel.sessionUser == nil)
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
            }
            .disabled(appModel.sessionUser == nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.bar)
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            comments = try await APIClient.shared.get("api/photos/\(photoID)/comments")
            commentCount = comments.count
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func send() async {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            let comment: PhotoComment = try await APIClient.shared.send(
                "api/photos/\(photoID)/comments",
                body: APIClient.CommentBody(content: value)
            )
            draft = ""
            comments.append(comment)
            commentCount = comments.count
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
