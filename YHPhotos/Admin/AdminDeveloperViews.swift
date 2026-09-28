import SwiftUI

struct AdminFaultInjectionView: View {
    @State private var services: [AdminFaultService] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label("这里只让选中的状态检查 API 返回 HTTP 500，不修改业务数据，也不中断真实功能。", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Section("状态服务") {
                ForEach(services) { service in
                    Toggle(isOn: Binding(get: { selected.contains(service.key) }, set: { enabled in if enabled { selected.insert(service.key) } else { selected.remove(service.key) }; saved = false })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(service.name, systemImage: selected.contains(service.key) ? "exclamationmark.octagon.fill" : "checkmark.circle.fill")
                                .foregroundStyle(selected.contains(service.key) ? .red : .green)
                            Text(service.endpoint).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
                if services.isEmpty && !isLoading { Text("没有可用状态服务").foregroundStyle(.secondary) }
            }
            Section {
                Button(role: .destructive) { Task { await save() } } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text(saved ? "已保存" : "保存故障配置") }; Spacer() } }.disabled(isSaving)
                Button("清空选择", systemImage: "xmark.circle") { selected.removeAll(); saved = false }.disabled(selected.isEmpty || isSaving)
            } footer: { Text("当前选择 \(selected.count) 项。取消选择并保存即可恢复对应状态接口。") }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("故障注入")
        .task { await load() }.refreshable { await load() }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do { let response: AdminFaultResponse = try await APIClient.shared.get("api/admin/dev/fault-injection"); services = response.services; selected = Set(response.active) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
    @MainActor private func save() async {
        isSaving = true; errorMessage = nil; saved = false; defer { isSaving = false }
        do { let response: AdminFaultUpdateResponse = try await APIClient.shared.send("api/admin/dev/fault-injection", method: "PUT", body: AdminFaultBody(services: selected.sorted())); selected = Set(response.active); saved = true }
        catch { errorMessage = error.localizedDescription }
    }
}

struct AdminPriorityGrantView: View {
    @State private var data: AdminPriorityGrantStatus?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let data {
                Section("授予概况") {
                    LabeledContent("在外余额", value: String(data.outstanding))
                    LabeledContent("累计授予", value: String(data.totalGranted))
                    LabeledContent("累计使用", value: String(data.totalUsed))
                    LabeledContent("自动授予总数", value: String(data.autoGrantedTotal))
                    LabeledContent("待审批申请", value: String(data.pendingApplications))
                    LabeledContent("自动授予阈值", value: "连续通过 \(data.threshold) 张 +1")
                }
                if !data.bySource.isEmpty {
                    Section("授予来源") { ForEach(data.bySource.keys.sorted(), id: \.self) { source in LabeledContent(sourceLabel(source), value: "\(data.bySource[source] ?? 0) 笔") } }
                }
                Section("最近授予流水") {
                    if data.grants.isEmpty { Text("暂无授予记录").foregroundStyle(.secondary) }
                    ForEach(data.grants) { grant in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(grant.user).font(.subheadline.weight(.semibold)); Text("@\(grant.username)").font(.caption).foregroundStyle(.secondary); Spacer()
                                Text(grant.amount > 0 ? "+\(grant.amount)" : String(grant.amount)).font(.headline.monospacedDigit()).foregroundStyle(grant.amount < 0 ? .red : .green)
                            }
                            HStack { Text(sourceLabel(grant.source)).foregroundStyle(AppTheme.accent); if let note = grant.note, !note.isEmpty { Text(note) }; if let by = grant.by { Text("· \(by)") } }.font(.caption).foregroundStyle(.secondary)
                            if let date = grant.createdAt { Text(date.replacingOccurrences(of: "T", with: " ").prefix(16)).font(.caption2).foregroundStyle(.tertiary) }
                        }.padding(.vertical, 3)
                    }
                }
                Section("用户优先额度（前 50）") {
                    if data.balances.isEmpty { Text("暂无用户持有优先额度").foregroundStyle(.secondary) }
                    ForEach(data.balances) { balance in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(balance.user).font(.subheadline.weight(.semibold)); Text("@\(balance.username)").font(.caption).foregroundStyle(.secondary); Spacer(); Text("余额 \(balance.balance)").font(.subheadline.weight(.bold)).foregroundStyle(AppTheme.accent) }
                            Text("连续进度 \(balance.streak)/\(data.threshold) · 累计获得 \(balance.totalGranted) · 使用 \(balance.totalUsed)").font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: min(Double(balance.streak), Double(data.threshold)), total: Double(max(1, data.threshold)))
                        }.padding(.vertical, 3)
                    }
                }
            } else if !isLoading {
                EmptyStateView("优先额度状态加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent) }.listRowBackground(Color.clear)
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
        }
        .navigationTitle("优先额度授予")
        .task { await load() }.refreshable { await load() }
    }

    private func sourceLabel(_ source: String) -> String { switch source { case "auto": "自动"; case "application": "申请"; case "admin": "管理员"; default: source } }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { data = try await APIClient.shared.get("api/admin/dev/priority", query: [URLQueryItem(name: "limit", value: "100")]) } catch { errorMessage = error.localizedDescription }; isLoading = false }
}

