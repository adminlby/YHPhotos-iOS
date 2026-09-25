import SwiftUI

@main
struct YHPhotosApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .tint(Color("AccentColor"))
                .preferredColorScheme(.dark)
                .task { await appModel.restoreSession() }
        }
    }
}
