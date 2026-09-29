#!/usr/bin/env swift

import AppKit

struct StoreShot {
    let source: String
    let output: String
    let title: String
    let subtitle: String
}

struct StoreLocale {
    let code: String
    let brandLine: String
    let phoneRawDirectory: String
    let padRawDirectory: String
    let phoneOutputDirectory: String
    let padOutputDirectory: String
    let phoneTitleSize: CGFloat
    let phoneSubtitleSize: CGFloat
    let padTitleSize: CGFloat
    let padSubtitleSize: CGFloat
    let phoneShots: [StoreShot]
    let padShots: [StoreShot]
}

let simplifiedPhone = [
    StoreShot(source: "01-discover.png", output: "01-open-to-great-photos.jpg", title: "打开，就是好作品", subtitle: "航空、铁路与模拟飞行摄影社区"),
    StoreShot(source: "02-aviation.png", output: "02-explore-aviation.jpg", title: "按实体探索航空世界", subtitle: "机型、注册号、航司与机场一触即达"),
    StoreShot(source: "03-photo.png", output: "03-every-photo-tells-a-story.jpg", title: "每张照片都有完整故事", subtitle: "作品、拍摄信息与实体资料紧密相连"),
    StoreShot(source: "04-map.png", output: "04-discover-by-map.jpg", title: "从地图发现拍摄目的地", subtitle: "按机场浏览社区作品"),
    StoreShot(source: "05-tools.png", output: "05-tools-for-spotters.jpg", title: "从拍摄到投稿，一站齐全", subtitle: "检查、情报、百科与社区工具都在这里"),
    StoreShot(source: "06-inspector.png", output: "06-inspect-before-upload.jpg", title: "上传前，把画面检查清楚", subtitle: "居中、水平、直方图与灰尘增强")
]

let simplifiedPad = [
    StoreShot(source: "01-discover.png", output: "01-immersive-gallery.jpg", title: "为大屏而生的沉浸图库", subtitle: "侧栏导航、双列作品流与原生分栏体验"),
    StoreShot(source: "02-photo.png", output: "02-photo-and-details.jpg", title: "大图与资料，一屏尽览", subtitle: "作品互动、拍摄信息和实体入口"),
    StoreShot(source: "03-tools.png", output: "03-professional-tools.jpg", title: "专业工具，为拍摄服务", subtitle: "检查、情报、百科与社区入口清晰分区")
]

let traditionalPhone = [
    StoreShot(source: "01-discover.png", output: "01-open-to-great-photos.jpg", title: "打開，就是好作品", subtitle: "航空、鐵路與模擬飛行攝影社群"),
    StoreShot(source: "02-aviation.png", output: "02-explore-aviation.jpg", title: "按實體探索航空世界", subtitle: "機型、註冊號、航空公司與機場一觸即達"),
    StoreShot(source: "03-photo.png", output: "03-every-photo-tells-a-story.jpg", title: "每張照片都有完整故事", subtitle: "作品、拍攝資訊與實體資料緊密相連"),
    StoreShot(source: "04-map.png", output: "04-discover-by-map.jpg", title: "從地圖發現拍攝目的地", subtitle: "按機場瀏覽社群作品"),
    StoreShot(source: "05-tools.png", output: "05-tools-for-spotters.jpg", title: "從拍攝到投稿，一站齊全", subtitle: "檢查、情報、百科與社群工具都在這裡"),
    StoreShot(source: "06-inspector.png", output: "06-inspect-before-upload.jpg", title: "上傳前，把畫面檢查清楚", subtitle: "置中、水平、直方圖與灰塵增強")
]

let traditionalPad = [
    StoreShot(source: "01-discover.png", output: "01-immersive-gallery.jpg", title: "為大螢幕而生的沉浸圖庫", subtitle: "側邊欄導覽、雙欄作品流與原生分欄體驗"),
    StoreShot(source: "02-photo.png", output: "02-photo-and-details.jpg", title: "大圖與資料，一屏盡覽", subtitle: "作品互動、拍攝資訊與實體入口"),
    StoreShot(source: "03-tools.png", output: "03-professional-tools.jpg", title: "專業工具，為拍攝服務", subtitle: "檢查、情報、百科與社群入口清晰分區")
]

