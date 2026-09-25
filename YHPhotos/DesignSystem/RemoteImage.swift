import SwiftUI

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case let .success(image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                placeholder
                    .overlay { Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary) }
            case .empty:
                placeholder.overlay { ProgressView().tint(.secondary) }
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.09), Color.white.opacity(0.025)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AvatarView: View {
    let urlString: String?
    let name: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(AppTheme.accent.opacity(0.18))
            if let value = urlString, let url = URL(string: value) {
                RemoteImage(url: url).clipShape(Circle())
            } else {
                Text(String(name.first ?? "Y"))
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.75))
        .accessibilityLabel(name)
    }
}
