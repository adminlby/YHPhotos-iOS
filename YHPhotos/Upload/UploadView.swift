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

private struct UploadPhotoTypesResponse: Decodable, Sendable {
    let items: [UploadPhotoType]
}

private struct UploadGroup: Decodable, Identifiable, Sendable {
    let id: Int
    let name: String
}

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

struct UploadView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var domain: PhotoDomain = .aviation
    @State private var title = ""
    @State private var description = ""
    @State private var shotDate = Date()
    @State private var registration = ""
    @State private var aircraftType = ""
    @State private var operatorName = ""
    @State private var airport = ""
    @State private var airportCode = ""
    @State private var flightNumber = ""
    @State private var locomotiveNumber = ""
    @State private var locomotiveModel = ""
    @State private var trainNumber = ""
    @State private var depot = ""
    @State private var lineName = ""
    @State private var station = ""
    @State private var simPlatform = ""
    @State private var simAddon = ""
    @State private var simLivery = ""
    @State private var availablePhotoTypes: [UploadPhotoType] = UploadView.fallbackPhotoTypes
    @State private var selectedPhotoTypes: Set<String> = []
    @State private var tags = ""
    @State private var moderatorMessage = ""
    @State private var groups: [UploadGroup] = []
    @State private var groupID: Int?
    @State private var entityIDs: [String: Int] = [:]
    @State private var quota: UploadQuota?
    @State private var queue = "normal"
    @State private var isHot = false
    @State private var hotReason = ""
    @State private var hotOther = ""
    @State private var apiPublished = true
    @State private var watermarkType = "image"
    @State private var watermarkVariant = "white"
    @State private var watermarkFont = "sans"
    @State private var watermarkColor = "#ffffff"
    @State private var watermarkX = 0.03
    @State private var watermarkY = 0.80
    @State private var watermarkScale = 0.18
    @GestureState private var watermarkDrag: CGSize = .zero
    @GestureState private var watermarkMagnification: CGFloat = 1
    @State private var showingImageInspector = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let simPlatforms = ["MSFS 2020", "MSFS 2024", "X-Plane 12", "X-Plane 11", "P3D", "FSX", "DCS World", "其他"]
    private let hotReasons = ["图库没有的注册号", "涂装变更", "运营人变更", "继承退役飞机的注册号", "其他"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    domainPicker
                    quotaCard
                    imagePicker
                    basicFields
                    domainFields
                    photoTypeFields
                    watermarkFields
                    publishingFields
                    reviewCard
                    submitButton
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L10n.string("上传作品"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.string("取消")) { dismiss() } } }
            .task(id: selection) { await loadSelectedImage() }
            .task { await loadUploadContext() }
            .onChange(of: domain) { _, _ in
                selectedPhotoTypes = []
                entityIDs = [:]
                isHot = false
                hotReason = ""
                if watermarkType == "image" { watermarkScale = 0.18 }
            }
            .onChange(of: watermarkType) { _, value in
                watermarkScale = value == "image" ? 0.18 : 0.024
            }
            .sheet(isPresented: $showingImageInspector) {
                if let imageData, let image = UIImage(data: imageData) {
                    ImageInspectorView(image: image, byteCount: imageData.count)
                }
            }
            .appScreenBackground()
        }
    }

    private var domainPicker: some View {
        Picker(L10n.string("分区"), selection: $domain) {
            ForEach(PhotoDomain.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var quotaCard: some View {
        if let quota {
            GlassPanel(cornerRadius: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .foregroundStyle(AppTheme.accent)
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

    private var imagePicker: some View {
        GlassPanel(cornerRadius: 22) {
            Group {
                if let imageData, let image = UIImage(data: imageData) {
                    watermarkPreview(image)
                        .overlay(alignment: .topTrailing) {
                            PhotosPicker(selection: $selection, matching: .images) {
                                Label(L10n.string("更换"), systemImage: "arrow.triangle.2.circlepath")
                                    .font(.caption.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 7)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                        }
                        .overlay(alignment: .bottomLeading) {
                            Button { showingImageInspector = true } label: {
                                Label(L10n.string("图片检查工具"), systemImage: "viewfinder")
                                    .font(.caption.weight(.semibold)).padding(.horizontal, 11).padding(.vertical, 7)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .padding(.bottom, 18)
                        }
                } else {
                    PhotosPicker(selection: $selection, matching: .images) {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 36)).foregroundStyle(AppTheme.accent)
                            Text(L10n.string("选择 JPG、PNG、GIF 或 HEIC 作品")).font(.headline)
                            Text(L10n.string("最大 50 MB；HEIC 会在设备上转换为兼容的 JPEG。"))
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 210)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func watermarkPreview(_ image: UIImage) -> some View {
        let ratio = max(image.size.width, 1) / max(image.size.height, 1)
        return Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 360)
            .overlay {
                GeometryReader { proxy in
                    Image(uiImage: image).resizable().scaledToFit()
                    watermarkMark(width: proxy.size.width)
                        .scaleEffect(watermarkMagnification, anchor: .topLeading)
                        .offset(
                            x: CGFloat(watermarkX) * proxy.size.width + watermarkDrag.width,
                            y: CGFloat(watermarkY) * proxy.size.height + watermarkDrag.height
                        )
                        .gesture(
                            DragGesture()
                                .updating($watermarkDrag) { value, state, _ in state = value.translation }
                                .onEnded { value in
                                    let bounds = watermarkBounds(in: proxy.size)
                                    watermarkX = min(max(0, watermarkX + value.translation.width / proxy.size.width), bounds.x)
                                    watermarkY = min(max(0, watermarkY + value.translation.height / proxy.size.height), bounds.y)
                                }
                        )
                        .simultaneousGesture(
                            MagnifyGesture()
                                .updating($watermarkMagnification) { value, state, _ in state = value.magnification }
                                .onEnded { value in
                                    let range = watermarkType == "image" ? 0.06...0.60 : 0.008...0.08
                                    let newScale = min(max(watermarkScale * value.magnification, range.lowerBound), range.upperBound)
                                    watermarkScale = newScale
                                    let bounds = watermarkBounds(in: proxy.size, scale: newScale)
                                    watermarkX = min(watermarkX, bounds.x)
                                    watermarkY = min(watermarkY, bounds.y)
                                }
                        )
                    HStack {
                        Text("YHPhotos").foregroundStyle(.white)
                        Spacer()
                        Text("Image Copyright @\(appModel.sessionUser?.username ?? "user")")
                            .foregroundStyle(Color(red: 225 / 255, green: 225 / 255, blue: 225 / 255))
                    }
                    .font(.system(size: max(7, max(14, proxy.size.height * 0.035) * 0.48), weight: .medium))
                    .padding(.horizontal, proxy.size.width * 0.02)
                    .frame(height: max(14, proxy.size.height * 0.035))
                    .background(Color.black)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipped()
    }

    @ViewBuilder private func watermarkMark(width: CGFloat) -> some View {
        if watermarkType == "image" {
            AsyncImage(url: URL(string: "https://www.yhphotos.top/watermark_\(watermarkVariant).png")) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().controlSize(.small)
            }
            .frame(width: max(1, width * watermarkScale), height: max(1, width * watermarkScale / 1.5624))
        } else {
            let fontSize = max(8, width * watermarkScale)
            VStack(alignment: .leading, spacing: 0) {
                Text("YHPhotos")
                    .font(watermarkFont(size: fontSize))
                Text("@\(appModel.sessionUser?.username ?? "user")")
                    .font(watermarkFont(size: fontSize * 0.76))
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .foregroundStyle(Color(hex: watermarkColor))
            .shadow(color: .black.opacity(0.7), radius: 2)
        }
    }

    private func watermarkFont(size: CGFloat) -> Font {
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
            markWidth = size.width * scale
            markHeight = markWidth / 1.5624
        } else {
            let fontSize = max(8, size.width * scale)
            markWidth = fontSize * 4.9 + 12
            markHeight = fontSize * 1.12 * 1.76 + 8
        }
        return (
            max(0, Double((size.width - markWidth) / max(size.width, 1))),
            max(0, Double((size.height - barHeight - markHeight) / max(size.height, 1)))
        )
    }

    private var basicFields: some View {
        uploadSection(L10n.string("作品信息"), icon: "info.circle.fill") {
            uploadField(L10n.string("标题（可选）"), text: $title)
            DatePicker(L10n.string("拍摄日期"), selection: $shotDate, displayedComponents: .date)
            uploadField(L10n.string("标签，以逗号分隔（最多 10 个）"), text: $tags)
            uploadField(L10n.string("作品说明"), text: $description, lines: 3...7)
        }
    }

    @ViewBuilder private var domainFields: some View {
        switch domain {
        case .aviation:
            uploadSection(L10n.string("航空资料"), icon: "airplane") {
                suggestionField(L10n.string("注册号 *"), type: "aircraft_registry", text: $registration, idKey: "aircraft_registry_id", capitalization: .characters)
                suggestionField(L10n.string("机型 *"), type: "aircraft_type", text: $aircraftType, idKey: "aircraft_type_id")
                suggestionField(L10n.string("航空公司 *"), type: "airline", text: $operatorName, idKey: "airline_id")
                suggestionField(L10n.string("机场 *"), type: "airport", text: $airport, idKey: "airport_id")
                uploadField(L10n.string("航班号（可选）"), text: $flightNumber, capitalization: .characters)
            }
        case .railway:
            uploadSection(L10n.string("铁路资料"), icon: "tram.fill") {
                uploadField(L10n.string("车号 / 编组号 *"), text: $locomotiveNumber)
                suggestionField(L10n.string("车型 *"), type: "train_model", text: $locomotiveModel, idKey: "train_model_id")
                uploadField(L10n.string("车次（可选）"), text: $trainNumber)
                suggestionField(L10n.string("路局 *"), type: "bureau", text: $depot, idKey: "bureau_id")
                suggestionField(L10n.string("线路 *"), type: "line", text: $lineName, idKey: "line_id")
                suggestionField(L10n.string("车站（可选）"), type: "station", text: $station, idKey: "station_id")
            }
        case .flightSim:
            uploadSection(L10n.string("模拟飞行资料"), icon: "gamecontroller.fill") {
                Picker(L10n.string("平台 *"), selection: $simPlatform) {
                    Text(L10n.string("请选择")).tag("")
                    ForEach(simPlatforms, id: \.self) { Text($0).tag($0) }
                }
                suggestionField(L10n.string("机型 *"), type: "aircraft_type", text: $aircraftType, idKey: "aircraft_type_id")
                suggestionField(L10n.string("航空公司（可选）"), type: "airline", text: $operatorName, idKey: "airline_id")
                uploadField(L10n.string("涂装（可选）"), text: $simLivery)
                uploadField(L10n.string("插件 / 机模（可选）"), text: $simAddon)
            }
        }
    }

    private var photoTypeFields: some View {
        uploadSection(L10n.string("作品类型"), icon: "square.grid.2x2.fill") {
            Text(L10n.string("至少选择一项，可多选"))
                .font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(domainPhotoTypes, id: \.stableID) { item in
                    Button {
                        if selectedPhotoTypes.contains(item.value) { selectedPhotoTypes.remove(item.value) }
                        else { selectedPhotoTypes.insert(item.value) }
                    } label: {
                        Text(displayName(for: item))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedPhotoTypes.contains(item.value) ? Color.white : Color.primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(selectedPhotoTypes.contains(item.value) ? AppTheme.accent : AppTheme.elevated, in: Capsule())
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
            }
            .pickerStyle(.segmented)
            if watermarkType == "image" {
                Picker(L10n.string("标识颜色"), selection: $watermarkVariant) {
                    Text(L10n.string("白色")).tag("white")
                    Text(L10n.string("黑色")).tag("black")
                }
            } else {
                Picker(L10n.string("字体"), selection: $watermarkFont) {
                    Text("Sans").tag("sans")
                    Text("Serif").tag("serif")
                    Text("Mono").tag("mono")
                    Text("Condensed").tag("condensed")
                }
                Picker(L10n.string("文字颜色"), selection: $watermarkColor) {
                    Text(L10n.string("白色")).tag("#ffffff")
                    Text(L10n.string("黑色")).tag("#000000")
                    Text(L10n.string("天蓝")).tag("#38bdf8")
                    Text(L10n.string("橙色")).tag("#fb923c")
                }
            }
            HStack {
                Label(L10n.string("在图片上拖动水印，双指缩放大小"), systemImage: "hand.draw.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.string("复位")) {
                    watermarkX = 0.03
                    watermarkY = 0.80
                    watermarkScale = watermarkType == "image" ? 0.18 : 0.024
                }
                .font(.caption.weight(.semibold))
            }
            Text(L10n.string("预览和最终图片均使用网站相同的水印坐标、缩放比例及底部版权栏。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var publishingFields: some View {
        uploadSection(L10n.string("发布设置"), icon: "paperplane.fill") {
            Picker(L10n.string("审核队列"), selection: $queue) {
                Text(L10n.string("普通队列")).tag("normal")
                Text(L10n.string("优先队列")).tag("priority")
            }
            .onChange(of: queue) { _, value in
                if value == "priority", quota?.priority.canUse ?? 0 <= 0 {
                    queue = "normal"
                    errorMessage = L10n.string("当前没有可用的优先审核额度。")
                }
            }
            if !groups.isEmpty {
                Picker(L10n.string("发布到小组（可选）"), selection: $groupID) {
                    Text(L10n.string("不发布到小组")).tag(Int?.none)
                    ForEach(groups) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if domain != .flightSim {
                Toggle(L10n.string("标记为 Hot 候选"), isOn: $isHot)
                if isHot {
                    Picker(L10n.string("Hot 原因 *"), selection: $hotReason) {
                        Text(L10n.string("请选择")).tag("")
                        ForEach(hotReasons, id: \.self) { Text(L10n.string($0)).tag($0) }
                    }
                    if hotReason == "其他" { uploadField(L10n.string("请填写 Hot 原因"), text: $hotOther) }
                }
            }
            Toggle(L10n.string("允许通过公开 API 发布"), isOn: $apiPublished)
            uploadField(L10n.string("给审核员的留言（可选）"), text: $moderatorMessage, lines: 2...5)
        }
    }

    private var reviewCard: some View {
        GlassPanel(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.string("提交前检查"), systemImage: "checkmark.shield.fill").font(.headline)
                Text(L10n.string("请确认图片清晰、拍摄日期准确、主体资料完整。联想列表中的官方条目会同时关联实体图库。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
    }

    private var submitButton: some View {
        VStack(spacing: 10) {
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red) }
            Button { Task { await submit() } } label: {
                HStack {
                    if isSubmitting { ProgressView() } else { Label(L10n.string("提交审核"), systemImage: "paperplane.fill") }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .disabled(!canSubmit || isSubmitting)
        }
    }

    private func uploadSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: icon).font(.headline)
                content()
            }
            .padding(18)
        }
    }

    private func uploadField(_ prompt: String, text: Binding<String>, lines: ClosedRange<Int> = 1...1, capitalization: TextInputAutocapitalization = .sentences) -> some View {
        TextField(prompt, text: text, axis: lines.upperBound > 1 ? .vertical : .horizontal)
            .lineLimit(lines)
            .textInputAutocapitalization(capitalization)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private func suggestionField(
        _ prompt: String,
        type: String,
        text: Binding<String>,
        idKey: String,
        capitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        UploadSuggestionField(
            prompt: prompt,
            type: type,
            text: text,
            capitalization: capitalization,
            onEdited: { entityIDs.removeValue(forKey: idKey) },
            onPick: applySuggestion
        )
    }

    private var domainPhotoTypes: [UploadPhotoType] {
        availablePhotoTypes.filter { $0.domain == domain && $0.active }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedTypeRules: (relaxed: Bool, airportOptional: Bool) {
        let selected = domainPhotoTypes.filter { selectedPhotoTypes.contains($0.value) }
        return (selected.contains(where: \.relaxAircraftFields), selected.contains(where: \.airportOptional))
    }

    private func displayName(for item: UploadPhotoType) -> String {
        Locale.current.language.languageCode?.identifier == "en" && !item.labelEn.isEmpty ? item.labelEn : item.labelZh
    }

    private var effectiveHotReason: String {
        hotReason == "其他" ? hotOther.trimmed : hotReason
    }

    private var canSubmit: Bool {
        guard imageData != nil, !selectedPhotoTypes.isEmpty else { return false }
        if isHot && effectiveHotReason.isEmpty { return false }
        switch domain {
        case .aviation:
            let baseReady = selectedTypeRules.relaxed || (!registration.trimmed.isEmpty && !aircraftType.trimmed.isEmpty && !operatorName.trimmed.isEmpty)
            let airportReady = selectedTypeRules.airportOptional || !airport.trimmed.isEmpty
            return baseReady && airportReady
        case .railway:
            return !locomotiveNumber.trimmed.isEmpty && !locomotiveModel.trimmed.isEmpty && !depot.trimmed.isEmpty && !lineName.trimmed.isEmpty
        case .flightSim:
            return !simPlatform.trimmed.isEmpty && !aircraftType.trimmed.isEmpty
        }
    }

    @MainActor private func loadSelectedImage() async {
        guard let selection else { return }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else { return }
            guard data.count <= 50 * 1024 * 1024 else {
                imageData = nil
                errorMessage = L10n.string("图片超过 50 MB 上限。")
                return
            }
            if isSupportedImage(data) {
                imageData = data
            } else if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.94) {
                imageData = jpeg
            } else {
                imageData = nil
                errorMessage = L10n.string("无法读取所选图片，请换一张重试。")
                return
            }
            errorMessage = nil
        } catch {
            imageData = nil
            errorMessage = error.localizedDescription
        }
    }

    @MainActor private func loadUploadContext() async {
        if let response: UploadPhotoTypesResponse = try? await APIClient.shared.get("api/upload/types"), !response.items.isEmpty {
            availablePhotoTypes = response.items
        }
        groups = (try? await APIClient.shared.get("api/me/groups")) ?? []
        quota = try? await APIClient.shared.get("api/upload/quota")
    }

    @MainActor private func applySuggestion(_ suggestion: UploadSuggestion) {
        for (key, value) in suggestion.fill {
            switch key {
            case "aircraft_registration": registration = value
            case "aircraft_type": aircraftType = value
            case "operator": operatorName = value
            case "airport_name": airport = value
            case "airport_code": airportCode = value
            case "locomotive_model": locomotiveModel = value
            case "depot": depot = value
            case "line_name": lineName = value
            case "station_name": station = value
            default: break
            }
        }
        for (key, value) in suggestion.ids ?? [:] {
            if let value { entityIDs[key] = value }
        }
    }

    @MainActor private func submit() async {
        guard let imageData, canSubmit else { return }
        struct Result: Decodable, Sendable { let id: Int; let status: String }
        isSubmitting = true; errorMessage = nil
        defer { isSubmitting = false }
        let selectedTypes = domainPhotoTypes.filter { selectedPhotoTypes.contains($0.value) }.map(\.value)
        var fields: [String: String] = [
            "domain": domain.rawValue, "title": title, "description": description,
            "shot_at": DateFormatter.yhPhotoDate.string(from: shotDate), "tags": tags,
            "photo_type": selectedTypes.joined(separator: ","), "category": selectedTypes.first ?? "",
            "moderator_message": moderatorMessage, "queue": queue,
            "is_hot": isHot ? "1" : "0", "hot_reason": effectiveHotReason,
            "api_published": apiPublished ? "1" : "0",
            "wm_x": String(watermarkX), "wm_y": String(watermarkY), "wm_scale": String(watermarkScale),
            "wm_type": watermarkType, "wm_variant": watermarkVariant,
            "wm_font": watermarkFont, "wm_color": watermarkColor,
        ]
        if let groupID { fields["group_id"] = String(groupID) }
        for (key, value) in entityIDs { fields[key] = String(value) }
        switch domain {
        case .aviation:
            fields.merge(["aircraft_registration": registration, "aircraft_type": aircraftType, "operator": operatorName, "airport_name": airport, "airport_code": airportCode, "flight_number": flightNumber]) { _, new in new }
        case .railway:
            fields.merge(["locomotive_number": locomotiveNumber, "locomotive_model": locomotiveModel, "train_number": trainNumber, "depot": depot, "line_name": lineName, "station_name": station]) { _, new in new }
        case .flightSim:
            fields.merge(["aircraft_type": aircraftType, "operator": operatorName, "sim_platform": simPlatform, "sim_livery": simLivery, "sim_addon": simAddon]) { _, new in new }
        }
        do {
            let kind = imageKind(imageData)
            let _: Result = try await APIClient.shared.upload("api/upload", imageData: imageData, filename: "yhphotos.\(kind.extension)", mimeType: kind.mime, fields: fields)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func isSupportedImage(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8, 0xFF]) ||
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ||
        data.starts(with: [0x47, 0x49, 0x46, 0x38])
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
                    id: nil, domain: domain, value: value, labelZh: value, labelEn: "",
                    sortOrder: (index + 1) * 10, active: true,
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
                TextField(prompt, text: Binding(
                    get: { text },
                    set: { value in text = value; onEdited() }
                ))
                .focused($isFocused)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(type != "airport")
                if isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12))

            if isFocused && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.prefix(8).enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            text = suggestion.label
                            onPick(suggestion)
                            suggestions = []
                            isFocused = false
                        } label: {
                            HStack {
                                Text(suggestion.label).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                if let sub = suggestion.sub, !sub.isEmpty {
                                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .contentShape(Rectangle())
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
            isLoading = true
            defer { isLoading = false }
            suggestions = try await APIClient.shared.get(
                "api/suggest",
                query: [URLQueryItem(name: "type", value: type), URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "12")]
            )
        } catch is CancellationError {
        } catch {
            suggestions = []
            isLoading = false
        }
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
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var points: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: width, height: y + lineHeight), points)
    }
}

private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }

private extension DateFormatter {
    static let yhPhotoDate: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = Calendar(identifier: .gregorian)
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
