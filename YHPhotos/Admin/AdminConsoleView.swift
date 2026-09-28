import SwiftUI

/// Native administration launcher. Its sections, routes and visibility rules
/// intentionally mirror the website console one-for-one.
struct AdminConsoleView: View {
    @Environment(\.dismiss) private var dismiss

    let identity: AdminIdentity

    @State private var query = ""
    @State private var path = NavigationPath()
    @State private var showingPermissions = false

    private var allowedModules: [AdminModule] {
        AdminModule.allCases.filter { module in
            module.isAllowed(for: identity)
                && (query.isEmpty || module.title.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                identityHeader

                ForEach(AdminSection.allCases) { section in
                    let modules = allowedModules.filter { $0.section == section }
                    if !modules.isEmpty {
                        Section(section.rawValue) {
                            ForEach(modules) { module in
                                NavigationLink(value: module) {
                                    AdminModuleRow(module: module)
                                }
                            }
                        }
                    }
                }

                if allowedModules.isEmpty {
                    EmptyStateView(
                        "未找到后台功能",
                        systemImage: "magnifyingglass",
                        description: "请尝试其他关键词"
                    )
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "搜索后台功能")
            .navigationTitle("管理后台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingPermissions = true } label: {
                        Image(systemName: "person.badge.key.fill")
                    }
                    .accessibilityLabel("查看当前权限")
                }
            }
            .sheet(isPresented: $showingPermissions) {
                AdminPermissionSummaryView(identity: identity)
            }
            .navigationDestination(for: AdminModule.self) { module in
                switch module {
                case .dashboard:
                    AdminDashboardView(identity: identity) { path.append($0) }
                case .reviewCenter:
                    AdminReviewView(identity: identity)
                case .appeals:
                    AdminAppealsView(identity: identity)
                case .rejectionReasons:
                    AdminRejectionReasonsView()
                case .reports:
                    AdminReportsView(identity: identity)
                case .users:
                    AdminUsersView()
                case .content:
                    AdminContentView(identity: identity)
                case .bounties:
                    AdminBountiesView()
                case .revisions:
                    AdminRevisionsView()
                case .featured:
                    AdminFeaturedView()
                case .groups:
                    AdminGroupsView(identity: identity)
                case .groupPolicy:
                    AdminGroupPolicyView()
                case .priority:
                    AdminPriorityView()
                case .tickets:
                    AdminTicketsView(identity: identity)
                case .feedback:
                    AdminFeedbackView()
                case .requests:
                    AdminRequestsView(identity: identity)
                case .forecast:
                    AdminForecastView(identity: identity)
                case .reference:
                    AdminReferenceView(identity: identity)
                case .photoTypes:
                    AdminPhotoTypesView()
                case .ruleDocuments:
                    AdminRuleDocumentsView()
                case .announcements:
                    AdminAnnouncementsView()
                case .news:
                    AdminNewsView()
                case .ranking:
                    AdminRankingView()
                case .badges:
                    AdminBadgesView()
                case .jury:
                    AdminJuryView()
                case .rbac:
                    AdminRBACView()
                case .audit:
                    AdminAuditView()
                case .quota:
                    AdminQuotaView()
                case .settings:
                    AdminSettingsView(identity: identity)
                case .team:
                    AdminTeamView()
                case .risk:
                    AdminRiskView(identity: identity)
                case .faultInjection:
                    AdminFaultInjectionView()
                case .priorityGrant:
                    AdminPriorityGrantView()
                case .juryScheduler:
                    AdminJurySchedulerView()
                case .badgeEngine:
                    AdminBadgeEngineView()
                }
            }
        }
        .appScreenBackground()
    }

    private var identityHeader: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(urlString: identity.avatar, name: identity.displayName, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(identity.displayName).font(.headline)
                    Text(identity.roleLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("可访问 \(AdminModule.allCases.filter { $0.isAllowed(for: identity) }.count) / \(AdminModule.allCases.count) 个后台模块")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.vertical, 6)
        } footer: {
            Text("功能入口按服务端有效权限展示；所有读取与操作仍由服务端逐次鉴权。")
        }
    }
}

private struct AdminModuleRow: View {
    let module: AdminModule

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: module.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 30, height: 30)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            Text(module.title)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct AdminPermissionSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    let identity: AdminIdentity

    var body: some View {
        NavigationStack {
            List {
                Section("身份") {
                    LabeledContent("账号", value: identity.username)
                    LabeledContent("显示名称", value: identity.displayName)
                    LabeledContent("角色", value: identity.roleLabel)
                    LabeledContent("权限等级", value: String(identity.level))
                }

                Section("服务端有效权限（\(identity.permissions.count)）") {
                    if identity.role == "admin" {
                        Label("超级管理员：拥有全部权限", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(identity.permissions.sorted(), id: \.self) { permission in
                        Text(permission).font(.system(.footnote, design: .monospaced))
                    }
                }
            }
            .navigationTitle("当前权限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
