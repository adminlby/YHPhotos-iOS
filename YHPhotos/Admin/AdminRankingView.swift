import PhotosUI
import SwiftUI
import UIKit

struct AdminRankingView: View {
    @State private var response: RankingActivitiesResponse?
    @State private var status = "all"
    @State private var offset = 0
    @State private var editor: RankingActivityEditorState?
    @State private var deleting: RankingActivity?
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let limit = 40

    var body: some View {
        List {
            Section {
                Picker("状态", selection: $status) {
                    Text("全部").tag("all"); Text("未开始").tag("upcoming"); Text("进行中").tag("active"); Text("已结束").tag("ended"); Text("归档").tag("archived")
                }
                Button("新建活动", systemImage: "plus.circle.fill") { editor = .init(activity: nil) }
            }
            if let response, !response.items.isEmpty {
                Section("共 \(response.total) 个赛事") {
                    ForEach(response.items) { activity in
                        NavigationLink {
                            RankingActivityDetailView(activity: activity) { Task { await load() } }
                        } label: {
                            HStack(spacing: 12) {
                                if let cover = activity.cover { RemoteImage(urlString: cover).frame(width: 64, height: 48).clipShape(RoundedRectangle(cornerRadius: 8)) }
                                else { Image(systemName: "trophy.fill").frame(width: 64, height: 48).background(.yellow.opacity(0.13), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.orange) }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(activity.name).font(.subheadline.weight(.semibold)); RankingStatusBadge(status: activity.status) }
                                    Text("\(activity.typeLabel) · \(activity.modeLabel) · \(activity.domainLabel)").font(.caption).foregroundStyle(.secondary)
                                    Text("\(activity.rankingMode == "photo_vote" ? activity.entries : activity.participants) \(activity.rankingMode == "photo_vote" ? "件参赛" : "人参赛") · \(activity.startDate ?? "?") ～ \(activity.endDate ?? "?")").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }.padding(.vertical, 3)
                        }.swipeActions {
                            Button("删除", systemImage: "trash", role: .destructive) { deleting = activity }
                            Button("编辑", systemImage: "pencil") { editor = .init(activity: activity) }.tint(.blue)
                        }
                    }
                }
                if response.total > limit { Section { AdminRankingPager(offset: $offset, limit: limit, total: response.total) } }
            } else if !isLoading && errorMessage == nil { EmptyStateView("还没有赛事活动", systemImage: "trophy").listRowBackground(Color.clear) }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("赛事排行")
        .task(id: "\(status)|\(offset)") { await load() }
        .refreshable { await load() }
        .sheet(item: $editor, onDismiss: { Task { await load() } }) { RankingActivityEditor(state: $0) }
        .confirmationDialog("删除赛事“\(deleting?.name ?? "")”及全部参赛、投票数据？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("永久删除", role: .destructive) { if let id = deleting?.id { Task { await delete(id) } } }; Button("取消", role: .cancel) { deleting = nil }
        }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { response = try await APIClient.shared.get("api/admin/ranking/activities", query: [.init(name: "status", value: status), .init(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset))]) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
    @MainActor private func delete(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/ranking/activities/\(id)", method: "DELETE"); deleting = nil; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct RankingActivityDetailView: View {
    let activity: RankingActivity
    let changed: () -> Void
    @State private var tab = "participants"
    var body: some View {
        List {
            Section { Picker("管理内容", selection: $tab) {
                if activity.rankingMode == "photo_vote" { Text("参赛作品").tag("entries") }
                Text(activity.rankingMode == "photo_vote" ? "参与者" : "排行数据").tag("participants")
                Text("奖品 / 领奖").tag("claims")
            }.pickerStyle(.segmented) }
            switch tab {
            case "entries": RankingEntriesSection(activity: activity, changed: changed)
            case "claims": AdminRankingClaimsSections(activity: activity)
            default: RankingParticipantsSection(activity: activity, changed: changed)
            }
        }.navigationTitle(activity.name).navigationBarTitleDisplayMode(.inline)
    }
}

private struct RankingEntriesSection: View {
    let activity: RankingActivity; let changed: () -> Void
    @State private var items: [RankingEntry] = []; @State private var votesOf: RankingEntry?; @State private var deleting: RankingEntry?; @State private var loading = true; @State private var error: String?
    var body: some View {
        Section("参赛作品（\(items.count)）") {
            ForEach(items) { entry in
                HStack(spacing: 11) {
                    RemoteImage(urlString: entry.thumb).frame(width: 62, height: 48).clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 3) { Text(entry.title ?? "（无题）").font(.subheadline.weight(.medium)); Text("#\(entry.photoId) · \(entry.uploader ?? "未知用户") · \(entry.votes) 票").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Button { votesOf = entry } label: { Image(systemName: "heart.text.square") }.buttonStyle(.borderless)
                }.swipeActions { Button("移除", role: .destructive) { deleting = entry } }
            }
            if loading { ProgressView() } else if items.isEmpty { Text("暂无参赛作品").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .task { await load() }
        .sheet(item: $votesOf) { RankingVotesView(entry: $0) { Task { await load(); changed() } } }
        .confirmationDialog("移除该参赛作品？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("移除", role: .destructive) { if let id = deleting?.id { Task { await remove(id) } } }; Button("取消", role: .cancel) {} }
    }
    @MainActor private func load() async { loading = true; do { let r: RankingEntriesResponse = try await APIClient.shared.get("api/admin/ranking/activities/\(activity.id)/entries"); items = r.items; error = nil } catch { self.error = error.localizedDescription }; loading = false }
    @MainActor private func remove(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/ranking/entries/\(id)", method: "DELETE"); deleting = nil; await load(); changed() } catch { self.error = error.localizedDescription } }
}

private struct RankingParticipantsSection: View {
    let activity: RankingActivity; let changed: () -> Void
    @State private var items: [RankingParticipant] = []; @State private var deleting: RankingParticipant?; @State private var loading = true; @State private var error: String?
    var body: some View {
        Section(activity.rankingMode == "photo_vote" ? "参与者（\(items.count)）" : "排行数据（\(items.count)）") {
            ForEach(items) { person in
                HStack(spacing: 11) {
                    if activity.rankingMode != "photo_vote" { Text("#\(person.rank ?? 0)").font(.subheadline.bold()).foregroundStyle(AppTheme.accent).frame(width: 38) }
                    AvatarView(urlString: person.avatar, name: person.displayName ?? "U", size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.displayName ?? "用户 #\(person.userId)").font(.subheadline.weight(.medium))
                        if activity.rankingMode == "photo_vote" { Text("\(person.entries) 件参赛\(person.joinedAt.map { " · " + String($0.prefix(10)) } ?? "")").font(.caption).foregroundStyle(.secondary) }
                        else { Text("上传 \(person.uploadCount ?? 0) · 通过 \(person.approvedCount ?? 0) · 驳回 \(person.rejectedCount ?? 0) · 待审 \(person.pendingCount ?? 0)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if activity.rankingMode != "photo_vote" { Text(person.eligible == false ? "未达门槛" : activity.rankingMode == "approved_count" ? "\(person.approvedCount ?? 0) 张" : "\(person.approvalRate ?? 0)%").font(.caption.weight(.semibold)).foregroundStyle(person.eligible == false ? .secondary : AppTheme.accent) }
                }.swipeActions { Button("移除", role: .destructive) { deleting = person } }
            }
            if loading { ProgressView() } else if items.isEmpty { Text("还没有人加入").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .task { await load() }
        .confirmationDialog("移除该参与者？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("移除", role: .destructive) { if let id = deleting?.id { Task { await remove(id) } } }; Button("取消", role: .cancel) {} }
    }
    @MainActor private func load() async { loading = true; do { let r: RankingParticipantsResponse = try await APIClient.shared.get("api/admin/ranking/activities/\(activity.id)/participants"); items = r.items; error = nil } catch { self.error = error.localizedDescription }; loading = false }
    @MainActor private func remove(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/ranking/participants/\(id)", method: "DELETE"); deleting = nil; await load(); changed() } catch { self.error = error.localizedDescription } }
}

private struct RankingVotesView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: RankingEntry; let changed: () -> Void
    @State private var items: [RankingVote] = []; @State private var error: String?
    var body: some View { NavigationStack { List { ForEach(items) { vote in HStack { AvatarView(urlString: vote.avatar, name: vote.displayName ?? "U", size: 34); VStack(alignment: .leading) { Text(vote.displayName ?? "用户 #\(vote.userId)"); if let at = vote.votedAt { Text(at).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Button("删票", role: .destructive) { Task { await remove(vote.id) } }.buttonStyle(.borderless) } }; if items.isEmpty && error == nil { Text("还没有投票").foregroundStyle(.secondary) }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("投票明细 · \(entry.votes) 票").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }.task { await load() } } }
    @MainActor private func load() async { do { let r: RankingVotesResponse = try await APIClient.shared.get("api/admin/ranking/entries/\(entry.id)/votes"); items = r.items; error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func remove(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/ranking/votes/\(id)", method: "DELETE"); await load(); changed() } catch { self.error = error.localizedDescription } }
}

private struct RankingActivityEditor: View {
    @Environment(\.dismiss) private var dismiss
    let state: RankingActivityEditorState
    @State private var name: String; @State private var type: String; @State private var mode: String; @State private var minimum: String; @State private var domains: Set<String>; @State private var description: String; @State private var rules: String; @State private var start: String; @State private var end: String; @State private var status: String; @State private var coverFilename: String
    @State private var selectedImage: PhotosPickerItem?; @State private var preview: String?; @State private var busy = false; @State private var uploading = false; @State private var error: String?
    init(state: RankingActivityEditorState) { self.state = state; let a = state.activity; _name = .init(initialValue: a?.name ?? ""); _type = .init(initialValue: a?.type ?? "activity"); _mode = .init(initialValue: a?.rankingMode ?? "photo_vote"); _minimum = .init(initialValue: String(a?.minSubmissions ?? 5)); _domains = .init(initialValue: Set(a?.domains ?? ["aviation", "railway", "flight_sim"])); _description = .init(initialValue: a?.description ?? ""); _rules = .init(initialValue: a?.rules ?? ""); _start = .init(initialValue: a?.startDate ?? ""); _end = .init(initialValue: a?.endDate ?? ""); _status = .init(initialValue: a?.status ?? "upcoming"); _coverFilename = .init(initialValue: a?.coverFilename ?? "") }
    var body: some View { NavigationStack { Form {
        Section("基本信息") { TextField("活动名称", text: $name); Picker("排行模式", selection: $mode) { Text("作品投票排行").tag("photo_vote"); Text("上传图片（通过）排行").tag("approved_count"); Text("过图率排行").tag("approval_rate") }; if mode == "approval_rate" { TextField("最低已审投稿量", text: $minimum).keyboardType(.numberPad) }; Picker("类型", selection: $type) { Text("月赛").tag("monthly"); Text("周赛").tag("weekly"); Text("活动").tag("activity"); Text("年度").tag("annual") }; Picker("状态", selection: $status) { Text("未开始").tag("upcoming"); Text("进行中").tag("active"); Text("已结束").tag("ended"); Text("归档").tag("archived") } }
        Section("领域（至少一个）") { Toggle("航空", isOn: domain("aviation")); Toggle("铁路", isOn: domain("railway")); Toggle("飞行模拟", isOn: domain("flight_sim")) }
        Section("活动周期") { TextField("开始日期 YYYY-MM-DD", text: $start); TextField("结束日期 YYYY-MM-DD", text: $end) }
        Section("说明") { TextField("活动描述", text: $description, axis: .vertical).lineLimit(3...8); TextField("活动规则", text: $rules, axis: .vertical).lineLimit(3...10) }
        Section("封面图") { if let preview { RemoteImage(urlString: preview).frame(maxWidth: .infinity).frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10)) } else if let cover = state.activity?.cover, !coverFilename.isEmpty { RemoteImage(urlString: cover).frame(maxWidth: .infinity).frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10)) }; PhotosPicker(selection: $selectedImage, matching: .images) { Label(coverFilename.isEmpty ? "选择封面" : "更换封面", systemImage: "photo.badge.plus") }; if uploading { ProgressView("正在上传…") }; if !coverFilename.isEmpty { Button("移除封面", role: .destructive) { coverFilename = ""; preview = nil } } }
        if let error { Section { Text(error).foregroundStyle(.red) } }
    }.disabled(busy).navigationTitle(state.activity == nil ? "新建活动" : "编辑活动").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || domains.isEmpty || busy || uploading) } }.onChange(of: selectedImage) { item in if let item { Task { await upload(item) } } } } }
    private func domain(_ key: String) -> Binding<Bool> { Binding(get: { domains.contains(key) }, set: { if $0 { domains.insert(key) } else { domains.remove(key) } }) }
    @MainActor private func upload(_ item: PhotosPickerItem) async { uploading = true; defer { uploading = false; selectedImage = nil }; do { guard let raw = try await item.loadTransferable(type: Data.self), let image = UIImage(data: raw), let data = image.jpegData(compressionQuality: 0.9), data.count <= 15 * 1024 * 1024 else { throw RankingImageError.invalid }; let r: RankingUploadResponse = try await APIClient.shared.upload("api/admin/ops/upload", imageData: data, filename: "ranking-cover.jpg", mimeType: "image/jpeg", fields: ["kind": "ranking"]); coverFilename = r.filename; preview = r.url; error = nil } catch { self.error = error.localizedDescription } }
    @MainActor private func save() async { busy = true; defer { busy = false }; do { let body = RankingActivityBody(name: name, type: type, ranking_mode: mode, min_submissions: Int(minimum) ?? 5, domains: Array(domains).sorted(), description: description, rules: rules, cover_filename: coverFilename, start_date: start.isEmpty ? nil : start, end_date: end.isEmpty ? nil : end, status: status); if let id = state.activity?.id { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/ranking/activities/\(id)", method: "PUT", body: body) } else { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/ranking/activities", body: body) }; dismiss() } catch { self.error = error.localizedDescription } }
}

private struct RankingStatusBadge: View { let status: String; var body: some View { Text(["upcoming":"未开始", "active":"进行中", "ended":"已结束", "archived":"归档"][status] ?? status).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(status == "active" ? Color.green.opacity(0.14) : Color.secondary.opacity(0.12), in: Capsule()).foregroundStyle(status == "active" ? .green : .secondary) } }
struct AdminRankingPager: View { @Binding var offset: Int; let limit: Int; let total: Int; var body: some View { HStack { Button("上一页", systemImage: "chevron.left") { offset = max(0, offset - limit) }.disabled(offset == 0); Spacer(); Text("\(offset / limit + 1) / \(max(1, Int(ceil(Double(total) / Double(limit)))))").foregroundStyle(.secondary); Spacer(); Button("下一页") { offset += limit }.disabled(offset + limit >= total); Image(systemName: "chevron.right") } } }

private struct RankingActivityEditorState: Identifiable { let id = UUID(); let activity: RankingActivity? }
struct RankingActivitiesResponse: Codable, Sendable { let items: [RankingActivity]; let total: Int }
struct RankingActivity: Codable, Identifiable, Sendable { let id: Int; let name: String; let type: String; let rankingMode: String; let minSubmissions: Int; let domain: String?; let domains: [String]; let description: String?; let rules: String?; let cover: String?; let coverFilename: String?; let startDate: String?; let endDate: String?; let status: String; let entries: Int; let participants: Int; let createdAt: String?; var typeLabel: String { ["monthly":"月赛", "weekly":"周赛", "activity":"活动", "annual":"年度"][type] ?? type }; var modeLabel: String { ["photo_vote":"作品投票", "approved_count":"通过数", "approval_rate":"过图率"][rankingMode] ?? rankingMode }; var domainLabel: String { domains.map { ["aviation":"航空", "railway":"铁路", "flight_sim":"飞行模拟"][$0] ?? $0 }.joined(separator: "、") } }
private struct RankingActivityBody: Encodable, Sendable { let name: String; let type: String; let ranking_mode: String; let min_submissions: Int; let domains: [String]; let description: String; let rules: String; let cover_filename: String; let start_date: String?; let end_date: String?; let status: String }
private struct RankingEntriesResponse: Codable, Sendable { let items: [RankingEntry] }
private struct RankingEntry: Codable, Identifiable, Sendable { let id: Int; let photoId: Int; let title: String?; let votes: Int; let score: Int; let rank: Int?; let uploader: String?; let thumb: String?; let href: String? }
private struct RankingParticipantsResponse: Codable, Sendable { let items: [RankingParticipant] }
private struct RankingParticipant: Codable, Identifiable, Sendable { let id: Int; let userId: Int; let displayName: String?; let avatar: String?; let entries: Int; let joinedAt: String?; let rank: Int?; let uploadCount: Int?; let approvedCount: Int?; let rejectedCount: Int?; let reviewedCount: Int?; let pendingCount: Int?; let approvalRate: Double?; let eligible: Bool? }
private struct RankingVotesResponse: Codable, Sendable { let items: [RankingVote] }
private struct RankingVote: Codable, Identifiable, Sendable { let id: Int; let userId: Int; let displayName: String?; let avatar: String?; let votedAt: String? }
private struct RankingUploadResponse: Codable, Sendable { let filename: String; let url: String }
private enum RankingImageError: LocalizedError { case invalid; var errorDescription: String? { "请选择有效图片，处理后大小不能超过 15 MB" } }
