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
        ZStack(alignment: .bottom) {
            selectedScreen
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 100) }

            FloatingDock()
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
        .appScreenBackground()
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
        case .wiki: WikiHomeView()
        case .upload: DiscoverView()
        case .messages: MessagesView()
        case .profile: UserCenterView()
        }
    }
}
