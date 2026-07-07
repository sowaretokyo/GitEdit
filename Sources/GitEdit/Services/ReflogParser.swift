import Foundation

/// A single `git reflog` record for HEAD.
struct ReflogEntry: Equatable {
    /// e.g. "HEAD@{0}"
    let selector: String
    /// Full SHA of the commit HEAD pointed to *after* this reflog event.
    let sha: String
    /// Abbreviated SHA.
    let shortSHA: String
    /// The reflog subject, e.g. "commit: Add feature" or "checkout: moving from a to b".
    let subject: String
}

enum ReflogParser {
    /// Field separator (Unit Separator).
    static let fieldSep = "\u{1F}"
    /// Record separator (Record Separator). Appended after every record so
    /// records can be split even when `%gs` itself contains a newline.
    static let recordSep = "\u{1E}"

    /// `%gs` is placed last so an embedded field separator in the subject
    /// (unlikely, but subjects are free-form commit summaries) can't shift
    /// fields after it.
    static let formatTemplate = "%gd\(fieldSep)%H\(fieldSep)%h\(fieldSep)%gs\(recordSep)"

    static func parse(_ output: String) -> [ReflogEntry] {
        var entries: [ReflogEntry] = []
        for record in output.split(separator: Character(recordSep), omittingEmptySubsequences: true) {
            // maxSplits: 3 keeps anything past the 3rd separator (the subject)
            // intact even if it happens to contain the separator character.
            let fields = record
                .split(separator: Character(fieldSep), maxSplits: 3, omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count == 4 else { continue }

            let selector = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let sha = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let shortSHA = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !selector.isEmpty, !sha.isEmpty else { continue }

            entries.append(ReflogEntry(
                selector: selector,
                sha: sha,
                shortSHA: shortSHA,
                subject: subject
            ))
        }
        return entries
    }
}

/// A single-step operation that can be undone by resetting/checking out to
/// the state recorded just before it in the reflog.
enum UndoableOperation: Equatable {
    /// A plain `git commit`. Undo: `reset --soft` to the prior HEAD.
    case commit(summary: String, targetSHA: String)
    /// A `git commit --amend`. Undo: `reset --soft` to the prior HEAD (the
    /// pre-amend commit).
    case amendCommit(summary: String, targetSHA: String)
    /// A `git merge` that produced a new commit (fast-forward or a real merge
    /// commit). Undo: `reset --hard` to the prior HEAD.
    case mergeCommit(summary: String, targetSHA: String)
    /// A branch switch (`checkout`/`switch`). Undo: checkout the prior branch.
    case branchSwitch(from: String, to: String)

    /// True for operations undone via `git reset` (commit-like operations).
    var isResetBased: Bool {
        switch self {
        case .commit, .amendCommit, .mergeCommit: return true
        case .branchSwitch: return false
        }
    }

    /// Only merges require `reset --hard` (they can bring in working-tree
    /// changes beyond the index that `--soft` wouldn't undo).
    var requiresHardReset: Bool {
        if case .mergeCommit = self { return true }
        return false
    }
}

/// Derives the single undoable operation (if any) represented by the most
/// recent reflog entry, using the entry just before it for context (e.g. the
/// SHA to reset back to).
enum ReflogUndoDeriver {
    static func undoable(top: ReflogEntry, previous: ReflogEntry?) -> UndoableOperation? {
        let subject = top.subject

        if subject.hasPrefix("commit (initial):") {
            return nil
        }
        if subject.hasPrefix("commit (amend):") {
            guard let previous else { return nil }
            let summary = extractSummary(subject, afterPrefix: "commit (amend):")
            return .amendCommit(summary: summary, targetSHA: previous.sha)
        }
        if subject.hasPrefix("commit (merge):") {
            guard let previous else { return nil }
            let summary = extractSummary(subject, afterPrefix: "commit (merge):")
            return .mergeCommit(summary: summary, targetSHA: previous.sha)
        }
        if subject.hasPrefix("commit:") {
            guard let previous else { return nil }
            let summary = extractSummary(subject, afterPrefix: "commit:")
            return .commit(summary: summary, targetSHA: previous.sha)
        }
        if subject.hasPrefix("merge ") {
            guard let previous else { return nil }
            guard let colonRange = subject.range(of: ": ") else { return nil }
            let branch = String(subject[subject.index(subject.startIndex, offsetBy: "merge ".count)..<colonRange.lowerBound])
            let detail = subject[colonRange.upperBound...]
            guard detail.hasPrefix("Fast-forward") || detail.hasPrefix("Merge made by") else { return nil }
            return .mergeCommit(summary: branch, targetSHA: previous.sha)
        }
        if subject.hasPrefix("checkout: moving from ") {
            let rest = subject.dropFirst("checkout: moving from ".count)
            guard let toRange = rest.range(of: " to ") else { return nil }
            let from = String(rest[rest.startIndex..<toRange.lowerBound])
            let to = String(rest[toRange.upperBound...])
            // A detached-HEAD starting point (bare 40-hex SHA) has no branch
            // to switch back to.
            guard !isFullSHA(from) else { return nil }
            return .branchSwitch(from: from, to: to)
        }
        // `reset:`, `pull:`, and anything else are not undoable — undoing a
        // reset via another reset risks silently "redoing" whatever the user
        // just backed out of.
        return nil
    }

    private static func extractSummary(_ subject: String, afterPrefix prefix: String) -> String {
        String(subject.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isFullSHA(_ s: String) -> Bool {
        s.count == 40 && s.allSatisfy(\.isHexDigit)
    }
}
