import SwiftUI

struct SearchPerson: Decodable, Identifiable, Sendable {
    let id: Int
    let username: String
    let displayName: String
    let avatar: String?
    let role: String
}

enum SearchResultItem: Decodable, Identifiable, Sendable {
    case user(SearchPerson)
    case photo(Photo)

    var id: String {
        switch self {
        case let .user(user): "user-\(user.id)"
        case let .photo(photo): "photo-\(photo.id)"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let user = try? container.decode(SearchPerson.self) {
            self = .user(user)
        } else {
            self = .photo(try container.decode(Photo.self))
        }
    }
}

struct SearchGroup: Decodable, Identifiable, Sendable {
    let key: String
    let label: String
    let kind: String
    let items: [SearchResultItem]
    let count: Int
    var id: String { key }
}

struct SearchResponse: Decodable, Sendable {
    let query: String
    let type: String
    let groups: [SearchGroup]
    let total: Int
}

struct SearchView: View {
    @State private var query = ""
    @State private var response: SearchResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            ForEach(response?.groups ?? []) { group in
                Section(group.label) {
                    ForEach(group.items) { item in
                        switch item {
                        case let .photo(photo):
                            NavigationLink { PhotoDetailView(photoID: photo.id) } label: {
                                photoRow(photo)
                            }
                        case let .user(user):
                            NavigationLink { PublicProfileView(userID: user.id) } label: {
                                userRow(user)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("搜索")
        .searchable(text: $query, prompt: "机型、注册号、机场、车站")
        .onSubmit(of: .search) { Task { await search() } }
        .appScreenBackground()
    }

    private func photoRow(_ photo: Photo) -> some View {
        HStack(spacing: 12) {
            RemoteImage(url: photo.thumbnailURL)
                .frame(width: 92, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.title).font(.headline).lineLimit(1)
                Text(photo.primaryMetadata).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func userRow(_ user: SearchPerson) -> some View {
        HStack(spacing: 12) {
            AvatarView(urlString: user.avatar, name: user.displayName, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName).font(.headline).lineLimit(1)
                Text("@\(user.username)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if user.role != "user" {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.accent)
            }
        }
    }

    @MainActor
    private func search() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            response = try await APIClient.shared.get("api/search", query: [URLQueryItem(name: "q", value: query)])
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}
