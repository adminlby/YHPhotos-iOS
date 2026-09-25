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
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: photo.imageURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
