import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "app.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L10n.string("跟随系统")
        case .light: L10n.string("浅色")
        case .dark: L10n.string("深色")
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
