import PhotosUI
import SwiftUI
import UIKit

private struct UploadPhotoType: Decodable, Identifiable, Sendable {
    let id: Int?
    let domain: PhotoDomain
    let value: String
    let labelZh: String
    let labelEn: String
    let sortOrder: Int
    let active: Bool
    let relaxAircraftFields: Bool
    let airportOptional: Bool
    var stableID: String { "\(domain.rawValue)-\(value)" }
}

private struct UploadPhotoTypesResponse: Decodable, Sendable { let items: [UploadPhotoType] }
private struct UploadGroup: Decodable, Identifiable, Sendable { let id: Int; let name: String }

private struct UploadQuota: Decodable, Sendable {
    struct Priority: Decodable, Sendable {
        let balance: Int
        let approvalStreak: Int
        let threshold: Int
        let canUse: Int
    }
    let perBatch: Int?
    let todayCount: Int
    let priority: Priority
}

private struct UploadSuggestion: Decodable, Identifiable, Sendable {
    let label: String
    let sub: String?
    let fill: [String: String]
    let ids: [String: Int?]?
    var id: String { "\(label)-\(sub ?? "")" }
}

private enum UploadMode: String, CaseIterable, Identifiable {
    case single, batch
    var id: String { rawValue }
    var title: String { self == .single ? L10n.string("单张上传") : L10n.string("批量上传") }
    var detail: String {
        self == .single
            ? L10n.string("上传一张作品，逐项完成检查与资料填写。")
            : L10n.string("一次选择多张作品，并逐张完成检查与资料填写。")
    }
    var icon: String { self == .single ? "photo" : "photo.stack" }
}

private enum UploadFlowStep: Int, CaseIterable, Identifiable {
    case mode, photos, inspection, information, watermark, apiPublishing, notes, review
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .mode: L10n.string("选择模式")
        case .photos: L10n.string("选择图片")
        case .inspection: L10n.string("图片检查")
        case .information: L10n.string("作品信息")
        case .watermark: L10n.string("水印设置")
        case .apiPublishing: L10n.string("API 发布")
        case .notes: L10n.string("审核设置")
        case .review: L10n.string("提交审核")
        }
    }
    var icon: String {
        switch self {
        case .mode: "square.grid.2x2"
        case .photos: "photo.badge.plus"
        case .inspection: "viewfinder"
        case .information: "text.badge.checkmark"
        case .watermark: "drop.fill"
        case .apiPublishing: "network"
        case .notes: "note.text"
        case .review: "paperplane.fill"
        }
    }
}

private struct UploadAsset: Identifiable {
    let id: UUID
    let data: Data
    var inspectionApproved = false
    var submitted = false
    var domain: PhotoDomain = .aviation
    var title = ""
    var description = ""
    var shotDate = Date()
    var registration = ""
    var aircraftType = ""
    var operatorName = ""
    var airport = ""
    var airportCode = ""
    var flightNumber = ""
    var locomotiveNumber = ""
    var locomotiveModel = ""
    var trainNumber = ""
    var depot = ""
    var lineName = ""
    var station = ""
    var simPlatform = ""
    var simAddon = ""
    var simLivery = ""
    var selectedPhotoTypes: Set<String> = []
    var tags = ""
    var entityIDs: [String: Int] = [:]
    var isHot = false
    var hotReason = ""
    var hotOther = ""
    var ocrAttempted = false
    var ocrRunning = false
    var ocrMessage: String?
    var ocrAutoFilled = false

    init(data: Data) {
        id = UUID()
        self.data = data
    }
}

