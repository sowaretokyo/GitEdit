import Foundation

/// A single `git stash` entry.
struct StashEntry: Identifiable, Hashable {
    /// The selector git accepts for this record, e.g. "stash@{0}". Not stable
    /// across other stash operations — always re-resolve via `id` (the SHA)
    /// before trusting it for a destructive op like drop.
    let selector: String
    let index: Int
    let message: String
    let relativeDate: String
    let sha: String

    var id: String { sha }
}
