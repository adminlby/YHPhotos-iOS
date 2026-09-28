import SwiftUI
import Charts

struct AdminDashboardResponse: Decodable, Sendable {
    struct Queues: Decodable, Sendable {
        let pendingPhotos: Int
        let appealingPhotos: Int
        let appeals: Int
        let photoReports: Int
        let userReports: Int
        let openTickets: Int
        let feedback: Int
        let corrections: Int
        let licenseRequests: Int
        let commentsPending: Int
    }
    struct Today: Decodable, Sendable {
        let newUsers: Int
        let newPhotos: Int
        let approved: Int
        let rejected: Int
    }
    struct Totals: Decodable, Sendable {
        let users: Int
        let bannedUsers: Int
        let photos: Int
        let groups: Int
    }
    struct Moderator: Decodable, Identifiable, Sendable {
        let id: Int
        let displayName: String
        let avatar: String?
        let role: String
        let roleLabel: String
        let lastActive: String?
    }

    let queues: Queues
    let today: Today
    let totals: Totals
    let onlineModerators: [Moderator]
}

struct AdminDashboardTrendsResponse: Decodable, Sendable {
    struct Point: Decodable, Identifiable, Sendable {
        let date: String
        let newPhotos: Int
        let newUsers: Int
        let approved: Int
        let rejected: Int
        var id: String { date }
    }
    let days: Int
    let series: [Point]
}

struct AdminDashboardView: View {
    let identity: AdminIdentity
    let openModule: (AdminModule) -> Void

    @State private var dashboard: AdminDashboardResponse?
    @State private var trends: AdminDashboardTrendsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(identity.displayName)，欢迎回来")
                        .font(.title2.bold())
                    Text("这里汇总需要处理的事项与社区动态。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let dashboard {
                    queueSection(dashboard.queues)
                    todaySection(dashboard.today)
                    if let trends { trendSection(trends) }
                    totalsSection(dashboard.totals)
                    moderatorsSection(dashboard.onlineModerators)
                }

                LoadingOrErrorView(isLoading: isLoading, error: errorMessage) {
                    Task { await load() }
                }
            }
            .padding(16)
        }
        .navigationTitle("仪表盘")
        .refreshable { await load() }
        .task { await load() }
        .appScreenBackground()
    }

    @ViewBuilder private func queueSection(_ queues: AdminDashboardResponse.Queues) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("待处理").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink { AdminReviewView(identity: identity) } label: {
                    queueCard("待审图片", value: queues.pendingPhotos, icon: "hourglass", color: .orange)
                }
                .buttonStyle(.plain)
                NavigationLink { AdminAppealsView(identity: identity) } label: {
                    queueCard("待处理申诉", value: queues.appeals, icon: "scale.3d", color: .purple)
                }
                .buttonStyle(.plain)
                moduleButton(.reports) {
                    queueCard("举报", value: queues.photoReports + queues.userReports, icon: "flag.fill", color: .red)
                }
                moduleButton(.content) {
                    queueCard("待审评论", value: queues.commentsPending, icon: "bubble.left.and.exclamationmark.bubble.right.fill", color: .orange)
                }
                moduleButton(.tickets) {
                    queueCard("未结工单", value: queues.openTickets, icon: "lifepreserver.fill", color: .blue)
                }
                moduleButton(.feedback) {
                    queueCard("新反馈", value: queues.feedback, icon: "bubble.left.and.bubble.right.fill", color: .cyan)
                }
                moduleButton(.requests) {
                    queueCard("信息纠错", value: queues.corrections, icon: "pencil.and.list.clipboard", color: .indigo)
                }
                moduleButton(.requests) {
                    queueCard("授权申请", value: queues.licenseRequests, icon: "checkmark.seal.fill", color: .green)
                }
            }
        }
    }

    private func moduleButton<Content: View>(_ module: AdminModule, @ViewBuilder content: () -> Content) -> some View {
        Button { openModule(module) } label: { content() }
            .buttonStyle(.plain)
    }

    private func queueCard(_ title: String, value: Int, icon: String, color: Color) -> some View {
        GlassPanel(cornerRadius: 17) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(value.formatted()).font(.title2.bold().monospacedDigit())
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
        }
        .opacity(value == 0 ? 0.68 : 1)
    }

    private func todaySection(_ today: AdminDashboardResponse.Today) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日").font(.headline)
            GlassPanel(cornerRadius: 18) {
                LazyVGrid(columns: columns, spacing: 0) {
                    metric("新增用户", today.newUsers, color: .blue)
                    metric("新增作品", today.newPhotos, color: .cyan)
                    metric("审核通过", today.approved, color: .green)
                    metric("审核驳回", today.rejected, color: .red)
                }
                .padding(8)
            }
        }
    }

    private func trendSection(_ trends: AdminDashboardTrendsResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("近 \(trends.days) 天趋势").font(.headline)
            GlassPanel(cornerRadius: 18) {
                Chart {
                    ForEach(trends.series) { point in
                        AreaMark(
                            x: .value("日期", point.date),
                            y: .value("新增图片", point.newPhotos)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [Color.cyan.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                        )
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("新增图片", point.newPhotos)
                        )
                        .foregroundStyle(Color.cyan)
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("审核通过", point.approved)
                        )
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartLegend(.hidden)
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 220)
                .padding(14)
            }
            HStack(spacing: 16) {
                Label("新增图片", systemImage: "circle.fill").foregroundStyle(.cyan)
                Label("审核通过", systemImage: "line.diagonal").foregroundStyle(.green)
            }
            .font(.caption)
        }
    }

    private func totalsSection(_ totals: AdminDashboardResponse.Totals) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("社区总览").font(.headline)
            GlassPanel(cornerRadius: 18) {
                LazyVGrid(columns: columns, spacing: 0) {
                    metric("用户", totals.users, color: .primary)
                    metric("已发布作品", totals.photos, color: .primary)
                    metric("小组", totals.groups, color: .primary)
                    metric("封禁用户", totals.bannedUsers, color: .red)
                }
                .padding(8)
            }
        }
    }

    private func moderatorsSection(_ moderators: [AdminDashboardResponse.Moderator]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("在线审核员", systemImage: "checkmark.shield.fill").font(.headline)
                Spacer()
                Text("\(moderators.count)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }
            GlassPanel(cornerRadius: 18) {
                VStack(spacing: 0) {
                    if moderators.isEmpty {
                        Text("当前没有在线审核员")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    } else {
                        ForEach(Array(moderators.enumerated()), id: \.element.id) { index, moderator in
                            HStack(spacing: 11) {
                                AvatarView(urlString: moderator.avatar, name: moderator.displayName, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(moderator.displayName).font(.subheadline.weight(.semibold))
                                    Text(moderator.roleLabel).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Circle().fill(.green).frame(width: 7, height: 7)
                            }
                            .padding(13)
                            if index < moderators.count - 1 { Divider().padding(.leading, 62) }
                        }
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.formatted()).font(.title2.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @MainActor private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let dashboardRequest: AdminDashboardResponse = APIClient.shared.get("api/admin/dashboard")
            async let trendsRequest: AdminDashboardTrendsResponse = APIClient.shared.get(
                "api/admin/dashboard/trends",
                query: [URLQueryItem(name: "days", value: "14")]
            )
            dashboard = try await dashboardRequest
            trends = try await trendsRequest
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}