struct UploadView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var step: UploadFlowStep = .mode
    @State private var uploadMode: UploadMode?
    @State private var selections: [PhotosPickerItem] = []
    @State private var assets: [UploadAsset] = []
    @State private var selectedAssetIndex = 0
    @State private var isLoadingImages = false
    @State private var showingImageInspector = false
    @State private var exitAfterInspector = false

    @State private var availablePhotoTypes: [UploadPhotoType] = UploadView.fallbackPhotoTypes
    @State private var groups: [UploadGroup] = []
    @State private var groupID: Int?
    @State private var quota: UploadQuota?
    @State private var queue = "normal"
    @State private var apiPublished = true
    @State private var moderatorMessage = ""

    @State private var watermarkType = "image"
    @State private var watermarkVariant = "white"
    @State private var watermarkFont = "sans"
    @State private var watermarkColor = "#ffffff"
    @State private var watermarkX = 0.03
    @State private var watermarkY = 0.80
    @State private var watermarkScale = 0.18
    @GestureState private var watermarkDrag: CGSize = .zero
    @GestureState private var watermarkMagnification: CGFloat = 1

    @State private var isSubmitting = false
    @State private var submittedCount = 0
    @State private var errorMessage: String?

    private let simPlatforms = ["MSFS 2020", "MSFS 2024", "X-Plane 12", "X-Plane 11", "P3D", "FSX", "DCS World", "其他"]
    private let hotReasons = ["图库没有的注册号", "涂装变更", "运营人变更", "继承退役飞机的注册号", "其他"]

    var body: some View {
        uploadRoot
    }

    private var uploadRoot: some View {
        NavigationStack {
            uploadScrollView
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("取消")) { dismiss() }.disabled(isSubmitting)
                }
            }
            .safeAreaInset(edge: .bottom) { flowControls }
            .task(id: selections) { await loadSelectedImages() }
            .task { await loadUploadContext() }
            .task(id: ocrTaskID) {
                if step == .information { await recognizeRegistrationIfNeeded() }
            }
            .onChange(of: uploadMode) { _ in
                selections = []
                assets = []
                selectedAssetIndex = 0
                errorMessage = nil
            }
            .onChange(of: watermarkType) { value in
                watermarkScale = value == "image" ? 0.18 : 0.024
            }
            .fullScreenCover(isPresented: $showingImageInspector, onDismiss: {
                if exitAfterInspector {
                    exitAfterInspector = false
                    dismiss()
                }
            }) {
                inspectorCover
            }
            .appScreenBackground()
        }
    }

    private var uploadScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                progressHeader
                stepContent
                errorBanner
            }
            .padding(18)
        }
    }

    @ViewBuilder private var errorBanner: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var inspectorCover: some View {
        if let asset = currentAsset, let image = UIImage(data: asset.data) {
            ImageInspectorView(
                image: image,
                byteCount: asset.data.count,
                onComplianceDecision: { accepted in
                    handleInspectionDecision(for: asset.id, accepted: accepted)
                }
            )
        }
    }

    private var currentAsset: UploadAsset? {
        assets.indices.contains(selectedAssetIndex) ? assets[selectedAssetIndex] : nil
    }
    private var currentDomain: PhotoDomain { currentAsset?.domain ?? .aviation }
    private var ocrTaskID: String {
        "\(step.rawValue)|\(currentAsset?.id.uuidString ?? "none")|\(currentDomain.rawValue)"
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(step.title, systemImage: step.icon).font(.subheadline.weight(.semibold))
                Spacer()
                Text(L10n.format("第 %d 步，共 %d 步", step.rawValue + 1, UploadFlowStep.allCases.count))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(step.rawValue + 1), total: Double(UploadFlowStep.allCases.count))
                .tint(AppTheme.accent)
        }
        .accessibilityElement(children: .combine)
    }

    private var stepContent: AnyView {
        switch step {
        case .mode: AnyView(modeStep)
        case .photos: AnyView(photosStep)
        case .inspection: AnyView(inspectionStep)
        case .information: AnyView(informationStep)
        case .watermark: AnyView(watermarkStep)
        case .apiPublishing: AnyView(apiPublishingStep)
        case .notes: AnyView(notesStep)
        case .review: AnyView(reviewStep)
        }
    }

    private var modeStep: some View {
        VStack(spacing: 14) {
            Text(L10n.string("这次要上传一张，还是一批作品？"))
                .font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(UploadMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { uploadMode = mode }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(uploadMode == mode ? Color.white : AppTheme.accent)
                            .frame(width: 58, height: 58)
                            .background(uploadMode == mode ? AppTheme.accent : AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(mode.title).font(.headline).foregroundStyle(.primary)
                            Text(mode.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: uploadMode == mode ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(uploadMode == mode ? AppTheme.accent : Color.secondary)
                    }
                    .padding(18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(uploadMode == mode ? AppTheme.accent.opacity(0.7) : AppTheme.divider, lineWidth: uploadMode == mode ? 2 : 0.75)
                )
            }
        }
    }

    private var photosStep: some View {
        VStack(spacing: 16) {
            quotaCard
            GlassPanel(cornerRadius: 22) {
                VStack(spacing: 14) {
                    if uploadMode == .batch {
                        PhotosPicker(selection: $selections, maxSelectionCount: maxBatchCount, matching: .images) { pickerLabel }
                    } else {
                        PhotosPicker(selection: $selections, maxSelectionCount: 1, matching: .images) { pickerLabel }
                    }
                    if isLoadingImages {
                        HStack(spacing: 9) { ProgressView(); Text(L10n.string("正在读取所选图片…")) }
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
            }
            if !assets.isEmpty { selectedImagesGrid }
        }
    }

    private var pickerLabel: some View {
        VStack(spacing: 12) {
            Image(systemName: uploadMode == .batch ? "photo.stack.fill" : "photo.badge.plus")
                .font(.system(size: 38)).foregroundStyle(AppTheme.accent)
            Text(uploadMode == .batch ? L10n.string("选择多张图片") : L10n.string("选择一张图片")).font(.headline)
            Text(L10n.string("支持 JPG、PNG、GIF 或 HEIC；每张最大 50 MB。"))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 170).contentShape(Rectangle())
    }

    private var selectedImagesGrid: some View {
        uploadSection(L10n.format("已选择 %d 张", assets.count), icon: "photo.stack") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 76, maximum: 110), spacing: 10, alignment: .top)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.elevated)
                        if let image = UIImage(data: asset.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        }
                        Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(6).background(.black.opacity(0.65), in: Circle()).padding(6)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inspectionStep: some View {
        VStack(spacing: 16) {
            batchAssetSwitcher(showStatus: true)
            if let asset = currentAsset, let image = UIImage(data: asset.data) {
                GlassPanel(cornerRadius: 22) {
                    VStack(spacing: 14) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        if asset.inspectionApproved {
                            Label(L10n.string("这张图片已确认符合标准"), systemImage: "checkmark.seal.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                        }
                        Button { showingImageInspector = true } label: {
                            Label(asset.inspectionApproved ? L10n.string("重新检查") : L10n.string("打开独立图片检查工具"), systemImage: "viewfinder")
                                .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    }
                    .padding(16)
                }
            }
            Text(L10n.string("请在检查工具中查看居中、水平、曝光和灰尘情况。选择“不符合”会退出本次上传；选择“符合标准”才可继续。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var informationStep: some View {
        VStack(spacing: 16) {
            batchAssetSwitcher(showStatus: false)
            domainPicker
            if currentDomain == .aviation { ocrPanel }
            domainFields
            photoTypeFields
            basicFields
            if assets.count > 1 { batchInformationNavigation }
        }
    }

    private var watermarkStep: some View {
        VStack(spacing: 16) {
            batchAssetSwitcher(showStatus: false)
            if let asset = currentAsset, let image = UIImage(data: asset.data) {
                GlassPanel(cornerRadius: 22) { watermarkPreview(image) }
            }
            watermarkFields
            Text(L10n.string("批量上传时，同一套水印位置与样式会应用到本批全部图片。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var apiPublishingStep: some View {
        uploadSection(L10n.string("API 发布设置"), icon: "network") {
            Toggle(L10n.string("允许通过公开 API 发布"), isOn: $apiPublished)
            Text(L10n.string("开启后，作品审核通过时可由已获授权的合作应用和公开接口展示；关闭不会影响 YHPhotos 站内展示。"))
                .font(.caption).foregroundStyle(.secondary)
            Label(
                apiPublished ? L10n.string("审核通过后允许 API 返回作品") : L10n.string("仅在 YHPhotos 站内展示"),
                systemImage: apiPublished ? "checkmark.shield.fill" : "eye.slash.fill"
            )
            .font(.subheadline.weight(.semibold)).foregroundStyle(apiPublished ? .green : .secondary)
        }
    }

    private var notesStep: some View {
        VStack(spacing: 16) {
            publishingFields
            if assets.contains(where: { $0.domain != .flightSim }) {
                batchAssetSwitcher(showStatus: false)
                hotFields
            }
            uploadSection(L10n.string("给审核员的备注"), icon: "note.text") {
                uploadField(L10n.string("给审核员的留言（可选）"), text: $moderatorMessage, lines: 3...7)
            }
        }
    }

    private var reviewStep: some View {
        VStack(spacing: 16) {
            uploadSection(L10n.string("提交前检查"), icon: "checkmark.shield.fill") {
                Label(
                    uploadMode == .batch ? L10n.format("共 %d 张作品将提交审核", assets.count) : L10n.string("作品将提交审核"),
                    systemImage: "paperplane.fill"
                ).font(.headline)
                Text(L10n.string("图片均已通过你的标准确认，必填资料完整。提交后仍需由审核员审核。"))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                LabeledContent(L10n.string("审核队列"), value: queue == "priority" ? L10n.string("优先队列") : L10n.string("普通队列"))
                LabeledContent(L10n.string("公开 API"), value: apiPublished ? L10n.string("允许") : L10n.string("不允许"))
            }
            uploadSection(L10n.string("作品清单"), icon: "photo.stack") {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    HStack(spacing: 12) {
                        if let image = UIImage(data: asset.data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(asset.title.trimmed.isEmpty ? L10n.format("作品 %d", index + 1) : asset.title)
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(reviewMetadata(for: asset)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: asset.submitted ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(asset.submitted ? .green : AppTheme.accent)
                    }
                    if index < assets.count - 1 { Divider() }
                }
            }
            if isSubmitting {
                VStack(spacing: 8) {
                    ProgressView(value: Double(submittedCount), total: Double(max(assets.count, 1)))
                    Text(L10n.format("正在提交 %d / %d", min(submittedCount + 1, assets.count), assets.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var flowControls: some View {
        HStack(spacing: 12) {
            if step != .mode {
                Button { moveBackward() } label: {
                    Label(L10n.string("上一步"), systemImage: "chevron.left").frame(minHeight: 44)
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).disabled(isSubmitting)
            }
            Button {
                if step == .review { Task { await submit() } } else { moveForward() }
            } label: {
                HStack {
                    if isSubmitting { ProgressView() }
                    Text(step == .review ? L10n.string("提交审核") : L10n.string("下一步"))
                    if step != .review { Image(systemName: "chevron.right") }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .disabled(!canContinue || isSubmitting)
        }
        .padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
    }

    private var canContinue: Bool {
        switch step {
        case .mode: uploadMode != nil
        case .photos: !assets.isEmpty && !isLoadingImages
        case .inspection: !assets.isEmpty && assets.allSatisfy(\.inspectionApproved)
        case .information: !assets.isEmpty && assets.allSatisfy(metadataReady)
        case .watermark, .apiPublishing: !assets.isEmpty
        case .notes: assets.allSatisfy(notesReady)
        case .review: !assets.isEmpty && assets.allSatisfy(canSubmit)
        }
    }

    private func moveForward() {
        guard canContinue, let next = UploadFlowStep(rawValue: step.rawValue + 1) else { return }
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.22)) { step = next }
        if next == .inspection {
            selectedAssetIndex = assets.firstIndex(where: { !$0.inspectionApproved }) ?? 0
        } else if next == .information {
            selectedAssetIndex = assets.firstIndex(where: { !metadataReady($0) }) ?? 0
        }
    }

    private func moveBackward() {
        guard let previous = UploadFlowStep(rawValue: step.rawValue - 1) else { return }
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.22)) { step = previous }
    }

    private var maxBatchCount: Int { max(1, quota?.perBatch ?? 10) }

    @ViewBuilder private var quotaCard: some View {
        if let quota {
            GlassPanel(cornerRadius: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.50percent").foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("上传额度")).font(.subheadline.weight(.semibold))
                        Text(L10n.format("今日已上传 %d 张 · 优先额度 %d", quota.todayCount, quota.priority.canUse))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let limit = quota.perBatch {
                        Text(L10n.format("单批最多 %d 张", limit)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder private func batchAssetSwitcher(showStatus: Bool) -> some View {
        if assets.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.format("当前第 %d 张，共 %d 张", selectedAssetIndex + 1, assets.count)).font(.subheadline.weight(.semibold))
                    Spacer()
                    if showStatus {
                        Text(L10n.format("已确认 %d 张", assets.filter(\.inspectionApproved).count)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                            Button { selectedAssetIndex = index } label: {
                                ZStack(alignment: .topTrailing) {
                                    if let image = UIImage(data: asset.data) {
                                        Image(uiImage: image).resizable().scaledToFill().frame(width: 78, height: 62).clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    if showStatus, asset.inspectionApproved {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .green).padding(4)
                                    }
                                }
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(index == selectedAssetIndex ? AppTheme.accent : Color.clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12).background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var batchInformationNavigation: some View {
        HStack {
            Button(L10n.string("上一张"), systemImage: "chevron.left") { selectedAssetIndex = max(0, selectedAssetIndex - 1) }
                .disabled(selectedAssetIndex == 0)
            Spacer()
            if let asset = currentAsset {
                Label(
                    metadataReady(asset) ? L10n.string("资料完整") : L10n.string("资料待补充"),
                    systemImage: metadataReady(asset) ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .font(.caption).foregroundStyle(metadataReady(asset) ? .green : .orange)
            }
            Spacer()
            Button(L10n.string("下一张"), systemImage: "chevron.right") { selectedAssetIndex = min(assets.count - 1, selectedAssetIndex + 1) }
                .disabled(selectedAssetIndex >= assets.count - 1)
        }
        .font(.subheadline.weight(.semibold))
    }

    private var domainPicker: some View {
        Picker(L10n.string("分区"), selection: domainBinding) {
            ForEach(PhotoDomain.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var domainBinding: Binding<PhotoDomain> {
        Binding(
            get: { currentAsset?.domain ?? .aviation },
            set: { newValue in
                guard assets.indices.contains(selectedAssetIndex), assets[selectedAssetIndex].domain != newValue else { return }
                assets[selectedAssetIndex].domain = newValue
                assets[selectedAssetIndex].selectedPhotoTypes = []
                assets[selectedAssetIndex].entityIDs = [:]
                assets[selectedAssetIndex].isHot = false
                assets[selectedAssetIndex].hotReason = ""
                assets[selectedAssetIndex].ocrMessage = nil
                assets[selectedAssetIndex].ocrAttempted = false
            }
        )
    }

    private var ocrPanel: some View {
        uploadSection(L10n.string("注册号识别"), icon: "text.viewfinder") {
            if currentAsset?.ocrRunning == true {
                HStack(spacing: 10) { ProgressView(); Text(L10n.string("正在设备上识别飞机注册号…")).font(.subheadline) }
            } else if let message = currentAsset?.ocrMessage {
                Label(message, systemImage: currentAsset?.ocrAutoFilled == true ? "sparkles" : "info.circle.fill")
                    .font(.subheadline).foregroundStyle(currentAsset?.ocrAutoFilled == true ? .green : .secondary)
            } else {
                Text(L10n.string("将使用 Apple Vision 在设备上读取图片，只提取可能的飞机注册号。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { Task { await recognizeRegistration(force: true) } } label: {
                Label(L10n.string("重新识别注册号"), systemImage: "viewfinder")
            }
            .disabled(currentAsset?.ocrRunning == true)
        }
    }

    private var basicFields: some View {
        uploadSection(L10n.string("作品信息"), icon: "info.circle.fill") {
            uploadField(L10n.string("标题（可选）"), text: assetBinding(\.title, fallback: ""))
            DatePicker(L10n.string("拍摄日期"), selection: assetBinding(\.shotDate, fallback: Date()), displayedComponents: .date)
            uploadField(L10n.string("标签，以逗号分隔（最多 10 个）"), text: assetBinding(\.tags, fallback: ""))
            uploadField(L10n.string("作品说明"), text: assetBinding(\.description, fallback: ""), lines: 3...7)
        }
    }

    @ViewBuilder private var domainFields: some View {
        switch currentDomain {
        case .aviation:
            uploadSection(L10n.string("航空资料"), icon: "airplane") {
                suggestionField(L10n.string("注册号 *"), type: "aircraft_registry", keyPath: \.registration, idKey: "aircraft_registry_id", capitalization: .characters)
                suggestionField(L10n.string("机型 *"), type: "aircraft_type", keyPath: \.aircraftType, idKey: "aircraft_type_id")
                suggestionField(L10n.string("航空公司 *"), type: "airline", keyPath: \.operatorName, idKey: "airline_id")
                suggestionField(L10n.string("机场 *"), type: "airport", keyPath: \.airport, idKey: "airport_id")
                uploadField(L10n.string("航班号（可选）"), text: assetBinding(\.flightNumber, fallback: ""), capitalization: .characters)
            }
        case .railway:
            uploadSection(L10n.string("铁路资料"), icon: "tram.fill") {
                uploadField(L10n.string("车号 / 编组号 *"), text: assetBinding(\.locomotiveNumber, fallback: ""))
                suggestionField(L10n.string("车型 *"), type: "train_model", keyPath: \.locomotiveModel, idKey: "train_model_id")
                uploadField(L10n.string("车次（可选）"), text: assetBinding(\.trainNumber, fallback: ""))
                suggestionField(L10n.string("路局 *"), type: "bureau", keyPath: \.depot, idKey: "bureau_id")
                suggestionField(L10n.string("线路 *"), type: "line", keyPath: \.lineName, idKey: "line_id")
                suggestionField(L10n.string("车站（可选）"), type: "station", keyPath: \.station, idKey: "station_id")
            }
        case .flightSim:
            uploadSection(L10n.string("模拟飞行资料"), icon: "gamecontroller.fill") {
                Picker(L10n.string("平台 *"), selection: assetBinding(\.simPlatform, fallback: "")) {
                    Text(L10n.string("请选择")).tag("")
                    ForEach(simPlatforms, id: \.self) { Text($0).tag($0) }
                }
                suggestionField(L10n.string("机型 *"), type: "aircraft_type", keyPath: \.aircraftType, idKey: "aircraft_type_id")
                suggestionField(L10n.string("航空公司（可选）"), type: "airline", keyPath: \.operatorName, idKey: "airline_id")
                uploadField(L10n.string("涂装（可选）"), text: assetBinding(\.simLivery, fallback: ""))
                uploadField(L10n.string("插件 / 机模（可选）"), text: assetBinding(\.simAddon, fallback: ""))
            }
        }
    }

    private var photoTypeFields: some View {
        uploadSection(L10n.string("作品类型"), icon: "square.grid.2x2.fill") {
            Text(L10n.string("至少选择一项，可多选")).font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(domainPhotoTypes(for: currentDomain), id: \.stableID) { item in
                    let selected = currentAsset?.selectedPhotoTypes.contains(item.value) == true
                    Button {
                        guard assets.indices.contains(selectedAssetIndex) else { return }
                        if selected { assets[selectedAssetIndex].selectedPhotoTypes.remove(item.value) }
                        else { assets[selectedAssetIndex].selectedPhotoTypes.insert(item.value) }
                    } label: {
                        Text(displayName(for: item)).font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(selected ? AppTheme.accent : AppTheme.elevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var watermarkFields: some View {
        uploadSection(L10n.string("水印"), icon: "drop.fill") {
            Picker(L10n.string("水印类型"), selection: $watermarkType) {
                Text(L10n.string("图片标识")).tag("image")
                Text(L10n.string("文字水印")).tag("text")
            }.pickerStyle(.segmented)
            if watermarkType == "image" {
                Picker(L10n.string("标识颜色"), selection: $watermarkVariant) {
                    Text(L10n.string("白色")).tag("white"); Text(L10n.string("黑色")).tag("black")
                }
            } else {
                Picker(L10n.string("字体"), selection: $watermarkFont) {
                    Text("Sans").tag("sans"); Text("Serif").tag("serif"); Text("Mono").tag("mono"); Text("Condensed").tag("condensed")
                }
                Picker(L10n.string("文字颜色"), selection: $watermarkColor) {
                    Text(L10n.string("白色")).tag("#ffffff"); Text(L10n.string("黑色")).tag("#000000")
                    Text(L10n.string("天蓝")).tag("#38bdf8"); Text(L10n.string("橙色")).tag("#fb923c")
                }
            }
            HStack {
                Label(L10n.string("在图片上拖动水印，双指缩放大小"), systemImage: "hand.draw.fill").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.string("复位")) {
                    watermarkX = 0.03; watermarkY = 0.80; watermarkScale = watermarkType == "image" ? 0.18 : 0.024
                }.font(.caption.weight(.semibold))
            }
            Text(L10n.string("预览和最终图片均使用网站相同的水印坐标、缩放比例及底部版权栏。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var publishingFields: some View {
        uploadSection(L10n.string("发布与审核"), icon: "paperplane.fill") {
            Picker(L10n.string("审核队列"), selection: $queue) {
                Text(L10n.string("普通队列")).tag("normal"); Text(L10n.string("优先队列")).tag("priority")
            }
            .onChange(of: queue) { value in
                if value == "priority", quota?.priority.canUse ?? 0 <= 0 {
                    queue = "normal"; errorMessage = L10n.string("当前没有可用的优先审核额度。")
                }
            }
            if !groups.isEmpty {
                Picker(L10n.string("发布到小组（可选）"), selection: $groupID) {
                    Text(L10n.string("不发布到小组")).tag(Int?.none)
                    ForEach(groups) { Text($0.name).tag(Optional($0.id)) }
                }
            }
        }
    }

    @ViewBuilder private var hotFields: some View {
        if currentDomain != .flightSim {
            uploadSection(L10n.string("Hot 候选"), icon: "flame.fill") {
                Toggle(L10n.string("标记为 Hot 候选"), isOn: assetBinding(\.isHot, fallback: false))
                if currentAsset?.isHot == true {
                    Picker(L10n.string("Hot 原因 *"), selection: assetBinding(\.hotReason, fallback: "")) {
                        Text(L10n.string("请选择")).tag("")
                        ForEach(hotReasons, id: \.self) { Text(L10n.string($0)).tag($0) }
                    }
                    if currentAsset?.hotReason == "其他" {
                        uploadField(L10n.string("请填写 Hot 原因"), text: assetBinding(\.hotOther, fallback: ""))
                    }
                }
            }
        }
    }

    private func watermarkPreview(_ image: UIImage) -> some View {
        let ratio = max(image.size.width, 1) / max(image.size.height, 1)
        return Color.clear.aspectRatio(ratio, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 390)
            .overlay {
                GeometryReader { proxy in
                    Image(uiImage: image).resizable().scaledToFit()
                    watermarkMark(width: proxy.size.width)
                        .scaleEffect(watermarkMagnification, anchor: .topLeading)
                        .offset(x: CGFloat(watermarkX) * proxy.size.width + watermarkDrag.width,
                                y: CGFloat(watermarkY) * proxy.size.height + watermarkDrag.height)
                        .gesture(
                            DragGesture().updating($watermarkDrag) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    let bounds = watermarkBounds(in: proxy.size)
                                    watermarkX = min(max(0, watermarkX + value.translation.width / proxy.size.width), bounds.x)
                                    watermarkY = min(max(0, watermarkY + value.translation.height / proxy.size.height), bounds.y)
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture().updating($watermarkMagnification) { value, state, _ in state = value }
                                .onEnded { value in
                                    let range = watermarkType == "image" ? 0.06...0.60 : 0.008...0.08
                                    let newScale = min(max(watermarkScale * value, range.lowerBound), range.upperBound)
                                    watermarkScale = newScale
                                    let bounds = watermarkBounds(in: proxy.size, scale: newScale)
                                    watermarkX = min(watermarkX, bounds.x); watermarkY = min(watermarkY, bounds.y)
                                }
                        )
                    HStack {
                        Text("YHPhotos").foregroundStyle(.white); Spacer()
                        Text("Image Copyright @\(appModel.sessionUser?.username ?? "user")")
                            .foregroundStyle(Color(red: 225 / 255, green: 225 / 255, blue: 225 / 255))
                    }
                    .font(.system(size: max(7, max(14, proxy.size.height * 0.035) * 0.48), weight: .medium))
                    .padding(.horizontal, proxy.size.width * 0.02).frame(height: max(14, proxy.size.height * 0.035))
                    .background(Color.black).frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipped()
    }

    @ViewBuilder private func watermarkMark(width: CGFloat) -> some View {
        if watermarkType == "image" {
            AsyncImage(url: URL(string: "https://www.yhphotos.top/watermark_\(watermarkVariant).png")) { image in
                image.resizable().scaledToFit()
            } placeholder: { ProgressView().controlSize(.small) }
            .frame(width: max(1, width * watermarkScale), height: max(1, width * watermarkScale / 1.5624))
        } else {
            let fontSize = max(8, width * watermarkScale)
            VStack(alignment: .leading, spacing: 0) {
                Text("YHPhotos").font(watermarkFontValue(size: fontSize))
                Text("@\(appModel.sessionUser?.username ?? "user")").font(watermarkFontValue(size: fontSize * 0.76))
            }
            .padding(.horizontal, 6).padding(.vertical, 4).foregroundStyle(Color(hex: watermarkColor))
            .shadow(color: .black.opacity(0.7), radius: 2)
        }
    }

    private func watermarkFontValue(size: CGFloat) -> Font {
        switch watermarkFont {
        case "serif": .system(size: size, design: .serif)
        case "mono": .system(size: size, design: .monospaced)
        case "condensed": .system(size: size, design: .rounded).width(.condensed)
        default: .system(size: size, design: .default)
        }
    }

    private func watermarkBounds(in size: CGSize, scale override: Double? = nil) -> (x: Double, y: Double) {
        let scale = override ?? watermarkScale
        let barHeight = max(14, size.height * 0.035)
        let markWidth: CGFloat
        let markHeight: CGFloat
        if watermarkType == "image" {
            markWidth = size.width * scale; markHeight = markWidth / 1.5624
        } else {
            let fontSize = max(8, size.width * scale)
            markWidth = fontSize * 4.9 + 12; markHeight = fontSize * 1.12 * 1.76 + 8
        }
        return (max(0, Double((size.width - markWidth) / max(size.width, 1))),
                max(0, Double((size.height - barHeight - markHeight) / max(size.height, 1))))
    }

    private func uploadSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: icon).font(.headline)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
    }

    private func uploadField(_ prompt: String, text: Binding<String>, lines: ClosedRange<Int> = 1...1,
                             capitalization: TextInputAutocapitalization = .sentences) -> some View {
        TextField(prompt, text: text, axis: lines.upperBound > 1 ? .vertical : .horizontal)
            .lineLimit(lines).textInputAutocapitalization(capitalization)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private func suggestionField(_ prompt: String, type: String, keyPath: WritableKeyPath<UploadAsset, String>,
                                 idKey: String, capitalization: TextInputAutocapitalization = .sentences) -> some View {
        UploadSuggestionField(
            prompt: prompt, type: type, text: assetBinding(keyPath, fallback: ""), capitalization: capitalization,
            onEdited: {
                guard assets.indices.contains(selectedAssetIndex) else { return }
                assets[selectedAssetIndex].entityIDs.removeValue(forKey: idKey)
                if keyPath == \.registration {
                    assets[selectedAssetIndex].ocrAutoFilled = false; assets[selectedAssetIndex].ocrMessage = nil
                }
            },
            onPick: applySuggestion
        )
    }

    private func assetBinding<Value>(_ keyPath: WritableKeyPath<UploadAsset, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: {
                guard assets.indices.contains(selectedAssetIndex) else { return fallback }
                return assets[selectedAssetIndex][keyPath: keyPath]
            },
            set: { value in
                guard assets.indices.contains(selectedAssetIndex) else { return }
                assets[selectedAssetIndex][keyPath: keyPath] = value
            }
        )
    }

    private func domainPhotoTypes(for domain: PhotoDomain) -> [UploadPhotoType] {
        availablePhotoTypes.filter { $0.domain == domain && $0.active }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func selectedTypeRules(for asset: UploadAsset) -> (relaxed: Bool, airportOptional: Bool) {
        let selected = domainPhotoTypes(for: asset.domain).filter { asset.selectedPhotoTypes.contains($0.value) }
        return (selected.contains(where: \.relaxAircraftFields), selected.contains(where: \.airportOptional))
    }

    private func displayName(for item: UploadPhotoType) -> String {
        AppLanguage.resolved == .english && !item.labelEn.isEmpty ? item.labelEn : item.labelZh
    }
    private func effectiveHotReason(for asset: UploadAsset) -> String {
        asset.hotReason == "其他" ? asset.hotOther.trimmed : asset.hotReason
    }

    private func metadataReady(_ asset: UploadAsset) -> Bool {
        guard !asset.selectedPhotoTypes.isEmpty else { return false }
        switch asset.domain {
        case .aviation:
            let rules = selectedTypeRules(for: asset)
            let baseReady = rules.relaxed || (!asset.registration.trimmed.isEmpty && !asset.aircraftType.trimmed.isEmpty && !asset.operatorName.trimmed.isEmpty)
            return baseReady && (rules.airportOptional || !asset.airport.trimmed.isEmpty)
        case .railway:
            return !asset.locomotiveNumber.trimmed.isEmpty && !asset.locomotiveModel.trimmed.isEmpty && !asset.depot.trimmed.isEmpty && !asset.lineName.trimmed.isEmpty
        case .flightSim:
            return !asset.simPlatform.trimmed.isEmpty && !asset.aircraftType.trimmed.isEmpty
        }
    }
    private func notesReady(_ asset: UploadAsset) -> Bool { !asset.isHot || !effectiveHotReason(for: asset).isEmpty }
    private func canSubmit(_ asset: UploadAsset) -> Bool { asset.inspectionApproved && metadataReady(asset) && notesReady(asset) }

    private func reviewMetadata(for asset: UploadAsset) -> String {
        switch asset.domain {
        case .aviation: [asset.registration, asset.aircraftType].filter { !$0.trimmed.isEmpty }.joined(separator: " · ")
        case .railway: [asset.locomotiveNumber, asset.locomotiveModel].filter { !$0.trimmed.isEmpty }.joined(separator: " · ")
        case .flightSim: [asset.simPlatform, asset.aircraftType].filter { !$0.trimmed.isEmpty }.joined(separator: " · ")
        }
    }

    @MainActor private func loadSelectedImages() async {
        guard !selections.isEmpty else { assets = []; return }
        isLoadingImages = true; errorMessage = nil
        defer { isLoadingImages = false }
        var loaded: [UploadAsset] = []
        var rejectedCount = 0
        for selection in selections {
            guard !Task.isCancelled else { return }
            do {
                guard let rawData = try await selection.loadTransferable(type: Data.self), rawData.count <= 50 * 1024 * 1024 else {
                    rejectedCount += 1; continue
                }
                if isSupportedImage(rawData) {
                    loaded.append(UploadAsset(data: rawData))
                } else if let image = UIImage(data: rawData), let jpeg = image.jpegData(compressionQuality: 0.94) {
                    loaded.append(UploadAsset(data: jpeg))
                } else { rejectedCount += 1 }
            } catch { rejectedCount += 1 }
        }
        assets = loaded; selectedAssetIndex = 0
        if rejectedCount > 0 { errorMessage = L10n.format("有 %d 张图片无法读取或超过 50 MB，已跳过。", rejectedCount) }
    }

    @MainActor private func loadUploadContext() async {
        if let response: UploadPhotoTypesResponse = try? await APIClient.shared.get("api/upload/types"), !response.items.isEmpty {
            availablePhotoTypes = response.items
        }
        groups = (try? await APIClient.shared.get("api/me/groups")) ?? []
        quota = try? await APIClient.shared.get("api/upload/quota")
    }

    @MainActor private func handleInspectionDecision(for assetID: UUID, accepted: Bool) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { showingImageInspector = false; return }
        if accepted {
            assets[index].inspectionApproved = true
            if let next = assets.indices.first(where: { !assets[$0].inspectionApproved }) {
                selectedAssetIndex = next
            } else {
                step = .information
                selectedAssetIndex = assets.firstIndex(where: { !metadataReady($0) }) ?? 0
            }
        } else { exitAfterInspector = true }
        showingImageInspector = false
    }

    @MainActor private func recognizeRegistrationIfNeeded() async {
        guard let asset = currentAsset, asset.domain == .aviation, !asset.ocrAttempted else { return }
        await recognizeRegistration(force: false)
    }

    @MainActor private func recognizeRegistration(force: Bool) async {
        guard assets.indices.contains(selectedAssetIndex), assets[selectedAssetIndex].domain == .aviation else { return }
        let assetID = assets[selectedAssetIndex].id
        if assets[selectedAssetIndex].ocrRunning || (!force && assets[selectedAssetIndex].ocrAttempted) { return }
        assets[selectedAssetIndex].ocrAttempted = true; assets[selectedAssetIndex].ocrRunning = true
        assets[selectedAssetIndex].ocrMessage = nil; assets[selectedAssetIndex].ocrAutoFilled = false
        let data = assets[selectedAssetIndex].data
        do {
            let registration = try await AircraftRegistrationRecognizer.recognize(in: data)
            guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
            assets[index].ocrRunning = false
            guard let registration else {
                assets[index].ocrMessage = L10n.string("未能识别清晰的注册号，请手动填写。"); return
            }
            assets[index].registration = registration
            assets[index].entityIDs.removeValue(forKey: "aircraft_registry_id")
            let suggestions: [UploadSuggestion] = (try? await APIClient.shared.get(
                "api/suggest",
                query: [URLQueryItem(name: "type", value: "aircraft_registry"),
                        URLQueryItem(name: "q", value: registration), URLQueryItem(name: "limit", value: "8")]
            )) ?? []
            guard let refreshedIndex = assets.firstIndex(where: { $0.id == assetID }) else { return }
            if let exact = suggestions.first(where: { normalizedRegistration($0.label) == normalizedRegistration(registration) }) {
                applySuggestion(exact, to: assetID)
                assets[refreshedIndex].ocrAutoFilled = true
                assets[refreshedIndex].ocrMessage = L10n.format("已自动找到注册号 %@ 及相应信息。", registration)
            } else {
                assets[refreshedIndex].ocrMessage = L10n.format("已识别注册号 %@，请手动补充其余资料。", registration)
            }
        } catch {
            guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
            assets[index].ocrRunning = false
            assets[index].ocrMessage = L10n.string("注册号识别失败，请手动填写。")
        }
    }

    @MainActor private func applySuggestion(_ suggestion: UploadSuggestion) {
        guard let id = currentAsset?.id else { return }
        applySuggestion(suggestion, to: id)
    }

    @MainActor private func applySuggestion(_ suggestion: UploadSuggestion, to assetID: UUID) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else { return }
        for (key, value) in suggestion.fill {
            switch key {
            case "aircraft_registration": assets[index].registration = value
            case "aircraft_type": assets[index].aircraftType = value
            case "operator": assets[index].operatorName = value
            case "airport_name": assets[index].airport = value
            case "airport_code": assets[index].airportCode = value
            case "locomotive_model": assets[index].locomotiveModel = value
            case "depot": assets[index].depot = value
            case "line_name": assets[index].lineName = value
            case "station_name": assets[index].station = value
            default: break
            }
        }
        for (key, value) in suggestion.ids ?? [:] { if let value { assets[index].entityIDs[key] = value } }
    }

    @MainActor private func submit() async {
        guard canContinue else { return }
        struct Result: Decodable, Sendable { let id: Int; let status: String }
        isSubmitting = true; errorMessage = nil; submittedCount = assets.filter(\.submitted).count
        defer { isSubmitting = false }
        for asset in assets where !asset.submitted {
            do {
                let kind = imageKind(asset.data)
                let _: Result = try await APIClient.shared.upload(
                    "api/upload", imageData: asset.data, filename: "yhphotos-\(asset.id.uuidString).\(kind.extension)",
                    mimeType: kind.mime, fields: uploadFields(for: asset)
                )
                if let index = assets.firstIndex(where: { $0.id == asset.id }) { assets[index].submitted = true }
                submittedCount += 1
            } catch {
                errorMessage = submittedCount > 0
                    ? L10n.format("已提交 %d 张；其余作品提交失败：%@", submittedCount, error.localizedDescription)
                    : error.localizedDescription
                return
            }
        }
        dismiss()
    }

    private func uploadFields(for asset: UploadAsset) -> [String: String] {
        let selectedTypes = domainPhotoTypes(for: asset.domain).filter { asset.selectedPhotoTypes.contains($0.value) }.map(\.value)
        var fields: [String: String] = [
            "domain": asset.domain.rawValue, "title": asset.title, "description": asset.description,
            "shot_at": DateFormatter.yhPhotoDate.string(from: asset.shotDate), "tags": asset.tags,
            "photo_type": selectedTypes.joined(separator: ","), "category": selectedTypes.first ?? "",
            "moderator_message": moderatorMessage, "queue": queue,
            "is_hot": asset.isHot ? "1" : "0", "hot_reason": effectiveHotReason(for: asset),
            "api_published": apiPublished ? "1" : "0",
            "wm_x": String(watermarkX), "wm_y": String(watermarkY), "wm_scale": String(watermarkScale),
            "wm_type": watermarkType, "wm_variant": watermarkVariant, "wm_font": watermarkFont, "wm_color": watermarkColor,
        ]
        if let groupID { fields["group_id"] = String(groupID) }
        for (key, value) in asset.entityIDs { fields[key] = String(value) }
        switch asset.domain {
        case .aviation:
            fields.merge(["aircraft_registration": asset.registration, "aircraft_type": asset.aircraftType,
                          "operator": asset.operatorName, "airport_name": asset.airport,
                          "airport_code": asset.airportCode, "flight_number": asset.flightNumber]) { _, new in new }
        case .railway:
            fields.merge(["locomotive_number": asset.locomotiveNumber, "locomotive_model": asset.locomotiveModel,
                          "train_number": asset.trainNumber, "depot": asset.depot,
                          "line_name": asset.lineName, "station_name": asset.station]) { _, new in new }
        case .flightSim:
            fields.merge(["aircraft_type": asset.aircraftType, "operator": asset.operatorName,
                          "sim_platform": asset.simPlatform, "sim_livery": asset.simLivery,
                          "sim_addon": asset.simAddon]) { _, new in new }
        }
        return fields
    }

    private func normalizedRegistration(_ value: String) -> String {
        value.uppercased().replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
    }
    private func isSupportedImage(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8, 0xFF]) || data.starts(with: [0x89, 0x50, 0x4E, 0x47]) || data.starts(with: [0x47, 0x49, 0x46, 0x38])
    }
    private func imageKind(_ data: Data) -> (extension: String, mime: String) {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return ("png", "image/png") }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return ("gif", "image/gif") }
        return ("jpg", "image/jpeg")
    }

    private static let fallbackPhotoTypes: [UploadPhotoType] = {
        let values: [PhotoDomain: [String]] = [
            .aviation: ["普通涂装", "特殊涂装", "军用飞机", "公务机", "风格图", "机翼", "夜拍图片", "驾驶舱或客舱", "事故", "直升机", "货机", "机场", "地面车辆", "航母"],
            .railway: ["客运列车", "城市轨道交通", "工程车辆", "特殊涂装", "货运列车", "试运行列车", "风格化图片", "调机", "实验列车", "客运回送", "高速综合检测车", "路用列车", "货运回送", "普速检测列车", "车站"],
            .flightSim: ["普通涂装", "特殊涂装", "风格图", "驾驶舱", "客舱", "夜航", "外景巡航", "进近落地", "地景/机场", "军机"],
        ]
        return values.flatMap { domain, items in
            items.enumerated().map { index, value in
                UploadPhotoType(
                    id: nil, domain: domain, value: value, labelZh: value, labelEn: "", sortOrder: (index + 1) * 10, active: true,
                    relaxAircraftFields: domain == .aviation && ["机场", "驾驶舱或客舱", "地面车辆", "航母", "机翼"].contains(value),
                    airportOptional: domain == .aviation && value == "驾驶舱或客舱"
                )
            }
        }
    }()
}

private struct UploadSuggestionField: View {
    let prompt: String
    let type: String
    @Binding var text: String
    let capitalization: TextInputAutocapitalization
    let onEdited: () -> Void
    let onPick: (UploadSuggestion) -> Void
    @FocusState private var isFocused: Bool
    @State private var suggestions: [UploadSuggestion] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(prompt, text: Binding(get: { text }, set: { value in text = value; onEdited() }))
                    .focused($isFocused).textInputAutocapitalization(capitalization).autocorrectionDisabled(type != "airport")
                if isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))

            if isFocused && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.prefix(8).enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            text = suggestion.label; onPick(suggestion); suggestions = []; isFocused = false
                        } label: {
                            HStack {
                                Text(suggestion.label).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                if let sub = suggestion.sub, !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < min(suggestions.count, 8) - 1 { Divider() }
                    }
                }
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.divider))
            }
        }
        .task(id: "\(isFocused)-\(text)") { await search() }
    }

    @MainActor private func search() async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isFocused, !query.isEmpty else { suggestions = []; return }
        do {
            try await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            isLoading = true; defer { isLoading = false }
            suggestions = try await APIClient.shared.get(
                "api/suggest",
                query: [URLQueryItem(name: "type", value: type), URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "12")]
            )
        } catch is CancellationError {
        } catch { suggestions = []; isLoading = false }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 320
        var x: CGFloat = 0; var y: CGFloat = 0; var lineHeight: CGFloat = 0; var points: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: width, height: y + lineHeight), points)
    }
}

private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
private extension DateFormatter {
    static let yhPhotoDate: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = Calendar(identifier: .gregorian); value.dateFormat = "yyyy-MM-dd"; return value
    }()
}
private extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
