import SwiftUI
import UIKit

struct AdminReviewAnnotationEditor: View {
    @Environment(\.dismiss) private var dismiss

    let detail: AdminReviewDetail
    let reasons: [AdminRejectionReason]
    @Binding var annotations: [AdminReviewAnnotation]

    @State private var working: [AdminReviewAnnotation] = []
    @State private var activeReasonID: Int?
    @State private var tool: AdminReviewAnnotation.Tool = .ellipse
    @State private var image: UIImage?
    @State private var errorMessage: String?
    @State private var draft: AdminReviewAnnotation?
    @State private var startPoint: AdminReviewAnnotation.Point?

    private let colors = ["#fb7185", "#f59e0b", "#38bdf8", "#a78bfa", "#34d399", "#f472b6"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                Divider()
                Group {
                    if let image {
                        annotationCanvas(image)
                            .background(Color.black)
                    } else if let errorMessage {
                        EmptyStateView("原图加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                            Button("重试") { Task { await loadImage() } }
                        }
                    } else {
                        ProgressView("正在加载原图…")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                annotationList
            }
            .navigationTitle("审核标注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        annotations = working
                        dismiss()
                    }
                }
            }
        }
        .task {
            working = annotations
            activeReasonID = reasons.first?.id
            await loadImage()
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("理由", selection: $activeReasonID) {
                    ForEach(reasons) { reason in Text(reason.title).tag(Optional(reason.id)) }
                }
                .pickerStyle(.menu)
                Spacer()
                Button("标注全图") { markFullImage() }
                    .buttonStyle(.bordered)
                    .disabled(activeReason == nil)
            }
            Picker("工具", selection: $tool) {
                Text("圆形").tag(AdminReviewAnnotation.Tool.ellipse)
                Text("矩形").tag(AdminReviewAnnotation.Tool.rect)
                Text("画笔").tag(AdminReviewAnnotation.Tool.path)
                Text("箭头").tag(AdminReviewAnnotation.Tool.arrow)
            }
            .pickerStyle(.segmented)
            HStack {
                Text(activeReason.map { "当前理由：\($0.title)" } ?? "请先选择理由")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("撤销") { if !working.isEmpty { working.removeLast() } }
                    .disabled(working.isEmpty)
                Button("清空", role: .destructive) { working.removeAll() }
                    .disabled(working.isEmpty)
            }
            .font(.caption)
        }
        .padding(12)
        .background(.bar)
    }

    private func annotationCanvas(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            let rect = aspectFitRect(imageSize: image.size, in: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                Canvas { context, size in
                    for annotation in working { draw(annotation, context: &context, size: size) }
                    if let draft { draw(draft, context: &context, size: size) }
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .gesture(annotationGesture(size: rect.size))
            }
        }
    }

    private var annotationList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(working) { item in
                    HStack(spacing: 5) {
                        Circle().fill(Color(annotationHex: item.color)).frame(width: 8, height: 8)
                        Text(item.reasonText).lineLimit(1)
                        Button {
                            working.removeAll { $0.id == item.id }
                        } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }
            .padding(10)
        }
        .frame(height: working.isEmpty ? 0 : 52)
        .background(.bar)
    }

    private func annotationGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let reason = activeReason else { return }
                let point = normalized(value.location, size: size)
                if startPoint == nil {
                    startPoint = point
                    draft = baseAnnotation(reason: reason, start: point)
                    return
                }
                guard let start = startPoint, var current = draft else { return }
                switch tool {
                case .rect, .ellipse:
                    current = annotation(
                        from: current,
                        geometry: .init(
                            x: min(start.x, point.x),
                            y: min(start.y, point.y),
                            width: abs(start.x - point.x),
                            height: abs(start.y - point.y)
                        ),
                        points: nil
                    )
                case .arrow:
                    current = annotation(from: current, geometry: nil, points: [start, point])
                case .path:
                    var points = current.points ?? [start]
                    if let last = points.last,
                       hypot(point.x - last.x, point.y - last.y) > 0.0025 {
                        points.append(point)
                    }
                    current = annotation(from: current, geometry: nil, points: points)
                }
                draft = current
            }
            .onEnded { _ in
                if let draft, isValid(draft) { working.append(draft) }
                draft = nil
                startPoint = nil
            }
    }

    private var activeReason: AdminRejectionReason? {
        reasons.first { $0.id == activeReasonID }
    }

    private func baseAnnotation(reason: AdminRejectionReason, start: AdminReviewAnnotation.Point) -> AdminReviewAnnotation {
        let color = colors[(reasons.firstIndex(of: reason) ?? 0) % colors.count]
        return AdminReviewAnnotation(
            id: "ann-\(UUID().uuidString.lowercased())",
            tool: tool,
            reasonId: reason.id,
            reasonText: reason.title + (reason.content.map { "：\($0)" } ?? ""),
            color: color,
            strokeWidth: 0.004,
            geometry: tool == .rect || tool == .ellipse ? .init(x: start.x, y: start.y, width: 0, height: 0) : nil,
            points: tool == .path || tool == .arrow ? [start, start] : nil
        )
    }

    private func annotation(
        from source: AdminReviewAnnotation,
        geometry: AdminReviewAnnotation.Geometry?,
        points: [AdminReviewAnnotation.Point]?
    ) -> AdminReviewAnnotation {
        AdminReviewAnnotation(
            id: source.id, tool: source.tool, reasonId: source.reasonId,
            reasonText: source.reasonText, color: source.color, strokeWidth: source.strokeWidth,
            geometry: geometry, points: points
        )
    }

    private func markFullImage() {
        guard let reason = activeReason else { return }
        var item = baseAnnotation(reason: reason, start: .init(x: 0, y: 0))
        item = annotation(from: item, geometry: .init(x: 0, y: 0, width: 1, height: 1), points: nil)
        working.removeAll {
            $0.tool == .rect && $0.reasonId == reason.id && $0.geometry == .init(x: 0, y: 0, width: 1, height: 1)
        }
        working.append(item)
    }

    private func normalized(_ point: CGPoint, size: CGSize) -> AdminReviewAnnotation.Point {
        .init(
            x: min(max(Double(point.x / max(size.width, 1)), 0), 1),
            y: min(max(Double(point.y / max(size.height, 1)), 0), 1)
        )
    }

    private func isValid(_ item: AdminReviewAnnotation) -> Bool {
        if let geometry = item.geometry { return geometry.width >= 0.005 && geometry.height >= 0.005 }
        guard let points = item.points, points.count >= 2,
              let first = points.first, let last = points.last else { return false }
        return hypot(last.x - first.x, last.y - first.y) >= 0.005
    }

    private func aspectFitRect(imageSize: CGSize, in size: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func draw(_ item: AdminReviewAnnotation, context: inout GraphicsContext, size: CGSize) {
        let color = Color(annotationHex: item.color)
        let width = max(2, CGFloat(item.strokeWidth) * max(size.width, size.height))
        var path = Path()
        if let geometry = item.geometry {
            let rect = CGRect(
                x: geometry.x * size.width,
                y: geometry.y * size.height,
                width: geometry.width * size.width,
                height: geometry.height * size.height
            )
            if item.tool == .ellipse { path.addEllipse(in: rect) } else { path.addRoundedRect(in: rect, cornerSize: .init(width: 5, height: 5)) }
            context.fill(path, with: .color(color.opacity(0.1)))
            context.stroke(path, with: .color(color), lineWidth: width)
            return
        }
        guard let points = item.points, let first = points.first else { return }
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        if item.tool == .arrow, points.count >= 2, let last = points.last {
            let before = points[points.count - 2]
            drawArrowHead(from: before, to: last, color: color, width: width, context: &context, size: size)
        }
    }

    private func drawArrowHead(
        from: AdminReviewAnnotation.Point,
        to: AdminReviewAnnotation.Point,
        color: Color,
        width: CGFloat,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let p1 = CGPoint(x: from.x * size.width, y: from.y * size.height)
        let p2 = CGPoint(x: to.x * size.width, y: to.y * size.height)
        let angle = atan2(p2.y - p1.y, p2.x - p1.x)
        let length = max(12, width * 4)
        var head = Path()
        head.move(to: p2)
        head.addLine(to: CGPoint(x: p2.x - length * cos(angle - .pi / 6), y: p2.y - length * sin(angle - .pi / 6)))
        head.move(to: p2)
        head.addLine(to: CGPoint(x: p2.x - length * cos(angle + .pi / 6), y: p2.y - length * sin(angle + .pi / 6)))
        context.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    @MainActor private func loadImage() async {
        errorMessage = nil
        do {
            let data: Data
            if detail.canViewOriginal, let path = detail.originalUrl {
                data = try await APIClient.shared.data(path)
            } else if let url = MediaURL.resolve(detail.image) {
                let result = try await URLSession.shared.data(from: url)
                guard let response = result.1 as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else { throw APIClientError.invalidResponse }
                data = result.0
            } else { throw APIClientError.invalidResponse }
            guard let decoded = UIImage(data: data) else { throw APIClientError.invalidResponse }
            image = decoded
        } catch { errorMessage = error.localizedDescription }
    }
}

private extension Color {
    init(annotationHex: String) {
        let value = annotationHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let number = UInt64(value, radix: 16) ?? 0xff4d4f
        self.init(
            red: Double((number >> 16) & 0xff) / 255,
            green: Double((number >> 8) & 0xff) / 255,
            blue: Double(number & 0xff) / 255
        )
    }
}
