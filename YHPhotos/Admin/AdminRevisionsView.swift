import SwiftUI

struct AdminRevisionsView: View {
    @State private var status = "all"
    @State private var query = ""
    @State private var response: AdminRevisionsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section { Picker("状态", selection: $status) { Text("全部").tag("all"); Text("待审").tag("pending"); Text("已通过").tag("approved"); Text("已驳回").tag("rejected"); Text("已被取代").tag("superseded") } }
            if let response {
                Section("共 \(response.total) 条") {
                    ForEach(response.items) { revision in
                        HStack(alignment: .top, spacing: 12) {
                            RemoteImage(urlString: revision.thumb).frame(width: 88, height: 66).clipShape(RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(revision.title ?? "#\(revision.photoId)").font(.subheadline.weight(.semibold)).lineLimit(1); Spacer(); Text("v\(revision.revisionNo)").font(.caption.monospaced()).foregroundStyle(.secondary) }
                                HStack { RevisionStatusBadge(status: revision.status); if let domain = revision.domain { Text(domainName(domain)).font(.caption).foregroundStyle(.secondary) } }
                                Text("提交：\(revision.submitter?.displayName ?? "—") · 审核：\(revision.reviewer?.displayName ?? "—")").font(.caption2).foregroundStyle(.secondary)
                                if let note = revision.rejectionReason ?? revision.note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                                Text(ByteCountFormatter.string(fromByteCount: Int64(revision.fileSize), countStyle: .file)).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }.padding(.vertical, 3)
                    }
                }
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            else if let errorMessage { EmptyStateView("修正版加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent) }.listRowBackground(Color.clear) }
            else if response?.items.isEmpty == true { EmptyStateView("没有修正版记录", systemImage: "clock.arrow.circlepath").listRowBackground(Color.clear) }
        }
        .navigationTitle("修正版审计")
        .searchable(text: $query, prompt: "标题、提交人、说明或驳回理由")
        .task(id: "\(status)|\(query)") { await load() }
        .refreshable { await load() }
    }
    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { response = try await APIClient.shared.get("api/admin/revisions", query: [URLQueryItem(name: "status", value: status), URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: "0")]) }
        catch { errorMessage = error.localizedDescription }; isLoading = false
    }
}

private struct RevisionStatusBadge: View {
    let status: String
    var body: some View { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color).padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.12), in: Capsule()) }
    private var label: String { switch status { case "pending": "待审"; case "approved": "已通过"; case "rejected": "已驳回"; case "superseded": "已被取代"; default: status } }
    private var color: Color { switch status { case "approved": .green; case "rejected": .red; case "pending": .orange; default: .secondary } }
}
private struct RevisionPerson: Codable, Sendable { let id: Int; let displayName: String? }
private struct AdminRevision: Codable, Identifiable, Sendable { let id: Int; let photoId: Int; let revisionNo: Int; let title: String?; let domain: String?; let thumb: String?; let status: String; let photoStatus: String; let fileSize: Int; let rejectionReason: String?; let note: String?; let submitter: RevisionPerson?; let reviewer: RevisionPerson?; let createdAt: String? }
private struct AdminRevisionsResponse: Codable, Sendable { let items: [AdminRevision]; let total: Int }
