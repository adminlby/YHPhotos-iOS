import ImageIO
import PhotosUI
import SwiftUI
import UIKit

/// Standalone entry for the image inspector: pick a photo, then open the same tool used on the upload page.
struct ImageInspectorLauncherView: View {
    @State private var selection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showingInspector = false
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                GlassPanel(cornerRadius: 22) {
                    Group {
                        if let imageData, let image = UIImage(data: imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    PhotosPicker(selection: $selection, matching: .images) {
                                        Label(L10n.string("更换"), systemImage: "arrow.triangle.2.circlepath")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 11).padding(.vertical, 7)
                                            .background(.ultraThinMaterial, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(10)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    Button { showingInspector = true } label: {
                                        Label(L10n.string("图片检查工具"), systemImage: "viewfinder")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 11).padding(.vertical, 7)
                                            .background(.ultraThinMaterial, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(10)
                                }
                                .padding(14)
                        } else {
                            PhotosPicker(selection: $selection, matching: .images) {
                                VStack(spacing: 12) {
                                    Image(systemName: "viewfinder")
                                        .font(.system(size: 36, weight: .semibold))
                                        .foregroundStyle(AppTheme.accent)
                                    Text(L10n.string("选择图片开始检查")).font(.headline)
                                    Text(L10n.string("最大 50 MB；HEIC 会在设备上转换为兼容的 JPEG。"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 48)
                                .padding(.horizontal, 18)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                GlassPanel(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.string("能检查什么"), systemImage: "sparkles")
                            .font(.headline)
                        Text(L10n.string("居中参考线、水平宫格、曝光直方图与灰尘增强，与上传页内的检查工具相同。"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if imageData != nil {
                            Button {
                                showingInspector = true
                            } label: {
                                Text(L10n.string("打开检查工具"))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .foregroundStyle(Color.white)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    .padding(18)
                }

                if let loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
        .navigationTitle(L10n.string("图片检查工具"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: selection) { await loadSelectedImage() }
        .sheet(isPresented: $showingInspector) {
            if let imageData, let image = UIImage(data: imageData) {
                ImageInspectorView(image: image, byteCount: imageData.count)
            }
        }
        .appScreenBackground()
    }

    private func loadSelectedImage() async {
        guard let selection else { return }
        loadError = nil
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                loadError = L10n.string("无法读取所选图片")
                return
            }
            guard data.count <= 50 * 1024 * 1024 else {
                imageData = nil
                loadError = L10n.string("图片超过 50 MB 上限。")
                return
            }
            if isSupportedImage(data) {
                imageData = data
            } else if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.94) {
                imageData = jpeg
            } else {
                imageData = nil
                loadError = L10n.string("无法读取所选图片，请换一张重试。")
                return
            }
            showingInspector = true
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func isSupportedImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String? else { return false }
        return ["public.jpeg", "public.png", "com.compuserve.gif", "public.heic", "public.heif"].contains(type)
    }
}
