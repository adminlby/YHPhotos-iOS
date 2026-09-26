import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                tabletRoot
            } else {
                phoneRoot
            }
        }
        .sheet(isPresented: $appModel.showingUpload) { UploadView() }
        .sheet(isPresented: $appModel.showingLogin) { LoginView() }
    }

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
