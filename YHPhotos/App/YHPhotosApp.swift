import SwiftUI

@main
struct YHPhotosApp: App {
    @UIApplicationDelegateAdaptor(YHPhotosAppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @AppStorage(AppAppearance.storageKey) private var appAppearance = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .tint(Color("AccentColor"))
                .preferredColorScheme((AppAppearance(rawValue: appAppearance) ?? .system).colorScheme)
                .task { await appModel.restoreSession() }
        }
    }
}