let englishPhone = [
    StoreShot(source: "01-discover.png", output: "01-open-to-great-photos.jpg", title: "Great photography starts here", subtitle: "A community for aviation, rail and flight simulation"),
    StoreShot(source: "02-aviation.png", output: "02-explore-aviation.jpg", title: "Explore aviation in context", subtitle: "Aircraft, registrations, airlines and airports—connected"),
    StoreShot(source: "03-photo.png", output: "03-every-photo-tells-a-story.jpg", title: "Every photo tells a story", subtitle: "Photography, capture details and reference data together"),
    StoreShot(source: "04-map.png", output: "04-discover-by-map.jpg", title: "Discover places on the map", subtitle: "Browse community photos airport by airport"),
    StoreShot(source: "05-tools.png", output: "05-tools-for-spotters.jpg", title: "Every tool a spotter needs", subtitle: "Inspection, intelligence, references and community"),
    StoreShot(source: "06-inspector.png", output: "06-inspect-before-upload.jpg", title: "Inspect before you upload", subtitle: "Check centering, level, histogram and dust")
]

let englishPad = [
    StoreShot(source: "01-discover.png", output: "01-immersive-gallery.jpg", title: "An immersive gallery built for iPad", subtitle: "Sidebar navigation, two-column feeds and native split views"),
    StoreShot(source: "02-photo.png", output: "02-photo-and-details.jpg", title: "Photography and details, side by side", subtitle: "Interactions, capture data and reference links in one view"),
    StoreShot(source: "03-tools.png", output: "03-professional-tools.jpg", title: "Professional tools for every shoot", subtitle: "Inspection, intelligence, references and community")
]

let locales = [
    StoreLocale(code: "zh-Hans", brandLine: "YHPhotos  ·  航摄图库", phoneRawDirectory: "Raw", padRawDirectory: "Raw-iPad", phoneOutputDirectory: "Screenshots-iPhone", padOutputDirectory: "Screenshots-iPad", phoneTitleSize: 72, phoneSubtitleSize: 36, padTitleSize: 92, padSubtitleSize: 46, phoneShots: simplifiedPhone, padShots: simplifiedPad),
    StoreLocale(code: "zh-Hant", brandLine: "YHPhotos  ·  航攝圖庫", phoneRawDirectory: "Raw-zh-Hant", padRawDirectory: "Raw-iPad-zh-Hant", phoneOutputDirectory: "Screenshots-iPhone-zh-Hant", padOutputDirectory: "Screenshots-iPad-zh-Hant", phoneTitleSize: 72, phoneSubtitleSize: 34, padTitleSize: 90, padSubtitleSize: 44, phoneShots: traditionalPhone, padShots: traditionalPad),
    StoreLocale(code: "en", brandLine: "YHPhotos  ·  Aviation Photography", phoneRawDirectory: "Raw-en", padRawDirectory: "Raw-iPad-en", phoneOutputDirectory: "Screenshots-iPhone-en", padOutputDirectory: "Screenshots-iPad-en", phoneTitleSize: 62, phoneSubtitleSize: 30, padTitleSize: 76, padSubtitleSize: 40, phoneShots: englishPhone, padShots: englishPad)
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appStore = root.appendingPathComponent("AppStore")
let backdropURL = appStore.appendingPathComponent("background-blue-hour.png")
let phoneCanvasSize = NSSize(width: 1320, height: 2868)
let phoneScreenshotRect = NSRect(x: 135, y: 82, width: 1050, height: 2282)
let padCanvasSize = NSSize(width: 2064, height: 2752)
let padScreenshotRect = NSRect(x: 232, y: 72, width: 1600, height: 2133)

func image(at url: URL) throws -> NSImage {
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "StoreShot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot load \(url.path)"])
    }
    return image
}

func drawAspectFill(_ image: NSImage, in rect: NSRect) {
    let scale = max(rect.width / image.size.width, rect.height / image.size.height)
    let sourceSize = NSSize(width: rect.width / scale, height: rect.height / scale)
    let source = NSRect(x: (image.size.width - sourceSize.width) / 2, y: (image.size.height - sourceSize.height) / 2, width: sourceSize.width, height: sourceSize.height)
    image.draw(in: rect, from: source, operation: .sourceOver, fraction: 1)
}

func drawText(_ value: String, in rect: NSRect, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    (value as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}

func makeBitmap(size: NSSize) throws -> (NSBitmapImageRep, NSGraphicsContext) {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "StoreShot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot allocate bitmap"])
    }
    return (bitmap, context)
}

func writeJPEG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.94]) else {
        throw NSError(domain: "StoreShot", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot encode \(url.path)"])
    }
    try data.write(to: url, options: .atomic)
}

func drawScreenshotCard(_ screenshot: NSImage, rect: NSRect, radius: CGFloat, shadowBlur: CGFloat, shadowOffset: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
    shadow.shadowBlurRadius = shadowBlur
    shadow.shadowOffset = NSSize(width: 0, height: shadowOffset)
    shadow.set()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    screenshot.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.2).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: radius, yRadius: radius)
    border.lineWidth = 1.5
    border.stroke()
}

