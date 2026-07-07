import Foundation

/// One entry from `GET /repos/{owner}/{repo}/pulls/{number}/reviews`.
///
/// `state` is the value GitHub reports for an already-submitted review
/// ("APPROVED" | "CHANGES_REQUESTED" | "COMMENTED" | "DISMISSED" | "PENDING")
/// — distinct from `ReviewEvent`'s raw values below, which are what you POST
/// to *create* a review ("APPROVE" | "REQUEST_CHANGES" | "COMMENT"). Kept as
/// a plain `String` rather than an enum since GitHub can return values this
/// app doesn't otherwise act on (e.g. "DISMISSED", "PENDING").
struct PullRequestReview: Codable, Identifiable, Hashable {
    let id: Int
    let user: GitHubUserRef?
    let state: String
    let body: String?
    let submittedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case state
        case body
        case submittedAt = "submitted_at"
    }
}

/// One entry from `GET /repos/{owner}/{repo}/issues/{number}/comments` — a
/// plain conversation comment on the PR's timeline. Distinct from review
/// comments (line-level comments attached to a review), which this app
/// doesn't surface.
struct IssueComment: Codable, Identifiable, Hashable {
    let id: Int
    let user: GitHubUserRef?
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case body
        case createdAt = "created_at"
    }
}

/// The `event` value POSTed to `.../pulls/{number}/reviews` to create a
/// review. `.comment` is part of GitHub's contract (a review that neither
/// approves nor requests changes) but isn't wired to any button in this
/// app's composer — the plain "コメント" action posts a conversation
/// comment via `createIssueComment` instead, since GitHub disallows
/// approving your own PR but does allow commenting on it either way.
enum ReviewEvent: String, Codable {
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
    case comment = "COMMENT"
}
