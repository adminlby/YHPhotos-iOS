import SwiftUI

struct AdminJuryView: View {
    @State private var mode = JuryAdminMode.members
    var body: some View {
        VStack(spacing: 0) {
            Picker("评审团管理", selection: $mode) { Text("成员").tag(JuryAdminMode.members); Text("报名申请").tag(JuryAdminMode.applications); Text("仲裁").tag(JuryAdminMode.reviews) }
                .pickerStyle(.segmented).padding()
            switch mode {
            case .members: AdminJuryMembersPanel()
            case .applications: AdminJuryApplicationsPanel()
            case .reviews: AdminJuryReviewsPanel()
            }
        }
        .navigationTitle("评审团")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AdminJuryMembersPanel: View {
    @State private var response: JuryMembersResponse?
    @State private var offset = 0
    @State private var appointing = false
    @State private var deleting: JuryMember?
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let limit = 40
    var body: some View {
        List {
            Section { Button("任命评审团成员", systemImage: "person.badge.plus") { appointing = true } }
            if let response, !response.items.isEmpty {
                Section("共 \(response.total) 名成员") {
                    ForEach(response.items) { member in
                        HStack(spacing: 11) {
                            AvatarView(urlString: member.avatar, name: member.displayName, size: 42)
                            VStack(alignment: .leading, spacing: 4) { HStack { Text(member.displayName).font(.subheadline.weight(.semibold)); JuryStatusBadge(status: member.status) }; Text("\(member.votesCount) 次投票\(member.appointer.map { " · 由 \($0) 任命" } ?? "")").font(.caption).foregroundStyle(.secondary); if let expires = member.expiresAt { Text("任期至 \(expires.prefix(10))").font(.caption2).foregroundStyle(.tertiary) } }
                            Spacer()
                            Menu {
                                Button("设为在任") { Task { await setStatus(member.id, "active") } }
                                Button("暂停") { Task { await setStatus(member.id, "suspended") } }
                                Button("停用") { Task { await setStatus(member.id, "inactive") } }
                                Button("移除成员", role: .destructive) { deleting = member }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }.padding(.vertical, 3)
                    }
                }
                JuryPager(offset: $offset, limit: limit, total: response.total)
            } else if !isLoading && errorMessage == nil { EmptyStateView("还没有评审团成员", systemImage: "checkmark.seal").listRowBackground(Color.clear) }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .task(id: offset) { await load() }.refreshable { await load() }
        .sheet(isPresented: $appointing, onDismiss: { Task { await load() } }) { JuryAppointView() }
        .confirmationDialog("移除评审团成员“\(deleting?.displayName ?? "")”？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("移除", role: .destructive) { if let id = deleting?.id { Task { await remove(id) } } }; Button("取消", role: .cancel) { deleting = nil } }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { response = try await APIClient.shared.get("api/admin/jury/members", query: [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]) } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func setStatus(_ id: Int, _ status: String) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/jury/members/\(id)/status", method: "PUT", body: JuryStatusBody(status: status)); await load() } catch { errorMessage = error.localizedDescription } }
    @MainActor private func remove(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/jury/members/\(id)", method: "DELETE"); deleting = nil; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct JuryAppointView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""; @State private var users: [JuryLookupUser] = []; @State private var selected: JuryLookupUser?; @State private var hasExpiry = false; @State private var expiry = Date().addingTimeInterval(365 * 86400); @State private var busy = false; @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("用户") {
                    TextField("用户名 / 昵称 / 邮箱 / ID", text: $query).textInputAutocapitalization(.never)
                    ForEach(users) { user in Button { selected = user; query = user.displayName; users = [] } label: { HStack { AvatarView(urlString: user.avatar, name: user.displayName, size: 32); VStack(alignment: .leading) { Text(user.displayName).foregroundStyle(.primary); Text("@\(user.username) · #\(user.id)").font(.caption).foregroundStyle(.secondary) }; Spacer(); if selected?.id == user.id { Image(systemName: "checkmark.circle.fill") } } } }
                    if let selected { LabeledContent("已选择", value: "\(selected.displayName) (#\(selected.id))") }
                }
                Section("任期") { Toggle("设置到期时间", isOn: $hasExpiry); if hasExpiry { DatePicker("到期", selection: $expiry, displayedComponents: [.date, .hourAndMinute]) } }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("任命评审团成员").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("任命") { Task { await save() } }.disabled(selected == nil || busy) } }
            .task(id: query) { await lookup() }
        }
    }
    @MainActor private func lookup() async { guard !query.isEmpty, selected?.displayName != query else { users = []; return }; do { try? await Task.sleep(nanoseconds: 250_000_000); let response: JuryLookupResponse = try await APIClient.shared.get("api/admin/ops/user-lookup", query: [URLQueryItem(name: "q", value: query)]); guard !Task.isCancelled else { return }; users = response.items } catch { users = [] } }
    @MainActor private func save() async { guard let selected else { return }; busy = true; defer { busy = false }; do { let body = JuryAppointBody(user_id: selected.id, expires_at: hasExpiry ? ISO8601DateFormatter().string(from: expiry) : nil); let _: AdminActionResponse = try await APIClient.shared.send("api/admin/jury/members", body: body); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminJuryApplicationsPanel: View {
    @State private var status = "pending"
    @State private var items: [JuryApplication] = []
    @State private var resolving: JuryApplicationDecisionState?
    @State private var editingRequirements = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    var body: some View {
        List {
            Section { Picker("状态", selection: $status) { Text("待审核").tag("pending"); Text("已通过").tag("approved"); Text("已驳回").tag("rejected"); Text("全部").tag("all") }.pickerStyle(.menu); Button("报名要求设置", systemImage: "slider.horizontal.3") { editingRequirements = true } }
            if !items.isEmpty {
                Section("申请（\(items.count)）") {
                    ForEach(items) { app in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { AvatarView(urlString: app.avatar, name: app.displayName, size: 38); VStack(alignment: .leading) { Text(app.displayName).font(.subheadline.weight(.semibold)); Text("@\(app.username) · 注册 \(app.stats.days) 天 · 通过 \(app.stats.approved) 张 · 过图率 \(app.stats.rate)%").font(.caption).foregroundStyle(.secondary) }; Spacer(); JuryApplicationBadge(status: app.status) }
                            if let statement = app.statement, !statement.isEmpty { Text(statement).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                            if let note = app.note, !note.isEmpty { Label(note, systemImage: "text.bubble").font(.caption).foregroundStyle(.secondary) }
                            if app.status == "pending" { HStack { Button("通过并加入评审团") { resolving = JuryApplicationDecisionState(application: app, decision: "approve") }.tint(.green); Button("驳回", role: .destructive) { resolving = JuryApplicationDecisionState(application: app, decision: "reject") } }.font(.caption) }
                        }.padding(.vertical, 4)
                    }
                }
            } else if !isLoading && errorMessage == nil { EmptyStateView("没有匹配的报名申请", systemImage: "person.crop.circle.badge.questionmark").listRowBackground(Color.clear) }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .task(id: status) { await load() }.refreshable { await load() }
        .sheet(item: $resolving, onDismiss: { Task { await load() } }) { JuryApplicationDecisionView(state: $0) }
        .sheet(isPresented: $editingRequirements) { JuryRequirementsView() }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { let response: JuryApplicationsResponse = try await APIClient.shared.get("api/admin/jury/applications", query: [URLQueryItem(name: "status", value: status)]); items = response.items } catch { errorMessage = error.localizedDescription }; isLoading = false }
}

private struct JuryApplicationDecisionView: View {
    @Environment(\.dismiss) private var dismiss
    let state: JuryApplicationDecisionState
    @State private var note = ""; @State private var busy = false; @State private var errorMessage: String?
    var body: some View { NavigationStack { Form { Section { Text(state.decision == "approve" ? "通过后，用户会立即加入评审团并收到通知。" : "请填写驳回说明，用户会收到通知。") }; Section("处理备注") { TextField("选填", text: $note, axis: .vertical).lineLimit(3...7) }; if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } } }.navigationTitle(state.decision == "approve" ? "通过申请" : "驳回申请").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(state.decision == "approve" ? "通过" : "驳回", role: state.decision == "reject" ? .destructive : nil) { Task { await resolve() } }.disabled(busy) } } } }
    @MainActor private func resolve() async { busy = true; defer { busy = false }; do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/jury/applications/\(state.application.id)/resolve", body: JuryResolveBody(decision: state.decision, note: note.isEmpty ? nil : note)); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct JuryRequirementsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var requirements: JuryRequirements?
    @State private var busy = false; @State private var errorMessage: String?
    var body: some View { NavigationStack { Form { if let binding = requirementBinding { Section { Toggle("开放报名", isOn: binding.applyOpen) }; Section("门槛（勾选项需同时满足）") { Toggle("启用注册天数", isOn: binding.days.enabled); Stepper("注册至少 \(binding.wrappedValue.days.value) 天", value: binding.days.value, in: 0...3650); Toggle("启用通过作品数", isOn: binding.approved.enabled); Stepper("通过至少 \(binding.wrappedValue.approved.value) 张", value: binding.approved.value, in: 0...100_000); Toggle("启用过图率", isOn: binding.rate.enabled); Stepper("过图率至少 \(binding.wrappedValue.rate.value)%", value: binding.rate.value, in: 0...100) } } else { HStack { Spacer(); ProgressView(); Spacer() } }; if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } } }.navigationTitle("报名要求").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(requirements == nil || busy) } }.task { await load() } } }
    private var requirementBinding: Binding<JuryRequirements>? { guard requirements != nil else { return nil }; return Binding(get: { requirements! }, set: { requirements = $0 }) }
    @MainActor private func load() async { do { requirements = try await APIClient.shared.get("api/admin/jury/requirements") } catch { errorMessage = error.localizedDescription } }
    @MainActor private func save() async { guard let requirements else { return }; busy = true; defer { busy = false }; do { let body = JuryRequirementsBody(apply_open: requirements.applyOpen, days_on: requirements.days.enabled, days: requirements.days.value, approved_on: requirements.approved.enabled, approved: requirements.approved.value, rate_on: requirements.rate.enabled, rate: requirements.rate.value); let _: AdminActionResponse = try await APIClient.shared.send("api/admin/jury/requirements", method: "PUT", body: body); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct AdminJuryReviewsPanel: View {
    @State private var status = "active"
    @State private var items: [JuryReview] = []
    @State private var creating = false
    @State private var cancelling: JuryReview?
    @State private var isLoading = true
    @State private var errorMessage: String?
    var body: some View {
        List {
            Section { Picker("状态", selection: $status) { Text("全部").tag("all"); Text("进行中").tag("active"); Text("待开始").tag("upcoming"); Text("已结束").tag("closed"); Text("已取消").tag("cancelled") }.pickerStyle(.menu); Button("发起评审仲裁", systemImage: "plus.circle.fill") { creating = true } }
            if !items.isEmpty {
                Section("仲裁记录（\(items.count)）") {
                    ForEach(items) { review in
                        HStack(alignment: .top, spacing: 11) {
                            RemoteImage(urlString: review.thumb).frame(width: 78, height: 58).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(review.title ?? "图片 #\(review.photoId)").font(.subheadline.weight(.semibold)); JuryReviewBadge(review: review) }
                                Text(review.reason ?? "仲裁请求").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text("\(review.scopeLabel)\(review.phaseTotal > 1 ? " · 阶段 \(review.phaseSeq ?? 0)/\(review.phaseTotal)" : "") · 通过 \(review.approveVotes) · 驳回 \(review.rejectVotes)").font(.caption2).foregroundStyle(.secondary)
                                if review.category == "active" { HStack { Button("投通过") { Task { await vote(review.id, "approve") } }.tint(.green); Button("投驳回", role: .destructive) { Task { await vote(review.id, "reject") } }; Button("弃权") { Task { await vote(review.id, "abstain") } } }.font(.caption) }
                                if review.status == "open" { Button("取消仲裁", role: .destructive) { cancelling = review }.font(.caption) }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            } else if !isLoading && errorMessage == nil { EmptyStateView("暂无仲裁记录", systemImage: "checkmark.seal").listRowBackground(Color.clear) }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .task(id: status) { await load() }.refreshable { await load() }
        .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) { JuryReviewCreateView() }
        .confirmationDialog("取消该仲裁？已投票数据会保留但不再结算。", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }), titleVisibility: .visible) { Button("取消仲裁", role: .destructive) { if let id = cancelling?.id { Task { await cancel(id) } } }; Button("返回", role: .cancel) { cancelling = nil } }
    }
    @MainActor private func load() async { isLoading = true; errorMessage = nil; do { let response: JuryReviewsResponse = try await APIClient.shared.get("api/admin/jury/reviews", query: [URLQueryItem(name: "status", value: status)]); items = response.items } catch { errorMessage = error.localizedDescription }; isLoading = false }
    @MainActor private func vote(_ id: Int, _ vote: String) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/jury/\(id)/vote", body: JuryVoteBody(vote: vote, comment: nil)); await load() } catch { errorMessage = error.localizedDescription } }
    @MainActor private func cancel(_ id: Int) async { do { let _: AdminActionResponse = try await APIClient.shared.send("api/admin/jury/reviews/\(id)/cancel", method: "POST"); cancelling = nil; await load() } catch { errorMessage = error.localizedDescription } }
}

private struct JuryReviewCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photoID = ""; @State private var reason = ""; @State private var phases = [JuryPhaseDraft(scope: "jury", end: Date().addingTimeInterval(86400))]; @State private var busy = false; @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("图片") {
                    TextField("图片 ID", text: $photoID).keyboardType(.numberPad)
                    TextField("仲裁理由", text: $reason, axis: .vertical).lineLimit(3...7)
                }
                Section("投票阶段（依次执行）") {
                    ForEach($phases) { $phase in
                        VStack(alignment: .leading) {
                            Picker("范围", selection: $phase.scope) {
                                Text("评审团").tag("jury")
                                Text("评审团 + 用户").tag("jury_users")
                                Text("全体用户").tag("users")
                            }
                            DatePicker("截止", selection: $phase.end, displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                    .onDelete {
                        guard phases.count - $0.count >= 1 else { return }
                        phases.remove(atOffsets: $0)
                    }
                    Button("添加阶段", systemImage: "plus") {
                        phases.append(JuryPhaseDraft(scope: "users", end: (phases.last?.end ?? Date()).addingTimeInterval(86400)))
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("发起评审仲裁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("发起") { Task { await save() } }.disabled(Int(photoID) == nil || phases.isEmpty || busy) }
            }
        }
    }
    @MainActor private func save() async { guard let id = Int(photoID) else { return }; busy = true; defer { busy = false }; do { let body = JuryReviewCreateBody(photo_id: id, reason: reason.isEmpty ? nil : reason, phases: phases.map { JuryPhaseBody(scope: $0.scope, ends_at: ISO8601DateFormatter().string(from: $0.end)) }); let _: AdminActionResponse = try await APIClient.shared.send("api/admin/jury/reviews", body: body); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct JuryStatusBadge: View { let status: String; var body: some View { Text(status == "active" ? "在任" : status == "suspended" ? "暂停" : "停用").font(.caption2.weight(.semibold)).foregroundStyle(status == "active" ? .green : status == "suspended" ? .orange : .secondary) } }
private struct JuryApplicationBadge: View { let status: String; var body: some View { Text(status == "pending" ? "待审核" : status == "approved" ? "已通过" : "已驳回").font(.caption2.weight(.semibold)).foregroundStyle(status == "pending" ? .orange : status == "approved" ? .green : .red) } }
private struct JuryReviewBadge: View { let review: JuryReview; var body: some View { Text(review.category == "active" ? "进行中" : review.category == "upcoming" ? "待开始" : review.status == "cancelled" ? "已取消" : "已结束").font(.caption2.weight(.semibold)).foregroundStyle(review.category == "active" ? .green : review.category == "upcoming" ? .blue : .secondary) } }
private struct JuryPager: View { @Binding var offset: Int; let limit: Int; let total: Int; var body: some View { if total > limit { Section { HStack { Button("上一页") { offset = max(0, offset-limit) }.disabled(offset == 0); Spacer(); Text("\(offset/limit+1) / \(max(1, Int(ceil(Double(total)/Double(limit)))))"); Spacer(); Button("下一页") { offset += limit }.disabled(offset+limit >= total) } } } } }

private enum JuryAdminMode: Hashable { case members, applications, reviews }
private struct JuryMembersResponse: Codable, Sendable { let items: [JuryMember]; let total: Int }
private struct JuryMember: Codable, Identifiable, Sendable { let id: Int; let userId: Int; let displayName: String; let avatar: String?; let role: String; let status: String; let votesCount: Int; let expiresAt: String?; let appointedAt: String?; let appointer: String? }
private struct JuryStatusBody: Encodable, Sendable { let status: String }
private struct JuryAppointBody: Encodable, Sendable { let user_id: Int; let expires_at: String? }
private struct JuryLookupResponse: Codable, Sendable { let items: [JuryLookupUser] }
private struct JuryLookupUser: Codable, Identifiable, Sendable { let id: Int; let username: String; let displayName: String; let email: String?; let avatar: String?; let role: String }
private struct JuryApplicationsResponse: Codable, Sendable { let items: [JuryApplication] }
private struct JuryApplication: Codable, Identifiable, Sendable { let id: Int; let userId: Int; let displayName: String; let username: String; let avatar: String?; let statement: String?; let status: String; let note: String?; let createdAt: String?; let stats: JuryApplicantStats }
private struct JuryApplicantStats: Codable, Sendable { let days: Int; let approved: Int; let rate: Int }
private struct JuryApplicationDecisionState: Identifiable { let id = UUID(); let application: JuryApplication; let decision: String }
private struct JuryResolveBody: Encodable, Sendable { let decision: String; let note: String? }
private struct JuryRequirements: Codable, Sendable { var applyOpen: Bool; var days: JuryRequirementValue; var approved: JuryRequirementValue; var rate: JuryRequirementValue }
private struct JuryRequirementValue: Codable, Sendable { var enabled: Bool; var value: Int }
private struct JuryRequirementsBody: Encodable, Sendable { let apply_open: Bool; let days_on: Bool; let days: Int; let approved_on: Bool; let approved: Int; let rate_on: Bool; let rate: Int }
private struct JuryReviewsResponse: Codable, Sendable { let items: [JuryReview] }
private struct JuryReview: Codable, Identifiable, Sendable { let id: Int; let photoId: Int; let reason: String?; let status: String; let category: String; let scope: String; let scopeLabel: String; let phaseSeq: Int?; let phaseTotal: Int; let phaseEndsAt: String?; let approveVotes: Int; let rejectVotes: Int; let result: String; let createdAt: String?; let initiator: String?; let title: String?; let thumb: String?; let href: String? }
private struct JuryVoteBody: Encodable, Sendable { let vote: String; let comment: String? }
private struct JuryPhaseDraft: Identifiable { let id = UUID(); var scope: String; var end: Date }
private struct JuryPhaseBody: Encodable, Sendable { let scope: String; let ends_at: String }
private struct JuryReviewCreateBody: Encodable, Sendable { let photo_id: Int; let reason: String?; let phases: [JuryPhaseBody] }