func drawLocalizedPadStatusBar(localeCode: String) {
    guard localeCode != "zh-Hans" else { return }
    let patch = NSRect(x: padScreenshotRect.minX + 18, y: padScreenshotRect.maxY - 36, width: 380, height: 28)
    NSColor.black.setFill()
    patch.fill()
    let status = localeCode == "en" ? "9:41 AM   Tue, Sep 29" : "9:41   9月29日週二"
    drawText(status, in: NSRect(x: padScreenshotRect.minX + 27, y: padScreenshotRect.maxY - 31, width: 360, height: 24), font: .systemFont(ofSize: 14, weight: .semibold), color: .white)
}

let backdrop = try image(at: backdropURL)

for locale in locales {
    let phoneOutput = appStore.appendingPathComponent(locale.phoneOutputDirectory)
    let padOutput = appStore.appendingPathComponent(locale.padOutputDirectory)
    try FileManager.default.createDirectory(at: phoneOutput, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: padOutput, withIntermediateDirectories: true)

    for shot in locale.phoneShots {
        let (bitmap, context) = try makeBitmap(size: phoneCanvasSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawAspectFill(backdrop, in: NSRect(origin: .zero, size: phoneCanvasSize))
        NSColor.black.withAlphaComponent(0.38).setFill()
        NSRect(origin: .zero, size: phoneCanvasSize).fill()
        NSColor(calibratedRed: 75 / 255, green: 184 / 255, blue: 244 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 96, y: 2725, width: 112, height: 10), xRadius: 5, yRadius: 5).fill()
        drawText(locale.brandLine, in: NSRect(x: 96, y: 2635, width: 1128, height: 60), font: .systemFont(ofSize: 34, weight: .semibold), color: NSColor.white.withAlphaComponent(0.72))
        drawText(shot.title, in: NSRect(x: 96, y: 2480, width: 1128, height: 130), font: .systemFont(ofSize: locale.phoneTitleSize, weight: .bold), color: .white)
        drawText(shot.subtitle, in: NSRect(x: 99, y: 2390, width: 1122, height: 80), font: .systemFont(ofSize: locale.phoneSubtitleSize, weight: .medium), color: NSColor.white.withAlphaComponent(0.72))
        let screenshot = try image(at: appStore.appendingPathComponent(locale.phoneRawDirectory).appendingPathComponent(shot.source))
        drawScreenshotCard(screenshot, rect: phoneScreenshotRect, radius: 76, shadowBlur: 42, shadowOffset: -12)
        NSGraphicsContext.restoreGraphicsState()
        try writeJPEG(bitmap, to: phoneOutput.appendingPathComponent(shot.output))
    }

    for shot in locale.padShots {
        let (bitmap, context) = try makeBitmap(size: padCanvasSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawAspectFill(backdrop, in: NSRect(origin: .zero, size: padCanvasSize))
        NSColor.black.withAlphaComponent(0.4).setFill()
        NSRect(origin: .zero, size: padCanvasSize).fill()
        NSColor(calibratedRed: 75 / 255, green: 184 / 255, blue: 244 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 154, y: 2610, width: 150, height: 12), xRadius: 6, yRadius: 6).fill()
        drawText(locale.brandLine, in: NSRect(x: 154, y: 2500, width: 1756, height: 72), font: .systemFont(ofSize: 44, weight: .semibold), color: NSColor.white.withAlphaComponent(0.72))
        drawText(shot.title, in: NSRect(x: 154, y: 2335, width: 1756, height: 140), font: .systemFont(ofSize: locale.padTitleSize, weight: .bold), color: .white)
        drawText(shot.subtitle, in: NSRect(x: 158, y: 2235, width: 1748, height: 86), font: .systemFont(ofSize: locale.padSubtitleSize, weight: .medium), color: NSColor.white.withAlphaComponent(0.72))
        let screenshot = try image(at: appStore.appendingPathComponent(locale.padRawDirectory).appendingPathComponent(shot.source))
        drawScreenshotCard(screenshot, rect: padScreenshotRect, radius: 62, shadowBlur: 52, shadowOffset: -14)
        drawLocalizedPadStatusBar(localeCode: locale.code)
        NSGraphicsContext.restoreGraphicsState()
        try writeJPEG(bitmap, to: padOutput.appendingPathComponent(shot.output))
    }

    print("Rendered \(locale.code): \(locale.phoneShots.count) iPhone and \(locale.padShots.count) iPad screenshots")
}
