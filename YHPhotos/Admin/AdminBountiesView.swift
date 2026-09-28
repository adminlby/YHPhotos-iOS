import SwiftUI

struct AdminBountiesView: View {
    @State private var status = "all"
    @State private var query = ""
    @State private var response: AdminBountiesResponse?
    @State private var editing: AdminBounty?
    @State private var cancelling: AdminBounty?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $status) {
                    Text("全部").tag("all"); Text("进行中").tag("open"); Text("已完成").tag("completed"); Text("已取消").tag("cancelled"); Text("已关闭").tag("closed")
                }
            }
            if let response {
                Section("共 \(response.total) 个") {
                    ForEach(response.items) { bounty in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(bounty.title).font(.headline).lineLimit(2); Spacer(); BountyStatusBadge(status: bounty.status) }
                            Text("发起人 \(bounty.creator) · \(bounty.submissionCount) 个投稿").font(.caption).foregroundStyle(.secondary)
                            if let target = bounty.targetSummary { Label(target, systemImage: "scope").font(.caption) }
                            if let reward = bounty.rewardText, !reward.isEmpty { Label(reward, systemImage: "gift.fill").font(.caption).foregroundStyle(.orange) }
                            if let description = bounty.description, !description.isEmpty { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                            HStack {
                                Button("编辑", systemImage: "pencil") { editing = bounty }
                                if bounty.status != "cancelled" { Button("取消悬赏", systemImage: "xmark.circle", role: .destructive) { cancelling = bounty } }
                            }.font(.caption)
                        }.padding(.vertical, 4)
                    }
                }
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            else if let errorMessage { EmptyStateView("悬赏加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent) }.listRowBackground(Color.clear) }
            else if response?.items.isEmpty == true { EmptyStateView("没有匹配的悬赏", systemImage: "gift").listRowBackground(Color.clear) }
        }
        .navigationTitle("悬赏管理")
        .searchable(text: $query, prompt: "标题、发起人或目标")
        .task(id: "\(status)|\(query)") { await load() }
        .refreshable { await load() }
        .sheet(item: $editing, onDismiss: { Task { await load() } }) { AdminBountyEditor(bounty: $0) }
        .confirmationDialog("确认取消悬赏“\(cancelling?.title ?? "")”？发起人会收到通知。", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }), titleVisibility: .visible) {
            Button("取消悬赏", role: .destructive) { if let id = cancelling?.id { Task { await cancel(id) } } }
            Button("返回", role: .cancel) { cancelling = nil }
        }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { response = try await APIClient.shared.get("api/admin/bounties", query: [URLQueryItem(name: "status", value: status), URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: "0")]) }
        catch { errorMessage = error.localizedDescription }; isLoading = false
    }
    @MainActor private func cancel(_ id: Int) async {
        do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/bounties/\(id)", method: "DELETE"); cancelling = nil; await load() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AdminBountyEditor: View {
    @Environment(\.dismiss) private var dismiss
    let bounty: AdminBounty
    @State private var title: String
    @State private var description: String
    @State private var targetType: String
    @State private var registryID: String
    @State private var airportID: String
    @State private var airlineID: String
    @State private var dateFrom: String
    @State private var dateTo: String
    @State private var reward: String
    @State private var status: String
    @State private var busy = false
    @State private var errorMessage: String?

    init(bounty: AdminBounty) {
        self.bounty = bounty
        _title = State(initialValue: bounty.title); _description = State(initialValue: bounty.description ?? ""); _targetType = State(initialValue: bounty.targetType)
        _registryID = State(initialValue: bounty.registryID.map(String.init) ?? ""); _airportID = State(initialValue: bounty.airportID.map(String.init) ?? ""); _airlineID = State(initialValue: bounty.airlineID.map(String.init) ?? "")
        _dateFrom = State(initialValue: String((bounty.dateFrom ?? "").prefix(10))); _dateTo = State(initialValue: String((bounty.dateTo ?? "").prefix(10))); _reward = State(initialValue: bounty.rewardText ?? ""); _status = State(initialValue: bounty.status)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") { TextField("标题", text: $title); TextField("说明", text: $description, axis: .vertical).lineLimit(4...8); TextField("奖励说明", text: $reward) }
                Section("目标") {
                    Picker("目标类型", selection: $targetType) { Text("注册号").tag("registration"); Text("机场").tag("airport"); Text("航司").tag("airline"); Text("注册号历史").tag("registration_history"); Text("历史涂装").tag("livery_history"); Text("机场历史时期").tag("airport_period") }
                    TextField("注册号记录 ID", text: $registryID).keyboardType(.numberPad)
                    TextField("机场 ID", text: $airportID).keyboardType(.numberPad)
                    TextField("航司 ID", text: $airlineID).keyboardType(.numberPad)
                    TextField("起始日期 YYYY-MM-DD", text: $dateFrom)
                    TextField("结束日期 YYYY-MM-DD", text: $dateTo)
                }
                Section("状态") { Picker("状态", selection: $status) { Text("进行中").tag("open"); Text("已完成").tag("completed"); Text("已取消").tag("cancelled"); Text("已关闭").tag("closed") } }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("编辑悬赏 #\(bounty.id)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).count < 3 || busy) } }
        }
    }
    @MainActor private func save() async {
        busy = true; defer { busy = false }
        do {
            let body = AdminBountyBody(title: title, description: description, target_type: targetType, registry_id: Int(registryID), airport_id: Int(airportID), airline_id: Int(airlineID), date_from: dateFrom.isEmpty ? nil : dateFrom, date_to: dateTo.isEmpty ? nil : dateTo, reward_text: reward, status: status)
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/bounties/\(bounty.id)", method: "PUT", body: body); dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct BountyStatusBadge: View {
    let status: String
    var body: some View { Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color).padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule()) }
    private var label: String { switch status { case "open": "进行中"; case "completed": "已完成"; case "cancelled": "已取消"; case "closed": "已关闭"; default: status } }
    private var color: Color { switch status { case "open": .green; case "completed": .blue; case "cancelled": .red; default: .secondary } }
}

private struct AdminBounty: Codable, Identifiable, Sendable {
    let id: Int; let creator: String; let creatorID: Int; let title: String; let description: String?; let targetType: String
    let registryID: Int?; let airportID: Int?; let airlineID: Int?; let registration: String?; let airport: String?; let airline: String?
    let dateFrom: String?; let dateTo: String?; let rewardText: String?; let status: String; let submissionCount: Int; let createdAt: String?
    enum CodingKeys: String, CodingKey { case id, creator, title, description, registration, airport, airline, status; case creatorID = "creator_id"; case targetType = "target_type"; case registryID = "registry_id"; case airportID = "airport_id"; case airlineID = "airline_id"; case dateFrom = "date_from"; case dateTo = "date_to"; case rewardText = "reward_text"; case submissionCount = "submission_count"; case createdAt = "created_at" }
    var targetSummary: String? { registration ?? airport ?? airline ?? [dateFrom, dateTo].compactMap { $0 }.joined(separator: " – ").nonEmpty }
}
private struct AdminBountiesResponse: Codable, Sendable { let items: [AdminBounty]; let total: Int }
private struct AdminBountyBody: Encodable, Sendable { let title: String?; let description: String?; let target_type: String?; let registry_id: Int?; let airport_id: Int?; let airline_id: Int?; let date_from: String?; let date_to: String?; let reward_text: String?; let status: String? }

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