struct AdminJurySchedulerView: View {
    @State private var data: AdminJurySchedulerStatus?
    @State private var isLoading = true
    @State private var isRunning = false
    @State private var lastProcessed: Int?
    @State private var errorMessage: String?

    private var secondsSinceRun: Int? {
        guard let data, let now = parse(data.dbNow), let last = parse(data.lastRun) else { return nil }
        return max(0, Int(now.timeIntervalSince(last)))
    }
    private var stale: Bool { (secondsSinceRun ?? 0) > 150 }

    var body: some View {
        List {
            if let data {
                Section("调度状态") {
                    LabeledContent("心跳", value: secondsSinceRun.map { stale ? "可能未运行（\($0) 秒）" : "正常（\($0) 秒前）" } ?? "尚无记录").foregroundStyle(stale ? .red : .primary)
                    LabeledContent("进行中仲裁", value: String(data.openReviews))
                    LabeledContent("已到期阶段", value: String(data.overduePhases))
                    LabeledContent("处理进程", value: data.processing ? "处理中" : "空闲")
                    LabeledContent("服务器时间", value: data.dbNow ?? "—")
                    if stale { Label("定时任务可能未启动，可先手动运行一次，并检查后端常驻进程。", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red) }
                }
                Section {
                    Button { Task { await runNow() } } label: { HStack { Spacer(); if isRunning { ProgressView() } else { Label(lastProcessed.map { "已处理 \($0) 个阶段" } ?? "立即处理一次", systemImage: "bolt.fill") }; Spacer() } }.disabled(isRunning)
                } footer: { Text("与定时任务使用同一个带锁入口，多 worker 安全。") }
                Section("进行中的仲裁（\(data.reviews.count)）") {
                    if data.reviews.isEmpty { Label("没有进行中的仲裁", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    ForEach(data.reviews) { review in
                        HStack(alignment: .top, spacing: 11) {
                            AdminSchedulerThumb(url: review.thumb)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(review.title ?? "图片 #\(review.photoId)").font(.subheadline.weight(.semibold)); if review.overdue { Text("已到期").font(.caption2).foregroundStyle(.orange) } }
                                Text("\(review.scopeLabel)\(review.phaseTotal > 1 ? " · 阶段 \(review.phaseSeq ?? 0)/\(review.phaseTotal)" : "")").font(.caption).foregroundStyle(AppTheme.accent)
                                Text("通过 \(review.approveVotes) · 驳回 \(review.rejectVotes)").font(.caption).foregroundStyle(.secondary)
                                if let end = review.phaseEndsAt { Text("截止 \(end.replacingOccurrences(of: "T", with: " ").prefix(16))").font(.caption2).foregroundStyle(.tertiary) }
                                if let reason = review.reason, !reason.isEmpty { Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            }
                        }.padding(.vertical, 3)
                    }
                }
            } else if !isLoading {
                EmptyStateView("调度状态加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent) }.listRowBackground(Color.clear)
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage, data != nil { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("评审团调度")
        .task { await load() }.refreshable { await load() }
    }
    private func parse(_ value: String?) -> Date? { guard var value else { return nil }; if !value.contains("T") { value = value.replacingOccurrences(of: " ", with: "T") }; return ISO8601DateFormatter().date(from: value) ?? ISO8601DateFormatter().date(from: value + "Z") }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { data = try await APIClient.shared.get("api/admin/dev/jury-scheduler") } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func runNow() async { isRunning = true; errorMessage = nil; defer { isRunning = false }; do { let response: AdminSchedulerRunResponse = try await APIClient.shared.send("api/admin/dev/jury-scheduler/run", method: "POST"); lastProcessed = response.processed; await load() } catch { errorMessage = error.localizedDescription } }
}

struct AdminBadgeEngineView: View {
    @State private var data: AdminBadgeEngineStatus?
    @State private var isLoading = true
    @State private var isScanning = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let data {
                if !data.migrationReady {
                    Section { Label("迁移未应用：请执行 2026-06-13_badge_engine.sql，否则累计/关联照片徽章无法授予。", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red) }
                }
                Section("引擎状态") {
                    LabeledContent("上次扫描", value: data.lastScanRan ? (data.lastScanAt ?? "刚刚") : "本次启动尚未完成")
                    LabeledContent("徽章定义", value: "\(data.badges.count) 项")
                    Button { Task { await rescan() } } label: { HStack { if isScanning { ProgressView() }; Label("立即全量重扫并补授", systemImage: "arrow.clockwise") } }.disabled(isScanning)
                }
                Section("徽章支持与授予统计") {
                    ForEach(data.badges) { badge in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(badge.icon).font(.title3); Text(badge.name).font(.subheadline.weight(.semibold)); Text(badge.nameEn).font(.caption).foregroundStyle(.secondary); Spacer(); Text(badge.implementationLabel).font(.caption2.weight(.semibold)).foregroundStyle(badge.implementationColor)
                            }
                            Text(badge.description).font(.caption).foregroundStyle(.secondary)
                            HStack { Text(badge.category); Text(badge.repeatable ? "可累计" : "仅一次"); if badge.photoLinked { Text("关联照片") }; Spacer(); Text("\(badge.holders) 人 · \(badge.awards) 次") }.font(.caption2).foregroundStyle(.secondary)
                            if let warning = badge.warn, !warning.isEmpty { Label(warning, systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange) }
                            if let status = badge.lastStatus { Text("上次扫描：\(status == "ok" ? "完成" : status == "unsupported" ? "跳过" : "出错")\(badge.lastNew.map { " · 新增 \($0)" } ?? "")").font(.caption2).foregroundStyle(status == "error" ? .red : .secondary) }
                            if let error = badge.lastError { Text(error).font(.caption2).foregroundStyle(.red).textSelection(.enabled) }
                        }.padding(.vertical, 4)
                    }
                }
            } else if !isLoading {
                EmptyStateView("徽章引擎加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) { Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent) }.listRowBackground(Color.clear)
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage, data != nil { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle("徽章引擎")
        .task { await load() }.refreshable { await load() }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { data = try await APIClient.shared.get("api/admin/dev/badges") } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func rescan() async { isScanning = true; errorMessage = nil; defer { isScanning = false }; do { let _: AdminBadgeRescanResponse = try await APIClient.shared.send("api/admin/dev/badges/rescan", method: "POST"); await load() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminSchedulerThumb: View {
    let url: String?
    var body: some View { AsyncImage(url: url.flatMap(URL.init(string:))) { phase in if case .success(let image) = phase { image.resizable().scaledToFill() } else { Image(systemName: "photo").foregroundStyle(.secondary) } }.frame(width: 74, height: 54).background(.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 8)) }
}

private struct AdminFaultService: Codable, Identifiable, Sendable { let key: String; let name: String; let endpoint: String; let enabled: Bool; var id: String { key } }
private struct AdminFaultResponse: Codable, Sendable { let active: [String]; let services: [AdminFaultService] }
private struct AdminFaultUpdateResponse: Codable, Sendable { let ok: Bool; let active: [String] }
private struct AdminFaultBody: Encodable, Sendable { let services: [String] }

private struct AdminPriorityGrantStatus: Codable, Sendable { let outstanding: Int; let totalGranted: Int; let totalUsed: Int; let autoGrantedTotal: Int; let bySource: [String: Int]; let pendingApplications: Int; let threshold: Int; let grants: [AdminPriorityGrant]; let balances: [AdminPriorityBalance] }
private struct AdminPriorityGrant: Codable, Identifiable, Sendable { let id: Int; let amount: Int; let source: String; let note: String?; let createdAt: String?; let user: String; let username: String; let by: String? }
private struct AdminPriorityBalance: Codable, Identifiable, Sendable { let userId: Int; let user: String; let username: String; let balance: Int; let streak: Int; let totalGranted: Int; let totalUsed: Int; var id: Int { userId } }
private struct AdminJurySchedulerStatus: Codable, Sendable { let dbNow: String?; let lastRun: String?; let processing: Bool; let openReviews: Int; let overduePhases: Int; let reviews: [AdminScheduledReview] }
private struct AdminScheduledReview: Codable, Identifiable, Sendable { let id: Int; let photoId: Int; let title: String?; let reason: String?; let scope: String; let scopeLabel: String; let phaseSeq: Int?; let phaseTotal: Int; let phaseEndsAt: String?; let overdue: Bool; let approveVotes: Int; let rejectVotes: Int; let thumb: String?; let href: String? }
private struct AdminSchedulerRunResponse: Codable, Sendable { let ok: Bool; let processed: Int }
private struct AdminBadgeEngineStatus: Codable, Sendable { let migrationReady: Bool; let lastScanAt: String?; let lastScanRan: Bool; let lastNotified: Bool?; let badges: [AdminBadgeEngineItem] }
private struct AdminBadgeEngineItem: Codable, Identifiable, Sendable {
    let code: String; let name: String; let nameEn: String; let icon: String; let description: String; let category: String; let repeatable: Bool; let photoLinked: Bool; let impl: String; let warn: String?; let awards: Int; let holders: Int; let lastStatus: String?; let lastNew: Int?; let lastError: String?
    var id: String { code }
    var implementationLabel: String { switch impl { case "ok": "完整"; case "partial": "近似/受限"; case "unsupported": "不支持"; default: impl } }
    var implementationColor: Color { switch impl { case "ok": .green; case "partial": .orange; case "unsupported": .red; default: .secondary } }
}
private struct AdminBadgeRescanResponse: Codable, Sendable { let at: String?; let ran: Bool?; let notified: Bool? }
