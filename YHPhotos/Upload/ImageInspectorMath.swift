import Foundation

/// Port of `frontend/src/components/upload/imageInspectorMath.ts`.
enum ImageInspectorMath {
    static let histogramBins = 256
    static let histogramCeilingFactor = 4.55
    static let percentileThreshold = 0.005
    static let previewMaxEdge = 1024

    struct ChannelHistograms: Sendable {
        var luminance: [UInt32]
        var red: [UInt32]
        var green: [UInt32]
        var blue: [UInt32]
        var pixelCount: Int
    }

    struct EqualizationLuts: Sendable {
        var red: [UInt8]
        var green: [UInt8]
        var blue: [UInt8]
    }

    struct ExposureMetrics: Sendable {
        var blackPoint: Int
        var whitePoint: Int
        var range: Int
        var blackClipPercent: Double
        var whiteClipPercent: Double
    }

    struct Size: Sendable, Equatable {
        var width: Int
        var height: Int
    }

    /// 统计 8-bit RGB 三通道和加权亮度直方图。
    /// 亮度采用 JetPhotos Helper v1.2 的 round(0.299R + 0.587G + 0.114B)。
    static func collectHistograms(rgba: [UInt8]) -> ChannelHistograms {
        var luminance = [UInt32](repeating: 0, count: histogramBins)
        var red = [UInt32](repeating: 0, count: histogramBins)
        var green = [UInt32](repeating: 0, count: histogramBins)
        var blue = [UInt32](repeating: 0, count: histogramBins)

        var index = 0
        while index + 3 < rgba.count {
            let r = Int(rgba[index])
            let g = Int(rgba[index + 1])
            let b = Int(rgba[index + 2])
            red[r] += 1
            green[g] += 1
            blue[b] += 1
            let lum = Int((0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)).rounded())
            luminance[min(max(lum, 0), 255)] += 1
            index += 4
        }

        return ChannelHistograms(
            luminance: luminance,
            red: red,
            green: green,
            blue: blue,
            pixelCount: rgba.count / 4
        )
    }

    /// 按 CDF_min 公式生成单通道全局直方图均衡化查找表。
    static func buildEqualizationLut(histogram: [UInt32], pixelCount: Int) -> [UInt8] {
        var cumulative = [UInt32](repeating: 0, count: histogramBins)
        var runningTotal: UInt32 = 0
        var cdfMin: UInt32 = 0

        for value in 0..<histogramBins {
            runningTotal += histogram[value]
            cumulative[value] = runningTotal
            if cdfMin == 0 && runningTotal > 0 { cdfMin = runningTotal }
        }

        var lut = [UInt8](repeating: 0, count: histogramBins)
        let denominator = Double(pixelCount) - Double(cdfMin)

        for value in 0..<histogramBins {
            // denominator 为 0 时结果是 NaN；与网站 Uint8ClampedArray 写 NaN→0 一致。
            let mapped = ((Double(cumulative[value]) - Double(cdfMin)) / denominator) * 255
            if mapped.isFinite {
                lut[value] = UInt8(min(max(mapped.rounded(), 0), 255))
            } else {
                lut[value] = 0
            }
        }
        return lut
    }

    static func buildEqualizationLuts(histograms: ChannelHistograms) -> EqualizationLuts {
        EqualizationLuts(
            red: buildEqualizationLut(histogram: histograms.red, pixelCount: histograms.pixelCount),
            green: buildEqualizationLut(histogram: histograms.green, pixelCount: histograms.pixelCount),
            blue: buildEqualizationLut(histogram: histograms.blue, pixelCount: histograms.pixelCount)
        )
    }

    /// 原地应用 RGB 三通道 LUT，Alpha 保持不变。
    static func applyEqualization(rgba: inout [UInt8], luts: EqualizationLuts) {
        var index = 0
        while index + 3 < rgba.count {
            rgba[index] = luts.red[Int(rgba[index])]
            rgba[index + 1] = luts.green[Int(rgba[index + 1])]
            rgba[index + 2] = luts.blue[Int(rgba[index + 2])]
            index += 4
        }
    }

    static func calculateExposureMetrics(luminance: [UInt32], pixelCount: Int) -> ExposureMetrics {
        guard pixelCount > 0 else {
            return ExposureMetrics(blackPoint: 0, whitePoint: 0, range: 0, blackClipPercent: 0, whiteClipPercent: 0)
        }

        let threshold = percentileThreshold * Double(pixelCount)
        var blackPoint = 0
        var lowTotal: UInt32 = 0
        for value in 0..<histogramBins {
            lowTotal += luminance[value]
            if Double(lowTotal) >= threshold {
                blackPoint = value
                break
            }
        }

        var whitePoint = 255
        var highTotal: UInt32 = 0
        for value in stride(from: 255, through: 0, by: -1) {
            highTotal += luminance[value]
            if Double(highTotal) >= threshold {
                whitePoint = value
                break
            }
        }

        let blackClip = luminance[0] + luminance[1] + luminance[2]
        let whiteClip = luminance[253] + luminance[254] + luminance[255]

        return ExposureMetrics(
            blackPoint: blackPoint,
            whitePoint: whitePoint,
            range: whitePoint - blackPoint,
            blackClipPercent: (Double(blackClip) / Double(pixelCount)) * 100,
            whiteClipPercent: (Double(whiteClip) / Double(pixelCount)) * 100
        )
    }

    static func getPreviewDimensions(width: Int, height: Int, compress: Bool) -> Size {
        if !compress || (width <= previewMaxEdge && height <= previewMaxEdge) {
            return Size(width: width, height: height)
        }
        let scale = Double(previewMaxEdge) / Double(max(width, height))
        return Size(
            width: Int((Double(width) * scale).rounded()),
            height: Int((Double(height) * scale).rounded())
        )
    }
}
