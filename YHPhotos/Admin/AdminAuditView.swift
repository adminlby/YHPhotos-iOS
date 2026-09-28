import SwiftUI

struct AdminAuditView: View {
    @State private var response: AdminAuditResponse?
    @State private var query = ""
    @State private var action = ""
    @State private var targetType = ""
    @State private var adminID = ""
    @State private var offset = 0
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let limit = 40
    private var page: Int { offset / limit + 1 }
    private var pages: Int { max(1, Int(ceil(Double(response?.total ?? 0) / Double(limit)))) }

    var body: some View {
        List {
            if response?.scope == "own" {
                Section { Label("当前权限只能查看你自己的后台操作。", systemImage: "person.crop.circle.badge.checkmark").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("筛选") {
                TextField("动作关键词", text: $action).textInputAutocapitalization(.never).font(.system(.body, design: .monospaced))
                TextField("对象类型（精确匹配）", text: $targetType).textInputAutocapitalization(.never)
                if response?.scope != "own" { TextField("操作人用户 ID", text: $adminID).keyboardType(.numberPad) }
                if !action.isEmpty || !targetType.isEmpty || !adminID.isEmpty {
                    Button("清除筛选", systemImage: "xmark.circle") { action = ""; targetType = ""; adminID = ""; offset = 0 }
                }
            }
            if let response, !response.items.isEmpty {
                Section("共 \(response.total) 条 · 第 \(page)/\(pages) 页") {
                    ForEach(response.items) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(adminCompositeSystemLabel(log.action)).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
                                Spacer()
                                Text(log.createdAt?.replacingOccurrences(of: "T", with: " ").prefix(19).description ?? "—").font(.caption2).foregroundStyle(.tertiary)
                            }
                            HStack {
                                Label(log.admin ?? "系统", systemImage: "person.fill")
                                if let type = log.targetType { Label("\(adminCompositeSystemLabel(type))\(log.targetId.map { " #\($0)" } ?? "")", systemImage: "scope") }
                            }.font(.caption).foregroundStyle(.secondary)
                            if let description = log.description, !description.isEmpty { Text(description).font(.subheadline).textSelection(.enabled) }
                            if let ip = log.ip, !ip.isEmpty { Text("网络地址  \(ip)").font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled) }
                        }.padding(.vertical, 4)
                    }
                }
                if response.total > limit {
                    Section {
                        HStack {
                            Button("上一页", systemImage: "chevron.left") { offset = max(0, offset - limit) }.disabled(offset == 0)
                            Spacer(); Text("\(page) / \(pages)").foregroundStyle(.secondary); Spacer()
                            Button("下一页") { offset += limit }.disabled(offset + limit >= response.total)
                            Image(systemName: "chevron.right")
                        }
                    }
                }
            } else if !isLoading && errorMessage == nil {
                EmptyStateView("没有日志", systemImage: "clock.arrow.circlepath").listRowBackground(Color.clear)
            }
            if isLoading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            if let errorMessage {
                EmptyStateView("审计日志加载失败", systemImage: "exclamationmark.triangle", description: errorMessage) {
                    Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                }.listRowBackground(Color.clear)
            }
        }
        .navigationTitle("审计日志")
        .searchable(text: $query, prompt: "搜索说明或操作人")
        .task(id: "\(query)|\(action)|\(targetType)|\(adminID)|\(offset)") { await load() }
        .refreshable { await load() }
        .onChange(of: query) { _ in offset = 0 }
        .onChange(of: action) { _ in offset = 0 }
        .onChange(of: targetType) { _ in offset = 0 }
        .onChange(of: adminID) { _ in offset = 0 }
    }

    @MainActor private func load() async {
        isLoading = true; errorMessage = nil
        do {
            var queryItems = [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]
            if !query.isEmpty { queryItems.append(URLQueryItem(name: "q", value: query)) }
            if !action.isEmpty { queryItems.append(URLQueryItem(name: "action", value: action)) }
            if !targetType.isEmpty { queryItems.append(URLQueryItem(name: "target_type", value: targetType)) }
            if let id = Int(adminID) { queryItems.append(URLQueryItem(name: "admin_id", value: String(id))) }
            response = try await APIClient.shared.get("api/admin/audit", query: queryItems)
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

private struct AdminAuditResponse: Codable, Sendable { let items: [AdminAuditLog]; let total: Int; let scope: String }
private struct AdminAuditLog: Codable, Identifiable, Sendable {
    let id: Int; let adminId: Int?; let admin: String?; let action: String; let targetType: String?; let targetId: Int?; let description: String?; let ip: String?; let createdAt: String?
}
