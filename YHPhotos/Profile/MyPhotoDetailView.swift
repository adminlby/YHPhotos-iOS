import PhotosUI
import SwiftUI
import UIKit

private struct ReviewFeedback: Decodable, Sendable {
    let photoId: Int
    let layers: [Layer]

    struct Layer: Decodable, Identifiable, Sendable {
        struct ImageInfo: Decodable, Sendable { let width: Double?; let height: Double?; let url: String }
        let kind: String
        let sourceId: Int
        let stage: String
        let status: String?
        let reason: String?
        let note: String?
        let createdAt: String?
        let image: ImageInfo
        let annotations: [Annotation]
        var id: String { "\(kind)-\(sourceId)" }
    }

    struct Annotation: Decodable, Identifiable, Sendable {
        struct Geometry: Decodable, Sendable { let x: Double; let y: Double; let width: Double; let height: Double }
        struct Point: Decodable, Sendable { let x: Double; let y: Double }
        let id: String
        let tool: String
        let reasonText: String
        let color: String
        let strokeWidth: Double
        let geometry: Geometry?
        let points: [Point]?
    }
}

struct MyPhotoDetailView: View {
    let photoID: Int
    @State private var photo: MyPhoto?
    @State private var feedback: ReviewFeedback?
    @State private var selectedLayerID: String?
    @State private var showsAnnotations = true
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var appealReason = ""
    @State private var showingAppeal = false
    @State private var showingWithdrawConfirmation = false
    @State private var revisionItem: PhotosPickerItem?
    @State private var isActing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let photo {
                    annotatedImage(photo)
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(photo.title).font(.title2.bold())
                            Label(statusTitle(photo.status), systemImage: statusIcon(photo.status))
                                .font(.subheadline).foregroundStyle(statusColor(photo.status))
                        }
                        Spacer()
                        if !(feedback?.layers.isEmpty ?? true) {
                            Toggle(isOn: $showsAnnotations) { Image(systemName: "pencil.and.outline") }
                                .labelsHidden()
                        }
                    }
                    metrics(photo)
                    reviewMessages(photo)
                    if let feedback { annotationDetails(feedback) }
                    actions(photo)
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
            }
            .padding(18)
        }
        .navigationTitle(L10n.string("作品详情"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: revisionItem) { _, item in
            guard let item else { return }
            Task { await submitRevision(item) }
        }
        .sheet(isPresented: $showingAppeal) { appealSheet }
        .confirmationDialog(
            L10n.string("撤回申诉？"),
            isPresented: $showingWithdrawConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.string("撤回申诉"), role: .destructive) { Task { await withdrawAppeal() } }
            Button(L10n.string("取消"), role: .cancel) { }
        } message: {
            Text(L10n.string("撤回后作品会恢复为未通过状态。"))
        }
        .appScreenBackground()
    }

    private func annotatedImage(_ photo: MyPhoto) -> some View {
        let layer = activeLayer
        let ratio = max(0.25, min(4, (layer?.image.width ?? 4) / max(1, layer?.image.height ?? 3)))
        return GeometryReader { geometry in
            ZStack {
                if let layer {
                    AuthenticatedReviewImage(path: layer.image.url)
                } else {
                    RemoteImage(url: URL(string: photo.image ?? photo.thumb ?? ""), contentMode: .fit)
                }
                if showsAnnotations {
                    Canvas { context, size in
                        for item in layer?.annotations ?? [] { draw(item, in: &context, size: size) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .aspectRatio(ratio, contentMode: .fit)
    }

    private var activeLayer: ReviewFeedback.Layer? {
        guard let layers = feedback?.layers, !layers.isEmpty else { return nil }
        return layers.first(where: { $0.id == selectedLayerID }) ?? layers.last
    }

    private func draw(_ item: ReviewFeedback.Annotation, in context: inout GraphicsContext, size: CGSize) {
        let color = Color(hex: item.color) ?? .red
        let width = max(2, item.strokeWidth * max(size.width, size.height))
        var path = Path()
        if let g = item.geometry {
            let rect = CGRect(x: g.x * size.width, y: g.y * size.height, width: g.width * size.width, height: g.height * size.height)
            if item.tool == "ellipse" { path.addEllipse(in: rect) } else { path.addRoundedRect(in: rect, cornerSize: CGSize(width: 5, height: 5)) }
        } else if let points = item.points, let first = points.first {
            path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
            for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height)) }
        }
        context.stroke(path, with: .color(color), lineWidth: width)
    }

    private func metrics(_ photo: MyPhoto) -> some View {
        GlassPanel(cornerRadius: 20) {
            HStack(spacing: 0) {
                metric(photo.views, L10n.string("浏览"), "eye.fill")
                metric(photo.likes, L10n.string("获赞"), "heart.fill")
                metric(photo.comments, L10n.string("评论"), "bubble.left.fill")
            }
            .padding(.vertical, 16)
        }
    }

    private func metric(_ value: Int, _ title: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Label(value.compactCount, systemImage: icon).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func reviewMessages(_ photo: MyPhoto) -> some View {
        if photo.rejectionReason != nil || photo.secondRejection != nil || photo.moderatorMessage != nil || photo.appeal != nil {
            GlassPanel(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.string("审核信息"), systemImage: "checkmark.seal.fill").font(.headline)
                    if let value = photo.rejectionReason { message(L10n.string("驳回原因"), value, .red) }
                    if let value = photo.secondRejection { message(L10n.string("二次驳回原因"), value, .red) }
                    if let value = photo.moderatorMessage { message(L10n.string("给审核员的留言"), value, AppTheme.accent) }
                    if let appeal = photo.appeal {
                        message(L10n.string("申诉"), appeal.reason ?? appeal.status, .purple)
                        if let reply = appeal.reply { message(L10n.string("申诉回复"), reply, .green) }
                    }
                }
                .padding(18)
            }
        }
    }

    private func message(_ title: String, _ body: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(body).font(.subheadline).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func annotationDetails(_ feedback: ReviewFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("审核标注")).font(.title3.bold())
            ForEach(feedback.layers) { layer in
                Button { selectedLayerID = layer.id } label: {
                    GlassPanel(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(layer.kind == "review" ? L10n.string("审核标注") : L10n.string("申诉标注"))
                                    .font(.headline)
                                Spacer()
                                if activeLayer?.id == layer.id {
                                    Label(L10n.string("正在查看"), systemImage: "eye.fill")
                                        .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                                } else {
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                            }
                            if let reason = layer.reason { Text(reason).font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(Array(layer.annotations.enumerated()), id: \.element.id) { index, annotation in
                                HStack(alignment: .top, spacing: 9) {
                                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                                        .frame(width: 22, height: 22).background(Color(hex: annotation.color) ?? .red, in: Circle())
                                    Text(annotation.reasonText).font(.subheadline).foregroundStyle(.primary)
                                }
                            }
                            if let note = layer.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                        }
                        .padding(16)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func actions(_ photo: MyPhoto) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("作品操作")).font(.title3.bold())
            if photo.status == "rejected" {
                PhotosPicker(selection: $revisionItem, matching: .images) {
                    Label(L10n.string("提交修正版"), systemImage: "arrow.triangle.2.circlepath.camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActing)
            }
            if photo.canAppeal == true {
                Button { showingAppeal = true } label: {
                    Label(L10n.string("发起申诉"), systemImage: "megaphone.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isActing)
            }
            if photo.status == "appealing", photo.appeal?.status == "pending" {
                Button(role: .destructive) { showingWithdrawConfirmation = true } label: {
                    Label(L10n.string("撤回申诉"), systemImage: "arrow.uturn.backward.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isActing)
            }
            if isActing { ProgressView().frame(maxWidth: .infinity) }
            if let actionMessage {
                Text(actionMessage).font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var appealSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $appealReason).frame(minHeight: 150)
                } header: { Text(L10n.string("申诉理由")) }
                footer: { Text(L10n.string("请具体说明审核结论需要重新考虑的原因，至少 10 个字符。")) }
            }
            .navigationTitle(L10n.string("发起申诉"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.string("取消")) { showingAppeal = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("提交")) { Task { await submitAppeal() } }
                        .disabled(appealReason.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 || isActing)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func statusTitle(_ value: String) -> String { ["pending": "审核中", "approved": "已通过", "rejected": "未通过", "appealing": "申诉中"][value].map(L10n.string) ?? value }
    private func statusIcon(_ value: String) -> String { ["approved": "checkmark.circle.fill", "rejected": "xmark.circle.fill", "appealing": "arrow.triangle.2.circlepath"][value] ?? "clock.fill" }
    private func statusColor(_ value: String) -> Color { ["approved": .green, "rejected": .red, "appealing": .purple][value] ?? .orange }
    private func reload() { Task { await load() } }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded: MyPhoto = try await APIClient.shared.get("api/me/photos/\(photoID)")
            photo = loaded
            if loaded.hasReviewAnnotations == true {
                feedback = try? await APIClient.shared.get("api/me/photos/\(photoID)/annotations")
                selectedLayerID = feedback?.layers.last?.id
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func submitAppeal() async {
        struct Body: Encodable, Sendable { let reason: String }
        let reason = appealReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 10 else { return }
        isActing = true
        defer { isActing = false }
        do {
            let _: APIClient.EmptyResponse = try await APIClient.shared.send(
                "api/me/photos/\(photoID)/appeal", body: Body(reason: reason)
            )
            showingAppeal = false
            appealReason = ""
            actionMessage = L10n.string("申诉已提交")
            await load()
        } catch { actionMessage = error.localizedDescription }
    }

    @MainActor private func withdrawAppeal() async {
        isActing = true
        defer { isActing = false }
        do {
            let _: APIClient.EmptyResponse = try await APIClient.shared.send(
                "api/me/photos/\(photoID)/appeal", method: "DELETE"
            )
            actionMessage = L10n.string("申诉已撤回")
            await load()
        } catch { actionMessage = error.localizedDescription }
    }

    @MainActor private func submitRevision(_ item: PhotosPickerItem) async {
        struct Response: Decodable, Sendable { let ok: Bool; let status: String; let revision: Int }
        isActing = true
        defer {
            isActing = false
            revisionItem = nil
        }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: raw),
                  let data = image.jpegData(compressionQuality: 0.94) else {
                throw APIClientError.invalidResponse
            }
            guard data.count <= 50 * 1024 * 1024 else {
                actionMessage = L10n.string("图片超过 50MB 上限")
                return
            }
            let response: Response = try await APIClient.shared.upload(
                "api/photos/\(photoID)/revision",
                imageData: data,
                filename: "revision.jpg",
                mimeType: "image/jpeg",
                fields: [:]
            )
            actionMessage = L10n.format("修正版 #%d 已提交审核", response.revision)
            await load()
        } catch { actionMessage = error.localizedDescription }
    }
}

private struct AuthenticatedReviewImage: View {
    let path: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                ContentUnavailableView(L10n.string("历史底图无法读取"), systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: path) {
            failed = false
            image = nil
            do {
                let data = try await APIClient.shared.data(path)
                guard let loaded = UIImage(data: data) else { failed = true; return }
                image = loaded
            } catch {
                failed = true
            }
        }
    }
}

private extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 0xff) / 255, green: Double((number >> 8) & 0xff) / 255, blue: Double(number & 0xff) / 255)
    }
}
