import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let storageKey = "app.language"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L10n.string("跟随系统")
        case .simplifiedChinese: L10n.string("简体中文")
        case .english: "English"
        }
    }

    static var selected: AppLanguage {
        let value = UserDefaults.standard.string(forKey: storageKey) ?? system.rawValue
        return AppLanguage(rawValue: value) ?? .system
    }

    static var resolved: AppLanguage {
        let selected = selected
        guard selected == .system else { return selected }

        let identifier = Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
        let normalized = Locale.canonicalLanguageIdentifier(from: identifier).lowercased()
        if normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh-hk") ||
            normalized.hasPrefix("zh-mo") || normalized.hasPrefix("zh-tw") {
            return .english
        }
        return normalized.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    var locale: Locale {
        switch self == .system ? AppLanguage.resolved : self {
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english, .system: Locale(identifier: "en")
        }
    }

    var apiValue: String {
        switch self == .system ? AppLanguage.resolved : self {
        case .simplifiedChinese: "zh"
        case .english, .system: "en"
        }
    }

    var httpLanguageTag: String {
        apiValue == "zh" ? "zh-CN" : "en"
    }
}

enum L10n {
    static func string(_ key: String) -> String {
        let language = AppLanguage.resolved.rawValue
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: AppLanguage.resolved.locale, arguments: arguments)
    }
}
