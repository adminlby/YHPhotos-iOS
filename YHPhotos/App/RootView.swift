import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if !appModel.hasRestoredSession || appModel.sessionRestoreError != nil {
                launchPlaceholder
            } else {
#if DEBUG
                if AppStoreDemo.isEnabled, isDirectDemoScreen {
                    directDemoRoot
                } else if horizontalSizeClass == .regular {
                    tabletRoot
                } else {
                    phoneRoot
                }
#else
                if horizontalSizeClass == .regular {
                    tabletRoot
                } else {
                    phoneRoot
                }
#endif
            }
        }
        .sheet(isPresented: $appModel.showingUpload) { UploadView() }
        .sheet(isPresented: $appModel.showingLogin) { LoginView() }
        .fullScreenCover(
            isPresented: Binding(
                get: { appModel.hasRestoredSession && appModel.requiresLegalAcceptance },
                set: { _ in }
            )
        ) {
            LegalConsentView()
                .environmentObject(appModel)
                .interactiveDismissDisabled()
        }
    }

    private var launchPlaceholder: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            if let errorMessage = appModel.sessionRestoreError {
                EmptyStateView(
                    L10n.string("无法验证账号状态"),
                    systemImage: "exclamationmark.shield.fill",
                    description: errorMessage
                ) {
                    Button(L10n.string("重试")) {
                        Task { await appModel.restoreSession() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                SecureLaunchAnimation()
            }
        }
    }

#if DEBUG
    private var isDirectDemoScreen: Bool {
        [.photo, .map, .inspector].contains(AppStoreDemo.screen)
    }

    @ViewBuilder
    private var directDemoRoot: some View {
        switch AppStoreDemo.screen {
        case .photo:
            NavigationStack { PhotoDetailView(photoID: 1) }
        case .map:
            NavigationStack { MapBrowserView() }
        case .inspector:
            NavigationStack { ImageInspectorLauncherView() }
        default:
            phoneRoot
        }
    }
#endif

    private var phoneRoot: some View {
        TabView(selection: Binding(
            get: { appModel.selectedSection },
            set: { appModel.select($0) }
        )) {
            tab(.discover) { DiscoverView() }
            tab(.tools) { ToolsHomeView() }
            tab(.upload) { Color.clear }
            tab(.messages) { MessagesView() }
            tab(.profile) { UserCenterView() }
        }
        .tint(AppTheme.accent)
    }

    private func tab<Content: View>(_ section: AppSection, @ViewBuilder content: () -> Content) -> some View {
        content()
            .tag(section)
            .tabItem { Label(section.title, systemImage: section.icon) }
    }

    private var tabletRoot: some View {
        NavigationSplitView {
            List(AppSection.allCases.filter { $0 != .upload }, selection: Binding(
                get: { appModel.selectedSection },
                set: { appModel.selectedSection = $0 ?? .discover }
            )) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationTitle("YHPhotos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { appModel.select(.upload) } label: { Label("上传", systemImage: "plus") }
                }
            }
        } detail: {
            selectedScreen
        }
        .navigationSplitViewStyle(.balanced)
        .appScreenBackground()
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch appModel.selectedSection {
        case .discover: DiscoverView()
        case .tools: ToolsHomeView()
        case .upload: DiscoverView()
        case .messages: MessagesView()
        case .profile: UserCenterView()
        }
    }
}

private struct SecureLaunchAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(pulsing ? 0.14 : 0.07))
                    .frame(width: 104, height: 104)
                    .scaleEffect(pulsing ? 1.08 : 0.94)

                Circle()
                    .trim(from: 0.08, to: 0.82)
                    .stroke(
                        AngularGradient(
                            colors: [AppTheme.accent.opacity(0.08), AppTheme.accent, .cyan, AppTheme.accent.opacity(0.08)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(rotating ? 360 : 0))

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 38, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.accent)
                    .scaleEffect(pulsing ? 1.03 : 0.97)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .padding(6)
                    .background(.thinMaterial, in: Circle())
                    .offset(x: 38, y: 38)
            }
            .accessibilityHidden(true)

            VStack(spacing: 7) {
                Text(L10n.string("正在安全加载…"))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.string("正在验证会话并准备你的图库"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotating = true
            }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}
