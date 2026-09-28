import SwiftUI

struct AdminReviewView: View {
    let identity: AdminIdentity

    @State private var phase = "all"
    @State private var domain = "all"
    @State private var kind = "all"
    @State private var sort = "old"
    @State private var response: AdminReviewQueueResponse?
    @State private var reasons: [AdminRejectionReason] = []
    @State private var selected: AdminReviewQueueItem?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("筛选") {
                Picker("阶段", selection: $phase) {
                    Text("全部阶段").tag("all")
                    Text("待初审").tag("fresh")
                    Text("待复核").tag("second")
                    Text("冲突仲裁").tag("conflict")
                }
                Picker("领域", selection: $domain) {
                    Text("全部领域").tag("all")
                    Text("航空").tag("aviation")
                    Text("铁路").tag("railway")
                    Text("模拟飞行").tag("flight_sim")
                }
                Picker("队列", selection: $kind) {
                    Text("全部队列").tag("all")
                    Text("Hot").tag("hot")
                    Text("优先").tag("priority")
                    Text("普通").tag("normal")
                }
                Picker("排序", selection: $sort) {
                    Text("最早优先").tag("old")
                    Text("最新优先").tag("new")
                }
            }

            if let response {
                Section("待处理 \(response.total) 张") {
                    ForEach(response.items) { item in
                        Button {
                            if item.lock == nil || item.lock?.byMe == true { selected = item }
                        } label: {
                            AdminReviewQueueRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .disabled(item.lock != nil && item.lock?.byMe != true)
                    }
                }
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let errorMessage {
                EmptyStateView("审核队列加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else if response?.items.isEmpty == true {
                EmptyStateView("当前筛选没有待审作品", systemImage: "checkmark.circle")
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("审核中心")
        .task(id: "\(phase)|\(domain)|\(kind)|\(sort)") { await load() }
        .refreshable { await load() }
        .sheet(item: $selected, onDismiss: { Task { await load() } }) { item in
            NavigationStack {
                AdminReviewDetailView(identity: identity, item: item, reasons: reasons)
            }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            var query = [
                URLQueryItem(name: "status", value: "pending"),
                URLQueryItem(name: "phase", value: phase),
                URLQueryItem(name: "kind", value: kind),
                URLQueryItem(name: "sort", value: sort),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "offset", value: "0"),
            ]
            if domain != "all" { query.append(URLQueryItem(name: "domain", value: domain)) }
            let requestQuery = query
            async let queue: AdminReviewQueueResponse = APIClient.shared.get("api/admin/review/queue", query: requestQuery)
            async let presets: AdminRejectionReasonsResponse = APIClient.shared.get(
                "api/admin/review/rejection-reasons",
                query: [URLQueryItem(name: "scope", value: "first")]
            )
            response = try await queue
            let presetResponse = try? await presets
            reasons = presetResponse?.items ?? []
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct AdminReviewQueueRow: View {
    let item: AdminReviewQueueItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                RemoteImage(urlString: item.thumb)
                    .frame(width: 96, height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 3) {
                    if item.hot { badge("Hot", color: .orange) }
                    else if item.priority { badge("优先", color: .blue) }
                    if item.conflict { badge("冲突", color: .red) }
                }
                .padding(4)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title.isEmpty ? "（无标题）" : item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(domainName(item.domain)) · \(item.uploader.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if item.dupHit {
                        Label("疑似重复", systemImage: "doc.on.doc.fill")
                            .foregroundStyle(.red)
                    }
                    if let pass = item.firstPass {
                        Label(firstPassLabel(pass.decision), systemImage: "person.badge.clock.fill")
                            .foregroundStyle(.purple)
                    }
                }
                .font(.caption2)
                if let lock = item.lock {
                    Label(lock.byMe ? "你正在审核" : "\(lock.byName ?? "他人") 已锁定", systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(lock.byMe ? AppTheme.accent : .red)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .foregroundStyle(.white).background(color, in: Capsule())
    }

    private func firstPassLabel(_ decision: String) -> String {
        switch decision { case "approve": "初审建议通过"; case "reject": "初审建议驳回"; case "escalate": "已转交"; default: "已初审" }
    }
}

private struct AdminReviewDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let identity: AdminIdentity
    let item: AdminReviewQueueItem
    let reasons: [AdminRejectionReason]

    @State private var detail: AdminReviewDetail?
    @State private var note = ""
    @State private var rejectText = ""
    @State private var selectedReasonIDs: Set<Int> = []
    @State private var annotations: [AdminReviewAnnotation] = []
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var claimed = false
    @State private var resolved = false
    @State private var errorMessage: String?
    @State private var confirmation: Action?
    @State private var showingInspector = false
    @State private var showingAnnotationEditor = false

    private enum Action: String, Identifiable {
        case approve, reject, escalate, delete
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let detail {
                Form {
                    Section {
                        Button { showingInspector = true } label: {
                            RemoteImage(urlString: detail.image, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(alignment: .bottomTrailing) {
                                    Label("放大检查", systemImage: "plus.magnifyingglass")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 9).padding(.vertical, 6)
                                        .background(.black.opacity(0.64), in: Capsule())
                                        .padding(9)
                                }
                        }
                        .buttonStyle(.plain)
                        Text(detail.title).font(.headline)
                        if let description = detail.description, !description.isEmpty {
                            Text(description).foregroundStyle(.secondary)
                        }
                        LabeledContent("领域", value: domainName(detail.domain))
                        if let type = detail.photoType { LabeledContent("上传类型", value: type) }
                        if let category = detail.category { LabeledContent("分类", value: category) }
                    }

                    Section("上传者") {
                        LabeledContent("用户", value: "\(detail.uploader.displayName) (@\(detail.uploader.username))")
                        LabeledContent("总作品", value: String(detail.uploader.stats.total))
                        LabeledContent("通过 / 驳回", value: "\(detail.uploader.stats.approved) / \(detail.uploader.stats.rejected)")
                        if detail.uploader.banned { Label("该用户已被封禁", systemImage: "person.crop.circle.badge.xmark").foregroundStyle(.red) }
                    }

                    Section("风险与阶段") {
                        Label(detail.hashed ? "已完成重复性比对" : "尚未生成图片哈希", systemImage: detail.hashed ? "checkmark.shield" : "questionmark.diamond")
                        if item.dupHit { Label("命中疑似重复作品", systemImage: "doc.on.doc.fill").foregroundStyle(.red) }
                        if detail.inConflict { Label("二审冲突，需仲裁权限", systemImage: "exclamationmark.arrow.triangle.2.circlepath").foregroundStyle(.red) }
                        if let first = detail.firstPass {
                            LabeledContent("初审", value: "\(first.reviewer ?? "审核员") · \(first.decision)")
                        }
                    }

                    if !detail.history.isEmpty {
                        Section("审核历史") {
                            ForEach(detail.history) { record in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(record.reviewer ?? "系统") · \(decisionLabel(record.decision))")
                                        .font(.subheadline.weight(.semibold))
                                    Text(record.stage).font(.caption).foregroundStyle(.secondary)
                                    if let value = record.reason ?? record.note { Text(value).font(.caption) }
                                }
                            }
                        }
                    }

                    if claimed {
                        Section("给上传者的留言") {
                            TextEditor(text: $note).frame(minHeight: 70)
                        }

                        Section("裁决") {
                            if detail.canFirstPass || detail.canFinalize || detail.canResolveConflict {
                                Button("通过", systemImage: "checkmark.circle.fill") { confirmation = .approve }
                                    .foregroundStyle(.green)
                                Button("驳回", systemImage: "xmark.circle.fill", role: .destructive) { confirmation = .reject }
                            }
                            if detail.canEscalate {
                                Button("转交复核", systemImage: "arrowshape.turn.up.right.fill") { confirmation = .escalate }
                            }
                            if detail.canDelete {
                                Button("删除作品", systemImage: "trash.fill", role: .destructive) { confirmation = .delete }
                            }
                        }
                    } else if identity.can("review.first") {
                        Section {
                            Button("获取审核锁", systemImage: "lock.fill") { Task { await claim() } }
                                .disabled(isBusy)
                        }
                    }

                    Section {
                        Button("打开原生检查工具", systemImage: "viewfinder") { showingInspector = true }
                    } footer: {
                        Text("支持鉴权原图、双指缩放、单独全屏查看、水平与居中辅助、放大镜、直方图和灰尘增强。")
                    }

                    if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                }
            } else if isLoading {
                ProgressView("正在加载审核详情…")
            } else {
                EmptyStateView("审核详情加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }
                }
            }
        }
        .navigationTitle("审核 #\(item.id)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            if claimed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("释放") { Task { await releaseAndDismiss() } }
                        .disabled(isBusy)
                }
            }
        }
        .task { await load() }
        .task(id: claimed) {
            guard claimed else { return }
            await keepLockAlive()
        }
        .onDisappear {
            if claimed && !resolved { Task { await release() } }
        }
        .sheet(item: $confirmation) { action in
            NavigationStack {
                actionForm(action)
            }
        }
        .fullScreenCover(isPresented: $showingInspector) {
            if let detail {
                AdminPhotoInspectionView(detail: detail)
            }
        }
    }

    @ViewBuilder private func actionForm(_ action: Action) -> some View {
        Form {
            if action == .reject {
                Section("预设驳回理由") {
                    ForEach(reasons) { reason in
                        Button { toggleReason(reason) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(reason.title)
                                    if reason.requiresAnnotation == true {
                                        Text("需要图片标注").font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                Image(systemName: selectedReasonIDs.contains(reason.id) ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                }
                Section("驳回说明") { TextEditor(text: $rejectText).frame(minHeight: 100) }
                if selectedReasonsNeedAnnotation {
                    Section {
                        Button {
                            showingAnnotationEditor = true
                        } label: {
                            Label(
                                missingRequiredAnnotationIDs.isEmpty ? "编辑图片标注（\(annotations.count)）" : "标注问题位置",
                                systemImage: "pencil.tip.crop.circle.badge.plus"
                            )
                        }
                        if !missingRequiredAnnotationIDs.isEmpty {
                            Text("以下理由仍缺少标注：\(missingRequiredReasonTitles.joined(separator: "、"))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } else {
                Section {
                    Text(actionMessage(action))
                }
            }
        }
        .navigationTitle(actionTitle(action))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { confirmation = nil } }
            ToolbarItem(placement: .confirmationAction) {
                Button("确认", role: action == .delete ? .destructive : nil) { Task { await perform(action) } }
                    .disabled(isBusy || (action == .reject && (rejectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !missingRequiredAnnotationIDs.isEmpty)))
            }
        }
        .fullScreenCover(isPresented: $showingAnnotationEditor) {
            if let detail {
                AdminReviewAnnotationEditor(
                    detail: detail,
                    reasons: selectedReasons,
                    annotations: $annotations
                )
            }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        do {
            let loaded: AdminReviewDetail = try await APIClient.shared.get("api/admin/review/photos/\(item.id)")
            detail = loaded
            annotations = loaded.reviewAnnotations ?? []
            errorMessage = nil
            if identity.can("review.first") { await claim() }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func claim() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let _: AdminActionResponse = try await APIClient.shared.send("api/admin/review/photos/\(item.id)/claim", method: "POST")
            claimed = true
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func perform(_ action: Action) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let result: AdminActionResponse
            switch action {
            case .approve:
                result = try await APIClient.shared.send(
                    "api/admin/review/photos/\(item.id)/approve",
                    body: AdminReviewNoteBody(note: cleaned(note))
                )
            case .reject:
                let ids = Array(selectedReasonIDs).sorted()
                result = try await APIClient.shared.send(
                    "api/admin/review/photos/\(item.id)/reject",
                    body: AdminReviewRejectBody(
                        rejectionReasonId: ids.count == 1 ? ids[0] : nil,
                        rejectionReasonIds: ids,
                        reason: cleaned(rejectText),
                        note: cleaned(note),
                        annotations: annotations
                    )
                )
            case .escalate:
                result = try await APIClient.shared.send(
                    "api/admin/review/photos/\(item.id)/escalate",
                    body: AdminReviewNoteBody(note: cleaned(note))
                )
            case .delete:
                result = try await APIClient.shared.send("api/admin/review/photos/\(item.id)/delete", method: "POST")
            }
            _ = result
            resolved = true
            claimed = false
            confirmation = nil
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func releaseAndDismiss() async {
        await release()
        claimed = false
        dismiss()
    }

    /// A review can legitimately take longer than the 100-second server lock,
    /// especially when checking the original image. Renew before expiry just as
    /// the website reviewer does; cancellation stops renewal when the sheet exits.
    @MainActor private func keepLockAlive() async {
        while claimed && !resolved && !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 55_000_000_000)
            } catch { return }
            guard claimed && !resolved && !Task.isCancelled else { return }
            do {
                let _: AdminActionResponse = try await APIClient.shared.send("api/admin/review/photos/\(item.id)/claim", method: "POST")
            } catch {
                claimed = false
                errorMessage = error.localizedDescription
                return
            }
        }
    }

    private func release() async {
        let _: AdminActionResponse? = try? await APIClient.shared.send("api/admin/review/photos/\(item.id)/release", method: "POST")
    }

    private var selectedReasonsNeedAnnotation: Bool {
        reasons.contains { selectedReasonIDs.contains($0.id) && $0.requiresAnnotation == true }
    }

    private var selectedReasons: [AdminRejectionReason] {
        reasons.filter { selectedReasonIDs.contains($0.id) }
    }

    private var missingRequiredAnnotationIDs: Set<Int> {
        let required = Set(selectedReasons.filter { $0.requiresAnnotation == true }.map(\.id))
        let annotated = Set(annotations.compactMap(\.reasonId))
        return required.subtracting(annotated)
    }

    private var missingRequiredReasonTitles: [String] {
        reasons.filter { missingRequiredAnnotationIDs.contains($0.id) }.map(\.title)
    }

    private func toggleReason(_ reason: AdminRejectionReason) {
        let block = reason.title + (reason.content.map { "：\($0)" } ?? "")
        if selectedReasonIDs.contains(reason.id) {
            selectedReasonIDs.remove(reason.id)
            annotations.removeAll { $0.reasonId == reason.id }
            rejectText = rejectText.split(separator: "\n").map(String.init).filter { $0 != block }.joined(separator: "\n")
        } else {
            selectedReasonIDs.insert(reason.id)
            rejectText = [rejectText, block].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    private func cleaned(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func actionTitle(_ action: Action) -> String {
        switch action { case .approve: "通过作品"; case .reject: "驳回作品"; case .escalate: "转交复核"; case .delete: "删除作品" }
    }

    private func actionMessage(_ action: Action) -> String {
        switch action {
        case .approve: "确认通过这张作品？最终审核会立即发布；初审则提交通过建议。"
        case .escalate: "确认将这张作品转交给更高级别审核员复核？"
        case .delete: "此操作会删除作品及相关文件，无法在 App 内撤销。"
        case .reject: ""
        }
    }

    private func decisionLabel(_ value: String) -> String {
        switch value { case "approve": "通过"; case "reject": "驳回"; case "escalate": "转交"; default: value }
    }
}
