import SwiftUI

struct PhotoGridCard: View {
    let photo: Photo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    RemoteImage(url: photo.thumbnailURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !photo.primaryMetadata.isEmpty {
                Text(photo.primaryMetadata)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            } else {
                Text(photo.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            if !photo.secondaryMetadata.isEmpty {
                Text(photo.secondaryMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                AvatarView(urlString: photo.author.avatar, name: photo.author.displayName, size: 24)
                Text(photo.author.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "heart")
                Text(photo.likes.compactCount)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

struct HeroPhotoView: View {
    let photo: Photo

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: photo.imageURL)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                LinearGradient(
                    colors: [.clear, AppTheme.canvas.opacity(0.2), AppTheme.canvas.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("编辑精选"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .appGlass(in: Capsule())
                    Text(photo.title).font(.title2.bold()).lineLimit(2)
                    Text([photo.primaryMetadata, photo.secondaryMetadata].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
            .clipped()
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct HeroCarouselView: View {
    let photos: [Photo]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = 0

    private var carouselID: String {
        photos.map { String($0.id) }.joined(separator: ",")
    }

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                TabView(selection: $selection) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        NavigationLink { PhotoDetailView(photoID: photo.id) } label: {
                            HeroPhotoView(photo: photo)
                        }
                        .buttonStyle(.plain)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            }
            .frame(maxWidth: .infinity)
            .clipped()
            .task(id: carouselID) {
                selection = min(selection, max(photos.count - 1, 0))
                guard photos.count > 1, !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.8)) {
                        selection = (selection + 1) % photos.count
                    }
                }
            }
    }
}

struct BadgeIconView: View {
    let icon: String?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let icon, icon.unicodeScalars.contains(where: { $0.value > 127 }) {
                Text(icon).font(.system(size: size))
            } else {
                Image(systemName: icon ?? "medal.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityHidden(true)
    }
}

struct LoadingOrErrorView: View {
    let isLoading: Bool
    let error: String?
    let loadingMessage: String?
    let retry: () -> Void

    init(
        isLoading: Bool,
        error: String?,
        loadingMessage: String? = nil,
        retry: @escaping () -> Void
    ) {
        self.isLoading = isLoading
        self.error = error
        self.loadingMessage = loadingMessage
        self.retry = retry
    }

    var body: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                if let loadingMessage {
                    Text(loadingMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if let error {
            EmptyStateView("加载失败", systemImage: "wifi.exclamationmark", description: error) {
                Button(action: retry) {
                    Text("重试")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.canvas)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 260)
        }
    }
}
