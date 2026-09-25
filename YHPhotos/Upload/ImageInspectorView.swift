import SwiftUI
import UIKit

/// Port of `frontend/src/components/upload/ImageInspector.tsx`.
struct ImageInspectorView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case normal, centering, horizon, histogram, equalize
        var id: String { rawValue }
        var title: String {
            switch self {
            case .normal: L10n.string("原图")
            case .centering: L10n.string("居中检查")
            case .horizon: L10n.string("水平检查")
            case .histogram: L10n.string("曝光直方图")
            case .equalize: L10n.string("灰尘增强")
            }
        }
        var help: String {
            switch self {
            case .normal: L10n.string("原始画面，不叠加分析结果。")
            case .centering: L10n.string("黄色线为固定 23/50/77% 与 28/50/72% 参考线；选择水平或垂直后拖动生成镜像辅助线。")
            case .horizon: L10n.string("黄色宫格按图片比例等分，红色十字线贯穿图片中心，可独立开关或叠加；移动手指可使用 3× 圆形放大镜检查水平线。")
            case .histogram: L10n.string("直方图使用未压缩分析原图的加权亮度，不与灰尘增强同时开启。")
            case .equalize: L10n.string("对 RGB 三通道分别执行全局直方图均衡化，用于放大灰尘、色带和背景不均；它不是自动灰尘识别。")
            }
        }
        var needsAnalysis: Bool { self == .histogram || self == .equalize }
    }

    private struct GridPreset: Identifiable {
        let rows: Int
        let columns: Int
        var id: String { "\(rows)x\(columns)" }
        var cells: Int { rows * columns }
    }

    private static let guideColor = Color(red: 1, green: 1, blue: 0)
    private static let manualGuideColor = Color(red: 1, green: 0, blue: 0)
    private static let guideWidth: CGFloat = 2
    private static let maxGridDivisions = 64
    private static let lensSize: CGFloat = 200
    private static let lensZoom: CGFloat = 3
    private static let gridPresets: [GridPreset] = [
        .init(rows: 3, columns: 3),
        .init(rows: 4, columns: 4),
        .init(rows: 4, columns: 8),
        .init(rows: 8, columns: 8),
    ]

    let image: UIImage
    let byteCount: Int

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .normal
    @State private var compress = false
    @State private var fullSize = false
    @State private var analysis: AnalysisResult?
    @State private var analysisPending = true
    @State private var analysisError = false
    @State private var displayImage: UIImage?
    @State private var equalizedImage: UIImage?
    @State private var cleanPixels: PixelBuffer?
    @State private var renderSize = ImageInspectorMath.Size(width: 0, height: 0)
    @State private var manualX: CGFloat?
    @State private var manualY: CGFloat?
    @State private var guideKind: ManualGuide = .horizontal
    @State private var gridRows = 3
    @State private var gridColumns = 3
    @State private var showGrid = true
    @State private var showCross = true
    @State private var loupeVisible = false
    @State private var loupeImage: UIImage?
    @State private var loupeOrigin: CGPoint = .zero
    @State private var contentSize: CGSize = .zero

    private enum ManualGuide: String, CaseIterable, Hashable { case horizontal, vertical }

    private struct AnalysisResult {
        let histograms: ImageInspectorMath.ChannelHistograms
        let luts: ImageInspectorMath.EqualizationLuts
    }

    private struct PixelBuffer {
        let width: Int
        let height: Int
        let rgba: [UInt8]
    }

    private var pixelWidth: Int { max(1, Int(image.size.width * image.scale)) }
    private var pixelHeight: Int { max(1, Int(image.size.height * image.scale)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    modePicker
                    optionsBar
                    if mode == .centering { centeringGuidePicker }
                    if mode == .horizon { horizonControls }
                    imageStage
                    if mode == .histogram, let analysis {
                        HistogramPanel(histograms: analysis.histograms)
                    }
                    helpFooter
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle(L10n.string("图片检查工具"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("完成")) { dismiss() }
                }
            }
            .appScreenBackground()
            .task { await prepare() }
            .onChange(of: compress) { _ in rebuildDisplay() }
            .onChange(of: mode) { _ in
                if mode != .horizon { loupeVisible = false }
                rebuildEqualizedIfNeeded()
            }
            .onChange(of: analysis?.histograms.pixelCount) { _ in rebuildEqualizedIfNeeded() }
        }
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Mode.allCases) { item in
                    let disabled = item.needsAnalysis && analysis == nil
                    Button {
                        mode = item
                    } label: {
                        Text(item.title)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(mode == item ? AppTheme.accent : .secondary)
                            .background(
                                Capsule()
                                    .fill(mode == item ? AppTheme.accent.opacity(0.15) : Color.clear)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(mode == item ? AppTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .opacity(disabled ? 0.45 : 1)
                }
            }
        }
    }

    private var optionsBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L10n.string("长边压缩至 1024px"), isOn: Binding(
                get: { compress },
                set: { enabled in
                    compress = enabled
                    if enabled { fullSize = false }
                }
            ))
            .font(.caption)
            Toggle(L10n.string("按实际像素显示"), isOn: Binding(
                get: { fullSize },
                set: { enabled in
                    fullSize = enabled
                    if enabled { compress = false }
                }
            ))
            .font(.caption)

            HStack(spacing: 6) {
                Text(L10n.format("原图 %d × %d", pixelWidth, pixelHeight))
                if renderSize.width > 0 {
                    Text(L10n.format(" · 当前 %d × %d", renderSize.width, renderSize.height))
                }
                Spacer(minLength: 0)
                Text(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            if analysisPending {
                Text(L10n.string("正在统计全分辨率像素…"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if analysisError {
                Text(L10n.string("原图分析失败"))
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var centeringGuidePicker: some View {
        Picker(L10n.string("辅助线"), selection: $guideKind) {
            Text(L10n.string("水平镜像线")).tag(ManualGuide.horizontal)
            Text(L10n.string("垂直镜像线")).tag(ManualGuide.vertical)
        }
        .pickerStyle(.segmented)
        .padding(12)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var horizonControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.string("显示宫格"), isOn: $showGrid).font(.caption)
            Toggle(L10n.string("中心十字分割线"), isOn: $showCross).font(.caption)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.gridPresets) { preset in
                        let selected = showGrid && gridRows == preset.rows && gridColumns == preset.columns
                        Button {
                            gridRows = preset.rows
                            gridColumns = preset.columns
                            showGrid = true
                        } label: {
                            Text(L10n.format("%d 宫格（%d×%d）", preset.cells, preset.rows, preset.columns))
                                .font(.caption2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(selected ? AppTheme.accent : .secondary)
                                .background(Capsule().fill(selected ? AppTheme.accent.opacity(0.15) : Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                Text(L10n.string("自定义")).font(.caption).foregroundStyle(.secondary)
                stepper(L10n.string("行数"), value: $gridRows)
                stepper(L10n.string("列数"), value: $gridColumns)
            }
            Text(L10n.format("%d 行 × %d 列 · 共 %d 格（行列各 1–%d）", gridRows, gridColumns, gridRows * gridColumns, Self.maxGridDivisions))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepper(_ title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Stepper(
                value: Binding(
                    get: { value.wrappedValue },
                    set: {
                        value.wrappedValue = min(max($0, 1), Self.maxGridDivisions)
                        showGrid = true
                    }
                ),
                in: 1...Self.maxGridDivisions
            ) {
                Text("\(value.wrappedValue)")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 24)
            }
        }
    }

    private var imageStage: some View {
        Group {
            if analysisError && mode.needsAnalysis {
                EmptyStateView(
                    L10n.string("原图分析失败"),
                    systemImage: "exclamationmark.octagon.fill",
                    description: L10n.string("需要可读取的未压缩原图；工具不会退回水印图生成统计结果。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        Color(red: 0.008, green: 0.024, blue: 0.090)
                        if let shown = shownImage {
                            Image(uiImage: shown)
                                .resizable()
                                .interpolation(.high)
                                .frame(
                                    width: stageWidth,
                                    height: stageHeight
                                )
                        } else {
                            ProgressView()
                                .frame(width: stageWidth, height: max(stageHeight, 180))
                        }

                        if mode == .centering || mode == .horizon {
                            guideOverlay
                                .frame(width: stageWidth, height: stageHeight)
                                .allowsHitTesting(true)
                        }

                        if mode == .horizon, loupeVisible, let loupeImage {
                            Image(uiImage: loupeImage)
                                .resizable()
                                .frame(width: Self.lensSize, height: Self.lensSize)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Self.guideColor, lineWidth: 2))
                                .shadow(radius: 12)
                                .position(loupeOrigin)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: stageWidth, height: stageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentSizeKey.self, value: proxy.size)
                        }
                    )
                }
                .frame(maxHeight: fullSize ? 620 : 420)
                .onPreferenceChange(ContentSizeKey.self) { contentSize = $0 }
            }
        }
    }

    private var shownImage: UIImage? {
        mode == .equalize ? (equalizedImage ?? displayImage) : displayImage
    }

    private var stageWidth: CGFloat {
        guard renderSize.width > 0 else { return 1 }
        if fullSize { return CGFloat(renderSize.width) }
        let maxW = max(contentSize.width, UIScreen.main.bounds.width - 32)
        let scale = min(1, maxW / CGFloat(renderSize.width))
        return CGFloat(renderSize.width) * scale
    }

    private var stageHeight: CGFloat {
        guard renderSize.width > 0, renderSize.height > 0 else { return 1 }
        return stageWidth * CGFloat(renderSize.height) / CGFloat(renderSize.width)
    }

    private var guideOverlay: some View {
        Canvas { context, size in
            if mode == .centering {
                drawCenteringGuides(context: &context, size: size)
            } else if mode == .horizon {
                drawHorizonGrid(context: &context, size: size)
            }
        }
        .contentShape(Rectangle())
        .gesture(centeringAndHorizonGesture)
    }

    private var centeringAndHorizonGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = imagePoint(from: value.location)
                if mode == .centering {
                    updateManualGuide(point, guide: guideKind)
                } else if mode == .horizon {
                    updateLoupe(at: value.location, imagePoint: point)
                }
            }
            .onEnded { _ in
                if mode == .horizon { loupeVisible = false }
            }
    }

    private var helpFooter: some View {
        HStack(alignment: .top, spacing: 6) {
            if mode == .horizon {
                Image(systemName: "plus.magnifyingglass")
                    .font(.caption)
                    .padding(.top, 1)
            }
            Text(mode.help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Drawing (same geometry as website)

    private func drawCenteringGuides(context: inout GraphicsContext, size: CGSize) {
        let x23 = (size.width * 0.23).rounded()
        let x50 = (size.width * 0.5).rounded()
        let x77 = (size.width * 0.77).rounded()
        let y28 = (size.height * 0.28).rounded()
        let y50 = (size.height * 0.5).rounded()
        let y72 = (size.height * 0.72).rounded()

        var path = Path()
        path.move(to: CGPoint(x: x23, y: 0)); path.addLine(to: CGPoint(x: x23, y: size.height))
        path.move(to: CGPoint(x: x77, y: 0)); path.addLine(to: CGPoint(x: x77, y: size.height))
        path.move(to: CGPoint(x: x50, y: y28)); path.addLine(to: CGPoint(x: x50, y: y72))
        path.move(to: CGPoint(x: 0, y: y28)); path.addLine(to: CGPoint(x: size.width, y: y28))
        path.move(to: CGPoint(x: 0, y: y72)); path.addLine(to: CGPoint(x: size.width, y: y72))
        path.move(to: CGPoint(x: x23, y: y50)); path.addLine(to: CGPoint(x: x77, y: y50))
        context.stroke(path, with: .color(Self.guideColor), lineWidth: Self.guideWidth)

        var manual = Path()
        if let manualY {
            let y = manualY * size.height / CGFloat(max(renderSize.height, 1))
            manual.move(to: CGPoint(x: 0, y: y)); manual.addLine(to: CGPoint(x: size.width, y: y))
            manual.move(to: CGPoint(x: 0, y: size.height - y)); manual.addLine(to: CGPoint(x: size.width, y: size.height - y))
        }
        if let manualX {
            let x = manualX * size.width / CGFloat(max(renderSize.width, 1))
            manual.move(to: CGPoint(x: x, y: 0)); manual.addLine(to: CGPoint(x: x, y: size.height))
            manual.move(to: CGPoint(x: size.width - x, y: 0)); manual.addLine(to: CGPoint(x: size.width - x, y: size.height))
        }
        context.stroke(manual, with: .color(Self.manualGuideColor), lineWidth: Self.guideWidth)
    }

    private func drawHorizonGrid(context: inout GraphicsContext, size: CGSize) {
        // 按实际显示宽度补偿线宽，避免大图缩放到窄屏后分割线被采样掉。
        let lineWidth = max(Self.guideWidth, 1.5 * CGFloat(renderSize.width) / max(size.width, 1))
        if showGrid {
            var path = Path()
            if gridColumns > 1 {
                for column in 1..<gridColumns {
                    let x = size.width * CGFloat(column) / CGFloat(gridColumns)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            if gridRows > 1 {
                for row in 1..<gridRows {
                    let y = size.height * CGFloat(row) / CGFloat(gridRows)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            context.stroke(path, with: .color(Self.guideColor), lineWidth: lineWidth)
        }
        if showCross {
            var cross = Path()
            cross.move(to: CGPoint(x: size.width / 2, y: 0))
            cross.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            cross.move(to: CGPoint(x: 0, y: size.height / 2))
            cross.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(cross, with: .color(Self.manualGuideColor), lineWidth: lineWidth)
        }
    }

    // MARK: - Interaction

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        let scaleX = CGFloat(renderSize.width) / max(stageWidth, 1)
        let scaleY = CGFloat(renderSize.height) / max(stageHeight, 1)
        return CGPoint(
            x: min(max(viewPoint.x * scaleX, 0), CGFloat(renderSize.width)),
            y: min(max(viewPoint.y * scaleY, 0), CGFloat(renderSize.height))
        )
    }

    private func updateManualGuide(_ point: CGPoint, guide: ManualGuide) {
        switch guide {
        case .horizontal: manualY = point.y
        case .vertical: manualX = point.x
        }
    }

    private func updateLoupe(at viewPoint: CGPoint, imagePoint: CGPoint) {
        guard let clean = cleanPixels else { return }
        let sample = Self.lensSize / Self.lensZoom
        let srcX = imagePoint.x - sample / 2
        let srcY = imagePoint.y - sample / 2
        loupeImage = cropMagnified(from: clean, x: srcX, y: srcY, sample: sample, output: Int(Self.lensSize))

        var left = viewPoint.x + 18
        var top = viewPoint.y + 18
        if left + Self.lensSize > stageWidth { left = viewPoint.x - Self.lensSize - 18 }
        if top + Self.lensSize > stageHeight { top = viewPoint.y - Self.lensSize - 18 }
        loupeOrigin = CGPoint(
            x: max(Self.lensSize / 2 + 2, min(left + Self.lensSize / 2, stageWidth - Self.lensSize / 2 - 2)),
            y: max(Self.lensSize / 2 + 2, min(top + Self.lensSize / 2, stageHeight - Self.lensSize / 2 - 2))
        )
        loupeVisible = true
    }

    // MARK: - Image pipeline

    @MainActor
    private func prepare() async {
        rebuildDisplay()
        analysisPending = true
        analysisError = false
        analysis = nil

        let source = image
        let result: AnalysisResult? = await Task.detached(priority: .userInitiated) {
            guard let rgba = Self.rgbaBytes(from: source, width: nil, height: nil) else { return nil }
            let histograms = ImageInspectorMath.collectHistograms(rgba: rgba)
            let luts = ImageInspectorMath.buildEqualizationLuts(histograms: histograms)
            return AnalysisResult(histograms: histograms, luts: luts)
        }.value

        if let result {
            analysis = result
            analysisError = false
            rebuildEqualizedIfNeeded()
        } else {
            analysisError = true
        }
        analysisPending = false
    }

    private func rebuildDisplay() {
        let size = ImageInspectorMath.getPreviewDimensions(width: pixelWidth, height: pixelHeight, compress: compress)
        renderSize = size
        guard let rgba = Self.rgbaBytes(from: image, width: size.width, height: size.height),
              let uiImage = Self.image(fromRGBA: rgba, width: size.width, height: size.height) else {
            displayImage = nil
            cleanPixels = nil
            equalizedImage = nil
            return
        }
        displayImage = uiImage
        cleanPixels = PixelBuffer(width: size.width, height: size.height, rgba: rgba)
        rebuildEqualizedIfNeeded()
    }

    private func rebuildEqualizedIfNeeded() {
        guard mode == .equalize, let analysis, var rgba = cleanPixels?.rgba,
              let width = cleanPixels?.width, let height = cleanPixels?.height else {
            equalizedImage = nil
            return
        }
        ImageInspectorMath.applyEqualization(rgba: &rgba, luts: analysis.luts)
        equalizedImage = Self.image(fromRGBA: rgba, width: width, height: height)
    }

    private func cropMagnified(from buffer: PixelBuffer, x: CGFloat, y: CGFloat, sample: CGFloat, output: Int) -> UIImage? {
        var out = [UInt8](repeating: 0, count: output * output * 4)
        let scale = sample / CGFloat(output)
        for py in 0..<output {
            for px in 0..<output {
                let sx = Int((x + CGFloat(px) * scale).rounded())
                let sy = Int((y + CGFloat(py) * scale).rounded())
                let dst = (py * output + px) * 4
                if sx < 0 || sy < 0 || sx >= buffer.width || sy >= buffer.height {
                    out[dst] = 2; out[dst + 1] = 6; out[dst + 2] = 23; out[dst + 3] = 255
                    continue
                }
                let src = (sy * buffer.width + sx) * 4
                out[dst] = buffer.rgba[src]
                out[dst + 1] = buffer.rgba[src + 1]
                out[dst + 2] = buffer.rgba[src + 2]
                out[dst + 3] = buffer.rgba[src + 3]
            }
        }
        return Self.image(fromRGBA: out, width: output, height: output)
    }

    /// Draw `UIImage` into RGBA8888 (non-premultiplied for analysis parity with canvas getImageData).
    private static func rgbaBytes(from image: UIImage, width: Int?, height: Int?) -> [UInt8]? {
        let targetW = width ?? max(1, Int(image.size.width * image.scale))
        let targetH = height ?? max(1, Int(image.size.height * image.scale))
        var pixels = [UInt8](repeating: 0, count: targetW * targetH * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: targetW * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.interpolationQuality = .high
        UIGraphicsPushContext(context)
        // Flip to UIKit coordinates so UIImage.draw matches HTML canvas top-left origin.
        context.translateBy(x: 0, y: CGFloat(targetH))
        context.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        UIGraphicsPopContext()

        // Un-premultiply to match canvas ImageData (non-premultiplied RGBA).
        var index = 0
        while index + 3 < pixels.count {
            let a = pixels[index + 3]
            if a > 0 && a < 255 {
                let af = CGFloat(a) / 255
                pixels[index] = UInt8(min(255, CGFloat(pixels[index]) / af))
                pixels[index + 1] = UInt8(min(255, CGFloat(pixels[index + 1]) / af))
                pixels[index + 2] = UInt8(min(255, CGFloat(pixels[index + 2]) / af))
            }
            index += 4
        }
        return pixels
    }

    private static func image(fromRGBA rgba: [UInt8], width: Int, height: Int) -> UIImage? {
        var pixels = rgba
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        // Premultiply for CGImage display.
        var index = 0
        while index + 3 < pixels.count {
            let a = pixels[index + 3]
            if a < 255 {
                let af = CGFloat(a) / 255
                pixels[index] = UInt8(CGFloat(pixels[index]) * af)
                pixels[index + 1] = UInt8(CGFloat(pixels[index + 1]) * af)
                pixels[index + 2] = UInt8(CGFloat(pixels[index + 2]) * af)
            }
            index += 4
        }
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct ContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - Histogram panel (website HistogramPanel)

private struct HistogramPanel: View {
    let histograms: ImageInspectorMath.ChannelHistograms

    private var metrics: ImageInspectorMath.ExposureMetrics {
        ImageInspectorMath.calculateExposureMetrics(
            luminance: histograms.luminance,
            pixelCount: histograms.pixelCount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .color(Color(red: 0.008, green: 0.024, blue: 0.090)))

                let ceiling = (ImageInspectorMath.histogramCeilingFactor * Double(histograms.pixelCount))
                    / Double(ImageInspectorMath.histogramBins)
                let safeCeiling = max(ceiling, 1)
                let barWidth = size.width / CGFloat(ImageInspectorMath.histogramBins)

                for value in 0..<ImageInspectorMath.histogramBins {
                    let normalized = min(Double(histograms.luminance[value]) / safeCeiling, 1)
                    let barHeight = CGFloat(normalized) * size.height
                    let bar = CGRect(
                        x: CGFloat(value) * barWidth,
                        y: size.height - barHeight,
                        width: max(1, barWidth + 0.4),
                        height: barHeight
                    )
                    context.fill(Path(bar), with: .color(Color.white.opacity(0.88)))
                }

                let averageLineY = size.height * (1 - 1 / ImageInspectorMath.histogramCeilingFactor)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: averageLineY))
                line.addLine(to: CGPoint(x: size.width, y: averageLineY))
                context.stroke(line, with: .color(Color(red: 0.957, green: 0.447, blue: 0.714)), lineWidth: 1)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text(L10n.string("0 · 黑")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.string("粉线：每个亮度级的平均像素数"))
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.957, green: 0.447, blue: 0.714))
                Spacer()
                Text(L10n.string("白 · 255")).font(.caption2).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metricCell(L10n.string("黑点 0.5%"), "\(metrics.blackPoint)")
                metricCell(L10n.string("白点 99.5%"), "\(metrics.whitePoint)")
                metricCell(L10n.string("色调跨度"), "\(metrics.range)")
                metricCell(L10n.string("黑端危险区 0–2"), String(format: "%.1f%%", metrics.blackClipPercent))
                metricCell(L10n.string("白端危险区 253–255"), String(format: "%.1f%%", metrics.whiteClipPercent))
            }

            Text(L10n.string("纵轴上限固定为平均 bin 像素数的 4.55 倍，超过上限的峰值会被顶平；色调跨度是 8-bit 百分位跨度，不是 EV 动态范围。"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(red: 0.008, green: 0.024, blue: 0.090).opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func metricCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}
