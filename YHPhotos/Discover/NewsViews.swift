import SwiftUI

struct NewsResponse: Decodable, Sendable {
    let items: [NewsItem]

    private enum CodingKeys: String, CodingKey {
        case items
        case data
    }

    init(from decoder: Decoder) throws {
        if let direct = try? decoder.singleValueContainer().decode([NewsItem].self) {
            items = direct
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let values = try container.decodeIfPresent([NewsItem].self, forKey: .items) {
            items = values
        } else {
            items = try container.decode([NewsItem].self, forKey: .data)
        }
    }
}

struct NewsItem: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let summary: String?
    let content: String?
    let source: String?
    let url: String?
    let cover: String?
    let publishedAt: String?
    let createdAt: String?
    let author: String?
    let views: Int?
    let photoId: Int?
    let photoTitle: String?
    let photoThumb: String?

    var displayDate: String? {
        let value = publishedAt ?? createdAt
        guard let value, !value.isEmpty else { return nil }
        return String(value.prefix(10))
    }

    var originalURL: URL? {
        guard let url, !url.isEmpty else { return nil }
        return URL(string: url)
    }

    var renderedContent: AttributedString? {
        guard let value = content?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return (try? AttributedString(markdown: value)) ?? AttributedString(value)
    }
}

private struct NewsDetailResponse: Decodable, Sendable {
    let item: NewsItem

    private enum CodingKeys: String, CodingKey {
        case item
        case news
        case data
    }

    init(from decoder: Decoder) throws {
        if let direct = try? NewsItem(from: decoder) {
            item = direct
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(NewsItem.self, forKey: .item) {
            item = value
        } else if let value = try container.decodeIfPresent(NewsItem.self, forKey: .news) {
            item = value
        } else {
            item = try container.decode(NewsItem.self, forKey: .data)
        }
    }
}

struct NewsCard: View {
    let item: NewsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NewsCover(item: item, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42, alignment: .topLeading)

            Text(item.summary ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .topLeading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if let source = item.source, !source.isEmpty { Text(source).lineLimit(1) }
                if item.source?.isEmpty == false, item.displayDate != nil { Text("·") }
                if let date = item.displayDate { Text(date) }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 278, height: 286, alignment: .topLeading)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.divider, lineWidth: 0.6))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct NewsListView: View {
    @State private var items: [NewsItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if !items.isEmpty {
                    ForEach(items) { item in
                        NavigationLink {
                            NewsDetailView(item: item)
                        } label: {
                            NewsListRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                } else if !isLoading && errorMessage == nil {
                    EmptyStateView(L10n.string("暂时没有新资讯"), systemImage: "newspaper")
                }

                LoadingOrErrorView(
                    isLoading: isLoading,
                    error: errorMessage,
                    loadingMessage: L10n.string("正在加载资讯…"),
                    retry: reload
                )
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(L10n.string("资讯"))
        .refreshable { await load() }
        .task { await load() }
        .appScreenBackground()
    }

    private func reload() {
        Task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: NewsResponse = try await APIClient.shared.get(
                "api/news",
                query: [URLQueryItem(name: "limit", value: "50")]
            )
            items = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct NewsDetailView: View {
    @Environment(\.openURL) private var openURL
    let item: NewsItem

    @State private var detail: NewsItem
    @State private var isLoading = false
    @State private var loadError: String?

    init(item: NewsItem) {
        self.item = item
        _detail = State(initialValue: item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NewsCover(item: detail, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text(detail.title)
                        .font(.title2.bold())
                        .textSelection(.enabled)

                    HStack(spacing: 7) {
                        if let source = detail.source, !source.isEmpty { Text(source) }
                        if detail.source?.isEmpty == false, detail.displayDate != nil { Text("·") }
                        if let date = detail.displayDate { Text(date) }
                        if let views = detail.views {
                            Text("·")
                            Label(views.formatted(), systemImage: "eye")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let summary = detail.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let content = detail.renderedContent {
                    Text(content)
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.string("正在加载资讯…"))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
                } else if detail.summary?.isEmpty != false {
                    EmptyStateView(L10n.string("暂时没有新资讯"), systemImage: "doc.text")
                }

                if let photoID = detail.photoId {
                    NavigationLink {
                        PhotoDetailView(photoID: photoID)
                    } label: {
                        Label(detail.photoTitle ?? L10n.string("作品详情"), systemImage: "photo.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }

                if let originalURL = detail.originalURL {
                    Button {
                        openURL(originalURL)
                    } label: {
                        Label(L10n.string("查看原文"), systemImage: "safari")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }

                if let loadError, detail.renderedContent == nil {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
        .navigationTitle(L10n.string("资讯详情"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) { await loadDetail() }
        .appScreenBackground()
    }

    @MainActor
    private func loadDetail() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let response: NewsDetailResponse = try await APIClient.shared.get("api/news/\(item.id)")
            detail = response.item
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct NewsListRow: View {
    let item: NewsItem

    var body: some View {
        HStack(spacing: 14) {
            NewsCover(item: item, contentMode: .fit)
                .frame(width: 108, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 5) {
                    if let source = item.source, !source.isEmpty { Text(source).lineLimit(1) }
                    if item.source?.isEmpty == false, item.displayDate != nil { Text("·") }
                    if let date = item.displayDate { Text(date) }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppTheme.divider, lineWidth: 0.6))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct NewsCover: View {
    let item: NewsItem
    let contentMode: ContentMode

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.accent.opacity(0.22), Color.cyan.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if MediaURL.resolve(item.cover) != nil {
                RemoteImage(urlString: item.cover, contentMode: contentMode)
                    .padding(contentMode == .fit ? 4 : 0)
            } else {
                Image(systemName: "newspaper.fill")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .clipped()
        .accessibilityLabel(item.title)
    }
}
