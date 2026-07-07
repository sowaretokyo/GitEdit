import Foundation

extension GitHubAPI {
    /// Pure request-shape builders (path + query), split out from the actual
    /// network calls below so path/query construction can be unit-tested
    /// without hitting the network.
    enum PullRequestRequests {
        static func list(owner: String, repo: String) -> (path: String, query: [URLQueryItem]) {
            (
                "/repos/\(owner)/\(repo)/pulls",
                [
                    URLQueryItem(name: "state", value: "open"),
                    URLQueryItem(name: "sort", value: "updated"),
                    URLQueryItem(name: "direction", value: "desc"),
                    URLQueryItem(name: "per_page", value: "50")
                ]
            )
        }

        static func detail(owner: String, repo: String, number: Int) -> String {
            "/repos/\(owner)/\(repo)/pulls/\(number)"
        }

        static func checkRuns(owner: String, repo: String, ref: String) -> String {
            "/repos/\(owner)/\(repo)/commits/\(ref)/check-runs"
        }

        static func combinedStatus(owner: String, repo: String, ref: String) -> String {
            "/repos/\(owner)/\(repo)/commits/\(ref)/status"
        }

        static func create(owner: String, repo: String) -> String {
            "/repos/\(owner)/\(repo)/pulls"
        }

        static func reviews(owner: String, repo: String, number: Int) -> String {
            "/repos/\(owner)/\(repo)/pulls/\(number)/reviews"
        }

        static func createReview(owner: String, repo: String, number: Int) -> String {
            "/repos/\(owner)/\(repo)/pulls/\(number)/reviews"
        }

        static func issueComments(owner: String, repo: String, number: Int) -> String {
            "/repos/\(owner)/\(repo)/issues/\(number)/comments"
        }

        static func createIssueComment(owner: String, repo: String, number: Int) -> String {
            "/repos/\(owner)/\(repo)/issues/\(number)/comments"
        }
    }

    struct CreatePullRequestBody: Encodable, Equatable {
        let title: String
        let head: String
        let base: String
        let body: String?
    }

    struct CreateReviewBody: Encodable, Equatable {
        let event: String
        let body: String?
    }

    struct CreateIssueCommentBody: Encodable, Equatable {
        let body: String
    }

    /// The 50 most recently updated open PRs. GitHub caps `per_page` at 100;
    /// 50 keeps the per-PR check-status fan-out (see
    /// `PullRequestsViewModel.loadCIStatuses`) from firing too many requests
    /// at once. `nextPageURL` on the returned wrapper tells callers whether
    /// there are more.
    func listPullRequests(owner: String, repo: String) async throws -> GitHubResponse<[PullRequest]> {
        let (path, query) = PullRequestRequests.list(owner: owner, repo: repo)
        return try await send(method: "GET", path: path, query: query, as: [PullRequest].self)
    }

    func pullRequest(owner: String, repo: String, number: Int) async throws -> PullRequest {
        try await send(
            method: "GET",
            path: PullRequestRequests.detail(owner: owner, repo: repo, number: number),
            as: PullRequest.self
        ).value
    }

    func checkRuns(owner: String, repo: String, ref: String) async throws -> CheckRunsResponse {
        try await send(
            method: "GET",
            path: PullRequestRequests.checkRuns(owner: owner, repo: repo, ref: ref),
            as: CheckRunsResponse.self
        ).value
    }

    func combinedStatus(owner: String, repo: String, ref: String) async throws -> CombinedStatus {
        try await send(
            method: "GET",
            path: PullRequestRequests.combinedStatus(owner: owner, repo: repo, ref: ref),
            as: CombinedStatus.self
        ).value
    }

    func createPullRequest(
        owner: String,
        repo: String,
        title: String,
        head: String,
        base: String,
        body: String?
    ) async throws -> PullRequest {
        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = CreatePullRequestBody(
            title: title,
            head: head,
            base: base,
            body: (trimmedBody?.isEmpty ?? true) ? nil : trimmedBody
        )
        let data = try JSONEncoder().encode(payload)
        return try await send(
            method: "POST",
            path: PullRequestRequests.create(owner: owner, repo: repo),
            body: data,
            as: PullRequest.self,
            requiredScope: "repo"
        ).value
    }

    // MARK: - Reviews & comments

    func reviews(owner: String, repo: String, number: Int) async throws -> [PullRequestReview] {
        try await send(
            method: "GET",
            path: PullRequestRequests.reviews(owner: owner, repo: repo, number: number),
            as: [PullRequestReview].self
        ).value
    }

    func issueComments(owner: String, repo: String, number: Int) async throws -> [IssueComment] {
        try await send(
            method: "GET",
            path: PullRequestRequests.issueComments(owner: owner, repo: repo, number: number),
            as: [IssueComment].self
        ).value
    }

    /// Submits a formal review (approve / request changes / comment-only).
    /// `body` is trimmed and sent as `nil` when empty — GitHub requires a
    /// body for `.requestChanges` and `.comment`, which the caller validates
    /// before reaching here.
    func createReview(
        owner: String,
        repo: String,
        number: Int,
        event: ReviewEvent,
        body: String?
    ) async throws -> PullRequestReview {
        let trimmedBody = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = CreateReviewBody(event: event.rawValue, body: (trimmedBody?.isEmpty ?? true) ? nil : trimmedBody)
        let data = try JSONEncoder().encode(payload)
        return try await send(
            method: "POST",
            path: PullRequestRequests.createReview(owner: owner, repo: repo, number: number),
            body: data,
            as: PullRequestReview.self,
            requiredScope: "repo"
        ).value
    }

    /// Posts a plain conversation comment (not tied to review state).
    func createIssueComment(owner: String, repo: String, number: Int, body: String) async throws -> IssueComment {
        let payload = CreateIssueCommentBody(body: body)
        let data = try JSONEncoder().encode(payload)
        return try await send(
            method: "POST",
            path: PullRequestRequests.createIssueComment(owner: owner, repo: repo, number: number),
            body: data,
            as: IssueComment.self,
            requiredScope: "repo"
        ).value
    }
}
