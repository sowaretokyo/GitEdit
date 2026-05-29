import SwiftUI

extension FileChange.Category {
    /// Accent color used by status badges and gutter highlights for this
    /// category of change.
    var statusColor: Color {
        switch self {
        case .modified, .typeChanged: return DT.Status.modified
        case .added:                  return DT.Status.added
        case .deleted:                return DT.Status.deleted
        case .renamed, .copied:       return DT.Status.renamed
        case .untracked:              return DT.Status.untracked
        case .unmerged:               return DT.Status.unmerged
        case .ignored:                return .secondary
        }
    }
}

extension FileChange {
    var statusColor: Color { category.statusColor }
}
