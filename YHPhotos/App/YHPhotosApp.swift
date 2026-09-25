import SwiftUI

@main
struct YHPhotosApp: App {
    @StateObject private var appModel = AppModel()
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
                .tint(Color("AccentColor"))
                .preferredColorScheme(.dark)
                .task { await appModel.restoreSession() }
        }
    }
}
