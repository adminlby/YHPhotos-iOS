import SwiftUI

struct UserCenterView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var overview: MeOverview?
    @State private var photos: [MyPhoto] = []
    @State private var status = "all"
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if appModel.sessionUser == nil { signedOut }
                else { signedIn }
            }
            .navigationTitle("我的")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { AppSettingsView() } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .task(id: appModel.sessionUser?.id) { if appModel.sessionUser != nil { await load() } }
            .task(id: status) { if overview != nil { await loadPhotos() } }
            .appScreenBackground()
        }
    }

    private var signedOut: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            ContentUnavailableView {
                Label("登录后管理作品", systemImage: "person.crop.circle.badge.checkmark")
            } description: {
                Text("查看审核进度、获赞数据、收藏与私信。")
            } actions: {
                Button("登录 YHPhotos") { appModel.showingLogin = true }.buttonStyle(.borderedProminent)
            }
            Spacer(minLength: 0)
            SiteLegalFooter(compact: true)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
    }

    private var signedIn: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let overview {
                    header(overview)
                    dashboard(overview)
                    quickActions
                    accountSecurityCard
                    workSection
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage, retry: reload)
                SiteLegalFooter(compact: true)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .refreshable { await load() }
    }

    private func header(_ value: MeOverview) -> some View {
        HStack(spacing: 15) {
            AvatarView(urlString: value.profile.avatar, name: value.profile.displayName, size: 70)
            VStack(alignment: .leading, spacing: 5) {
                Text(value.profile.displayName).font(.title2.bold())
                Text("@\(value.profile.username)").font(.subheadline).foregroundStyle(.secondary)
                Text(value.profile.email).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            NavigationLink { PublicProfileView(userID: value.profile.id) } label: {
                Image(systemName: "arrow.up.right").frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
        .padding(.top, 8)
    }

    private func dashboard(_ value: MeOverview) -> some View {
        GlassPanel(cornerRadius: 24) {
            VStack(spacing: 16) {
                HStack { Text("创作数据").font(.headline); Spacer(); Text("全部作品").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 0) {
                    metric(value.counts.approved, L10n.string("已通过"), .green)
                    metric(value.counts.pending, L10n.string("审核中"), .orange)
                    metric(value.totals.views, L10n.string("浏览"), AppTheme.accent)
                    metric(value.totals.likes, L10n.string("获赞"), .pink)
                }
            }
            .padding(18)
        }
    }

    private var quickActions: some View {
        GlassPanel(cornerRadius: 22) {
            HStack(spacing: 0) {
                quick(.favorites, "bookmark.fill", .purple)
                quick(.collections, "square.stack.3d.up.fill", AppTheme.accent)
                quick(.badges, "medal.fill", .yellow)
                quick(.spotting, "scope", .orange)
            }
            .padding(.vertical, 16)
        }
    }

    private var accountSecurityCard: some View {
        NavigationLink {
            AccountSecurityView()
        } label: {
            GlassPanel(cornerRadius: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(AppTheme.accent.opacity(0.13), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("账号与安全").font(.headline)
                        Text("通过 SSO 修改密码、管理登录方式")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }

    private var workSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("我的作品").font(.title3.bold())
                Spacer()
                Text(L10n.format("%d 项", photos.count)).font(.subheadline).foregroundStyle(.secondary)
            }
            Picker("状态", selection: $status) {
                Text("全部").tag("all")
                Text("审核中").tag("pending")
                Text("已通过").tag("approved")
                Text("未通过").tag("rejected")
            }
            .pickerStyle(.segmented)
            LazyVStack(spacing: 12) {
                ForEach(photos) { photo in
                    NavigationLink { MyPhotoDetailView(photoID: photo.id) } label: {
                        HStack(spacing: 12) {
                            RemoteImage(url: URL(string: photo.thumb ?? photo.image ?? ""))
                                .frame(width: 104, height: 76).clipShape(RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(photo.title).font(.headline).lineLimit(1)
                                Label(statusTitle(photo.status), systemImage: statusIcon(photo.status))
                                    .font(.caption).foregroundStyle(statusColor(photo.status))
                                HStack(spacing: 12) {
                                    Label(photo.views.compactCount, systemImage: "eye")
                                    Label(photo.likes.compactCount, systemImage: "heart")
                                    if photo.hasReviewAnnotations == true { Label(L10n.string("有标注"), systemImage: "pencil.and.outline") }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func metric(_ value: Int, _ title: String, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value.compactCount).font(.headline).foregroundStyle(color).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func quick(_ kind: ProfileLibraryKind, _ icon: String, _ color: Color) -> some View {
        NavigationLink { ProfileLibraryView(kind: kind) } label: {
            VStack(spacing: 8) { Image(systemName: icon).font(.title2).foregroundStyle(color); Text(kind.title).font(.caption).foregroundStyle(.primary) }
                .frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    private func statusTitle(_ value: String) -> String {
        let key = ["pending": "审核中", "approved": "已通过", "rejected": "未通过", "appealing": "申诉中"][value]
        return key.map(L10n.string) ?? value
    }
    private func statusIcon(_ value: String) -> String { ["approved": "checkmark.circle.fill", "rejected": "xmark.circle.fill", "appealing": "arrow.triangle.2.circlepath"][value] ?? "clock.fill" }
    private func statusColor(_ value: String) -> Color { ["approved": .green, "rejected": .red, "appealing": .purple][value] ?? .orange }
    private func reload() { Task { await load() } }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            overview = try await APIClient.shared.get("api/me/overview")
            await loadPhotos()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor
    private func loadPhotos() async {
        do {
            photos = try await APIClient.shared.get(
                "api/me/photos",
                query: [URLQueryItem(name: "status", value: status), URLQueryItem(name: "limit", value: "30")]
            )
        } catch { errorMessage = error.localizedDescription }
    }
}
