import PhotosUI
import SwiftUI

struct UploadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var domain: PhotoDomain = .aviation
    @State private var title = ""
    @State private var description = ""
    @State private var shotDate = Date()
    @State private var primary = ""
    @State private var secondary = ""
    @State private var location = ""
    @State private var tags = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("选择作品") {
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label(L10n.string(imageData == nil ? "从照片图库选择" : "重新选择"), systemImage: "photo.on.rectangle")
                    }
                }
                Section("作品信息") {
                    Picker("分区", selection: $domain) {
                        ForEach(PhotoDomain.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("标题（可选）", text: $title)
                    DatePicker("拍摄日期", selection: $shotDate, displayedComponents: .date)
                    TextField(primaryLabel, text: $primary)
                    TextField(secondaryLabel, text: $secondary)
                    TextField(locationLabel, text: $location)
                    TextField("标签，以逗号分隔", text: $tags)
                    TextField("作品说明", text: $description, axis: .vertical).lineLimit(3...8)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button { Task { await submit() } } label: {
                        HStack {
                            Spacer()
                            if isSubmitting { ProgressView() } else { Label("提交审核", systemImage: "paperplane.fill") }
                            Spacer()
                        }
                    }
                    .disabled(imageData == nil || primary.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
            .navigationTitle("上传作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .task(id: selection) {
                imageData = try? await selection?.loadTransferable(type: Data.self)
            }
        }
    }

    private var primaryLabel: String {
        switch domain {
        case .aviation: L10n.string("注册号")
        case .railway: L10n.string("车号 / 编组号")
        case .flightSim: L10n.string("机型")
        }
    }
    private var secondaryLabel: String {
        switch domain {
        case .aviation: L10n.string("机型")
        case .railway: L10n.string("车型")
        case .flightSim: L10n.string("平台")
        }
    }
    private var locationLabel: String {
        switch domain {
        case .aviation: L10n.string("机场")
        case .railway: L10n.string("车站")
        case .flightSim: L10n.string("涂装")
        }
    }

    @MainActor
    private func submit() async {
        guard let imageData else { return }
        struct Result: Decodable, Sendable { let id: Int; let status: String }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        var fields: [String: String] = [
            "domain": domain.rawValue,
            "title": title,
            "description": description,
            "shot_at": DateFormatter.yhPhotoDate.string(from: shotDate),
            "tags": tags,
        ]
        switch domain {
        case .aviation:
            fields["aircraft_registration"] = primary
            fields["aircraft_type"] = secondary
            fields["airport_name"] = location
        case .railway:
            fields["locomotive_number"] = primary
            fields["locomotive_model"] = secondary
            fields["station_name"] = location
        case .flightSim:
            fields["aircraft_type"] = primary
            fields["sim_platform"] = secondary
            fields["sim_livery"] = location
        }
        do {
            let kind = imageKind(imageData)
            let _: Result = try await APIClient.shared.upload(
                "api/upload",
                imageData: imageData,
                filename: "yhphotos.\(kind.extension)",
                mimeType: kind.mime,
                fields: fields
            )
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func imageKind(_ data: Data) -> (extension: String, mime: String) {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return ("png", "image/png") }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return ("gif", "image/gif") }
        return ("jpg", "image/jpeg")
    }
}

private extension DateFormatter {
    static let yhPhotoDate: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = Calendar(identifier: .gregorian)
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()
}
