import Foundation

/// User-selectable diff rendering style. Persisted in UserDefaults under
/// "diffDisplayStyle". Applies app-wide, matching `AppAppearance`'s pattern.
enum DiffDisplayStyle: String, CaseIterable, Identifiable {
    case unified
    case split

    static let storageKey = "diffDisplayStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unified: return L("統合")
        case .split: return L("分割")
        }
    }
}
