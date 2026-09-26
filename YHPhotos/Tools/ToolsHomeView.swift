import SwiftUI

private enum ToolDestination: Hashable {
    case imageInspector
    case forecast
    case missions
    case bounties
    case scene
    case wiki
    case map
    case ranking
    case activities
}

struct ToolsHomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    intro
                    toolSection(L10n.string("图片工具"), icon: "viewfinder") {
                        link(.imageInspector, title: L10n.string("图片检查工具"), subtitle: L10n.string("居中、水平、直方图与灰尘增强"), icon: "viewfinder")
                    }
                    toolSection(L10n.string("航空情报"), icon: "airplane.departure") {
                        link(.forecast, title: L10n.string("好货预报"), subtitle: L10n.string("按机场与日期筛稀有机型、少见航司、彩绘与换机"), icon: "bolt.fill")
                        link(.missions, title: L10n.string("拍摄任务"), subtitle: L10n.string("机队缺口、机场补拍建议与追踪清单"), icon: "target")
                        link(.bounties, title: L10n.string("缺口悬赏"), subtitle: L10n.string("发布征集、补全历史涂装和机场时期影像"), icon: "gift.fill")
                        link(.scene, title: L10n.string("历史场景"), subtitle: L10n.string("按机场和日期重建场景与多机位照片"), icon: "calendar")
                    }
                    toolSection(L10n.string("资料工具"), icon: "books.vertical.fill") {
                        link(.wiki, title: L10n.string("百科"), subtitle: L10n.string("航司、机场、机型与注册号资料库"), icon: "book.fill")
                        link(.map, title: L10n.string("地图"), subtitle: L10n.string("按机场地理位置浏览作品"), icon: "map.fill")
                    }
                    toolSection(L10n.string("社区"), icon: "person.3.fill") {
                        link(.ranking, title: L10n.string("排行榜"), subtitle: L10n.string("过图贡献、热门作品与赛事榜单"), icon: "trophy.fill")
                        link(.activities, title: L10n.string("活动与领奖"), subtitle: L10n.string("征图活动、参赛与领奖入口"), icon: "flag.fill")
                    }
                }
                .padding(18)
            }
            .navigationTitle(L10n.string("工具"))
            .navigationDestination(for: ToolDestination.self) { destination in
                switch destination {
                case .imageInspector: ImageInspectorLauncherView()
                case .forecast: ForecastView()
                case .missions: MissionsView()
                case .bounties: BountiesView()
                case .scene: SceneView()
                case .wiki: WikiHomeView()
                case .map: MapBrowserView()
                case .ranking: RankingHomeView()
                case .activities: ActivitiesHomeView()
                }
            }
            .appScreenBackground()
        }
    }

    private var intro: some View {
        GlassPanel(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title)
                    .foregroundStyle(AppTheme.accent)
                Text(L10n.string("选择一个工具")).font(.title3.bold())
                Text(L10n.string("图片检查、航空情报、百科资料与社区活动都集中在这里。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [AppTheme.accent.opacity(0.22), Color.cyan.opacity(0.08), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .padding(.top, 4)
    }

    private func toolSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                content()
            }
            .padding(.bottom, 8)
        }
    }

    private func link(
        _ destination: ToolDestination,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
