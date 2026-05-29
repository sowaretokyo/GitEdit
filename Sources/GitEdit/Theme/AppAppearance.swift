import SwiftUI

/// User-selectable appearance. Persisted in UserDefaults under "appAppearance".
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L("システムに合わせる")
        case .light: return L("ライト")
        case .dark: return L("ダーク")
        }
    }

    var iconSystemName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// `nil` means "follow the system" — pass it to `.preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static var current: AppAppearance {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppAppearance.system.rawValue
        return AppAppearance(rawValue: raw) ?? .system
    }
}
