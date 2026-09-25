import SwiftUI
import UIKit

struct ImageInspectorView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case normal, centering, horizon, histogram, equalize
        var id: String { rawValue }
        var title: String {
            switch self {
            case .normal: L10n.string("原图")
            case .centering: L10n.string("居中线")
            case .horizon: L10n.string("地平线")
            case .histogram: L10n.string("直方图")
            case .equalize: L10n.string("均衡预览")
            }
        }
        var icon: String {
            switch self {
            case .normal: "photo"
            case .centering: "scope"
            case .horizon: "grid"
            case .histogram: "chart.bar.fill"
            case .equalize: "circle.lefthalf.filled"
            }
        }
    }

    let image: UIImage
    let byteCount: Int
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .normal
    @State private var zoom: CGFloat = 1
    @GestureState private var liveZoom: CGFloat = 1

    private var analysis: InspectorAnalysis { InspectorAnalysis(image: image) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Mode.allCases) { item in
                            Button { mode = item } label: {
                                Label(item.title, systemImage: item.icon)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .foregroundStyle(mode == item ? Color.white : Color.primary)
                                    .background(mode == item ? AppTheme.accent : AppTheme.elevated, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                GeometryReader { proxy in
                    ZStack {
                        Color.black
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .contrast(mode == .equalize ? analysis.previewContrast : 1)
                            .brightness(mode == .equalize ? analysis.previewBrightness : 0)
                            .scaleEffect(zoom * liveZoom)
                            .gesture(
                                MagnifyGesture()
                                    .updating($liveZoom) { value, state, _ in state = value.magnification }
                                    .onEnded { value in zoom = min(max(zoom * value.magnification, 1), 8) }
                            )
                            .onTapGesture(count: 2) { withAnimation { zoom = zoom > 1 ? 1 : 2 } }
                        if mode == .centering || mode == .horizon {
                            InspectorGrid(mode: mode == .centering ? .centering : .horizon)
                                .allowsHitTesting(false)
                        }
                        if mode == .histogram {
                            InspectorHistogram(bins: analysis.bins)
                                .frame(height: min(180, proxy.size.height * 0.35))
                                .padding(14)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                HStack(spacing: 18) {
                    Label("\(Int(image.size.width)) × \(Int(image.size.height))", systemImage: "aspectratio")
                    Label(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file), systemImage: "doc")
                    Spacer()
                    Text("B \(analysis.blackPoint)% · W \(analysis.whitePoint)%")
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
            .navigationTitle(L10n.string("图片检查工具"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("完成")) { dismiss() }
                }
            }
            .appScreenBackground()
        }
    }
}

private struct InspectorGrid: View {
    enum Kind { case centering, horizon }
    let mode: Kind

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let xs: [CGFloat] = mode == .centering ? [0.5] : [0.25, 0.5, 0.75]
            let ys: [CGFloat] = mode == .centering ? [0.5] : [0.2, 0.4, 0.5, 0.6, 0.8]
            for x in xs { path.move(to: CGPoint(x: size.width * x, y: 0)); path.addLine(to: CGPoint(x: size.width * x, y: size.height)) }
            for y in ys { path.move(to: CGPoint(x: 0, y: size.height * y)); path.addLine(to: CGPoint(x: size.width, y: size.height * y)) }
            context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1)
            context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 3)
        }
    }
}

private struct InspectorHistogram: View {
    let bins: [Int]
    var body: some View {
        Canvas { context, size in
            let peak = max(bins.max() ?? 1, 1)
            var path = Path()
            for (index, count) in bins.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(max(bins.count - 1, 1))
                let y = size.height * (1 - CGFloat(count) / CGFloat(peak))
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .linearGradient(
                Gradient(colors: [.black, .gray, .white]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: 0)
            ))
            context.stroke(path, with: .color(AppTheme.accent), lineWidth: 1.5)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct InspectorAnalysis {
    let bins: [Int]
    let blackPoint: Int
    let whitePoint: Int
    let previewContrast: Double
    let previewBrightness: Double

    init(image: UIImage) {
        guard let source = image.cgImage else {
            bins = Array(repeating: 0, count: 256); blackPoint = 0; whitePoint = 100
            previewContrast = 1; previewBrightness = 0; return
        }
        let width = min(source.width, 512)
        let height = max(1, Int(Double(source.height) * Double(width) / Double(max(source.width, 1))))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            bins = Array(repeating: 0, count: 256); blackPoint = 0; whitePoint = 100
            previewContrast = 1; previewBrightness = 0; return
        }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        var values = [Int](repeating: 0, count: 256)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let lum = Int(0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2]))
            values[min(max(lum, 0), 255)] += 1
        }
        bins = values
        let total = max(width * height, 1)
        func percentile(_ target: Double) -> Int {
            var count = 0
            for (index, value) in values.enumerated() {
                count += value
                if Double(count) / Double(total) >= target { return index }
            }
            return 255
        }
        let low = percentile(0.01), high = max(percentile(0.99), low + 1)
        blackPoint = Int((Double(low) / 255 * 100).rounded())
        whitePoint = Int((Double(high) / 255 * 100).rounded())
        previewContrast = min(3, 255 / Double(high - low))
        previewBrightness = -Double(low) / 255
    }
}
