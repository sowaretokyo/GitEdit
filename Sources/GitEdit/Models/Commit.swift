import Foundation

/// Single author / co-author of a commit.
struct CommitAuthor: Hashable {
    let name: String
    let email: String
}

struct Commit: Identifiable, Hashable {
    let id: String
    let shortSHA: String
    let summary: String
    let body: String
    let author: String
    let authorEmail: String
    let date: Date
    /// Authors discovered from `Co-Authored-By:` trailers in the commit body,
    /// in the order they appear. The primary `author` is *not* included here.
    let coAuthors: [CommitAuthor]

    /// Primary author followed by every co-author. Convenient for views that
    /// render a stack of avatars / a "X, Y, Z" name list.
    var allAuthors: [CommitAuthor] {
        [CommitAuthor(name: author, email: authorEmail)] + coAuthors
    }

    /// Comma-separated display names of every author of this commit. Used in
    /// the history sidebar so a co-authored commit reads "alice, bob".
    var allAuthorDisplayNames: String {
        allAuthors.map(\.name).joined(separator: ", ")
    }
}
