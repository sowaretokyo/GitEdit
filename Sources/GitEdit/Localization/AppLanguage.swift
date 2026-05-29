import Foundation

/// User-selectable UI language. Persisted in `UserDefaults` under "appLanguage".
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case japanese = "ja"
    case english = "en"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L("システムに従う")
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }

    /// The lproj directory code; `nil` means use the system default.
    var bundleLanguageCode: String? {
        switch self {
        case .system: return nil
        case .japanese: return "ja"
        case .english: return "en"
        }
    }

    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        return AppLanguage(rawValue: raw) ?? .system
    }
}
