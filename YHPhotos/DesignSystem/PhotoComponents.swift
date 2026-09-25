import SwiftUI

struct PhotoGridCard: View {
    let photo: Photo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: photo.thumbnailURL)
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipped()
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
    var height: CGFloat = 390

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: photo.imageURL)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
            LinearGradient(
                colors: [.clear, AppTheme.canvas.opacity(0.2), AppTheme.canvas.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("编辑精选")
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
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct LoadingOrErrorView: View {
    let isLoading: Bool
    let error: String?
    let retry: () -> Void

    var body: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 180)
        } else if let error {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("重试", action: retry).buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 260)
        }
    }
}
