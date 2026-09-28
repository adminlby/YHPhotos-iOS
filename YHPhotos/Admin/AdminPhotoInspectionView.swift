import SwiftUI
import UIKit

/// Loads the inspector payload from a caller-selected, permission-checked
/// admin endpoint before entering the shared native image workspace.
struct AdminPhotoInspectionLoaderView: View {
    @Environment(\.dismiss) private var dismiss

    let endpoint: String

    @State private var detail: AdminReviewDetail?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let detail {
                AdminPhotoInspectionView(detail: detail)
            } else if let errorMessage {
                NavigationStack {
                    EmptyStateView(
                        "检查工具加载失败",
                        systemImage: "exclamationmark.triangle.fill",
                        description: errorMessage
                    ) {
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { dismiss() }
                        }
                    }
                }
            } else {
                NavigationStack {
                    ProgressView("正在载入检查工具…")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { dismiss() }
                            }
                        }
                }
            }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        errorMessage = nil
        do {
            detail = try await APIClient.shared.get(endpoint)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Native authenticated image workspace shared by review and appeal flows.
/// The original file is loaded through APIClient so Bearer/App-Attest headers
/// are applied; it is never downgraded silently to a public thumbnail.
struct AdminPhotoInspectionView: View {
    @Environment(\.dismiss) private var dismiss

    let detail: AdminReviewDetail

    @State private var image: UIImage?
    @State private var byteCount = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingFullscreen = false
    @State private var showingAnalysis = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    VStack(spacing: 0) {
                        ZoomableImageView(image: image)
                            .background(Color.black)
                            .overlay(alignment: .topLeading) {
                                sourceBadge.padding(12)
                            }
                        controls
                    }
                } else if isLoading {
                    ProgressView("正在安全加载原图…")
                } else {
                    EmptyStateView(
                        "图片加载失败",
                        systemImage: "exclamationmark.triangle.fill",
                        description: errorMessage ?? "无法读取图片"
                    ) {
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("检查工具 · #\(detail.id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let image {
                AdminFullscreenImageView(image: image, title: detail.title)
            }
        }
        .fullScreenCover(isPresented: $showingAnalysis) {
            if let image {
                ImageInspectorView(image: image, byteCount: byteCount)
            }
        }
    }

    private var sourceBadge: some View {
        Label(
            detail.canViewOriginal && detail.originalUrl != nil ? "无水印原图 · 仅审核可见" : "水印展示图",
            systemImage: detail.canViewOriginal && detail.originalUrl != nil ? "lock.shield.fill" : "photo"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.62), in: Capsule())
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { showingFullscreen = true } label: {
                    Label("单独查看", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { showingAnalysis = true } label: {
                    Label("画质分析", systemImage: "waveform.path.ecg.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Text("双指缩放、拖动查看；双击可在适应屏幕与 3× 之间切换。画质分析包含居中、水平、放大镜、曝光直方图和灰尘增强。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.bar)
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let data: Data
            if detail.canViewOriginal, let path = detail.originalUrl {
                data = try await APIClient.shared.data(path)
            } else if let url = MediaURL.resolve(detail.image) {
                let result = try await URLSession.shared.data(from: url)
                guard let response = result.1 as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else {
                    throw APIClientError.invalidResponse
                }
                data = result.0
            } else {
                throw APIClientError.invalidResponse
            }
            guard let decoded = UIImage(data: data) else { throw APIClientError.invalidResponse }
            image = decoded
            byteCount = data.count
        } catch {
            image = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct AdminFullscreenImageView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let title: String

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            ZoomableImageView(image: image)
                .ignoresSafeArea(edges: .bottom)
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .foregroundStyle(.white)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text("双击 3×")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .statusBarHidden()
    }
}

/// UIKit's scroll view provides predictable high-resolution pinch zooming,
/// inertial panning and double-tap zoom without rasterizing the SwiftUI image.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let view = ZoomingImageScrollView()
        view.setImage(image)
        return view
    }

    func updateUIView(_ view: ZoomingImageScrollView, context: Context) {
        if view.imageView.image !== image { view.setImage(image) }
    }
}

final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    private var needsInitialFit = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .black
        showsHorizontalScrollIndicator = true
        showsVerticalScrollIndicator = true
        bouncesZoom = true
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage) {
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        needsInitialFit = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(bounds.width / max(image.size.width, 1), bounds.height / max(image.size.height, 1))
        minimumZoomScale = min(fit, 1)
        maximumZoomScale = max(minimumZoomScale * 12, 8)
        if needsInitialFit {
            zoomScale = minimumZoomScale
            needsInitialFit = false
        }
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.2 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let targetScale = min(maximumZoomScale, minimumZoomScale * 3)
        let point = recognizer.location(in: imageView)
        let width = bounds.width / targetScale
        let height = bounds.height / targetScale
        zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), animated: true)
    }

    private func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        imageView.center = CGPoint(
            x: contentSize.width / 2 + horizontal,
            y: contentSize.height / 2 + vertical
        )
    }
}
