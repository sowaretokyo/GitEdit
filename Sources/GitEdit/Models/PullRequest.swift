import Foundation

/// A GitHub user reference as embedded in pull request payloads (author, etc.).
struct GitHubUserRef: Codable, Hashable {
    let login: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarURL = "avatar_url"
    }
}

/// A repository owner reference, as embedded in `RepoRef`.
struct OwnerRef: Codable, Hashable {
    let login: String
}

/// A repository reference, as embedded in a pull request's `head`/`base`.
struct RepoRef: Codable, Hashable {
    let fullName: String
    let name: String
    let owner: OwnerRef

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
        case owner
    }
}

/// One side (`head` or `base`) of a pull request. `repo` is `nil` when the
/// source repository has been deleted (common for old fork PRs).
struct PullRequestBranchRef: Codable, Hashable {
    let ref: String
    let sha: String
    let label: String
    let repo: RepoRef?
}

/// A GitHub pull request, as returned by the list and detail endpoints.
struct PullRequest: Codable, Identifiable, Hashable {
    let number: Int
    let title: String
    let state: String
    let isDraft: Bool
    let body: String?
    let htmlURL: String
    let user: GitHubUserRef?
    let head: PullRequestBranchRef
    let base: PullRequestBranchRef
    let createdAt: Date
    let updatedAt: Date
    let merged: Bool?
    let mergeable: Bool?
    let mergeableState: String?

    var id: Int { number }

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case state
        case isDraft = "draft"
        case body
        case htmlURL = "html_url"
        case user
        case head
        case base
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case merged
        case mergeable
        case mergeableState = "mergeable_state"
    }

    var isOpen: Bool { state == "open" }
    var isMerged: Bool { merged == true }

    /// True when the PR's head branch lives in the same repository as its
    /// base — i.e. not a fork. `head.repo` is `nil` when the response omits
    /// it (fork PR whose source repository was deleted), which is also
    /// treated as "not same-repo" since a plain `git fetch <remote> <ref>`
    /// requires the ref to actually exist on that remote.
    var isSameRepo: Bool {
        guard let headRepo = head.repo, let baseRepo = base.repo else { return false }
        return headRepo.fullName == baseRepo.fullName
    }
}
