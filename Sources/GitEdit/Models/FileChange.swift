import Foundation

/// One row per path. `indexStatus` (X) and `workingStatus` (Y) follow git porcelain v1.
struct FileChange: Identifiable, Hashable {
    var id: String { path }

    let path: String
    let indexStatus: Character
    let workingStatus: Character
    let renameFrom: String?

    var isUntracked: Bool { indexStatus == "?" && workingStatus == "?" }
    var isIgnored: Bool { indexStatus == "!" && workingStatus == "!" }

    var hasStagedChange: Bool {
        !isUntracked && !isIgnored && indexStatus != " "
    }

    var hasUnstagedChange: Bool {
        isUntracked || (!isIgnored && workingStatus != " ")
    }

    /// Will this be included in the next `git commit`?
    var willBeCommitted: Bool { hasStagedChange }

    /// True for unresolved merge conflicts: both porcelain "U" states, plus the
    /// add/add and delete/delete conflict pairs which porcelain reports as
    /// "AA" / "DD" rather than "U?"/"?U".
    var isConflicted: Bool {
        if indexStatus == "U" || workingStatus == "U" { return true }
        if indexStatus == "A" && workingStatus == "A" { return true }
        if indexStatus == "D" && workingStatus == "D" { return true }
        return false
    }

    var primaryStatusSymbol: String {
        if isConflicted { return "U" }
        if isUntracked { return "?" }
        if isIgnored { return "!" }
        if indexStatus != " " { return String(indexStatus) }
        if workingStatus != " " { return String(workingStatus) }
        return " "
    }

    var displayPath: String {
        if let from = renameFrom {
            return "\(from) → \(path)"
        }
        return path
    }

    enum Category {
        case modified, added, deleted, renamed, copied, typeChanged, untracked, ignored, unmerged
    }

    var category: Category {
        if isConflicted { return .unmerged }
        if isUntracked { return .untracked }
        if isIgnored { return .ignored }
        let ch = (indexStatus != " ") ? indexStatus : workingStatus
        switch ch {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "T": return .typeChanged
        case "U": return .unmerged
        default: return .modified
        }
    }
}
