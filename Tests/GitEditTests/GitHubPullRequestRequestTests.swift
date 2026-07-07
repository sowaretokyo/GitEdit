import XCTest
@testable import GitEdit

final class GitHubPullRequestRequestTests: XCTestCase {

    func testListPathAndQuery() {
        let (path, query) = GitHubAPI.PullRequestRequests.list(owner: "octo", repo: "cat")
        XCTAssertEqual(path, "/repos/octo/cat/pulls")
        XCTAssertEqual(query, [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: "50")
        ])
    }

    func testDetailPath() {
        XCTAssertEqual(
            GitHubAPI.PullRequestRequests.detail(owner: "octo", repo: "cat", number: 42),
            "/repos/octo/cat/pulls/42"
        )
    }

    func testCheckRunsPath() {
        XCTAssertEqual(
            GitHubAPI.PullRequestRequests.checkRuns(owner: "octo", repo: "cat", ref: "abc123"),
            "/repos/octo/cat/commits/abc123/check-runs"
        )
    }

    func testCombinedStatusPath() {
        XCTAssertEqual(
            GitHubAPI.PullRequestRequests.combinedStatus(owner: "octo", repo: "cat", ref: "abc123"),
            "/repos/octo/cat/commits/abc123/status"
        )
    }

    func testCreatePath() {
        XCTAssertEqual(GitHubAPI.PullRequestRequests.create(owner: "octo", repo: "cat"), "/repos/octo/cat/pulls")
    }

    func testCreatePullRequestBodyEncodesExpectedJSON() throws {
        let body = GitHubAPI.CreatePullRequestBody(title: "Add feature", head: "feature/x", base: "main", body: "Description here")
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["title"] as? String, "Add feature")
        XCTAssertEqual(object?["head"] as? String, "feature/x")
        XCTAssertEqual(object?["base"] as? String, "main")
        XCTAssertEqual(object?["body"] as? String, "Description here")
    }

    func testCreatePullRequestBodyOmitsNilBody() throws {
        let body = GitHubAPI.CreatePullRequestBody(title: "Add feature", head: "feature/x", base: "main", body: nil)
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(object?["body"])
        XCTAssertEqual(object?["title"] as? String, "Add feature")
    }

    // MARK: - Reviews & comments (L3)

    func testReviewsPath() {
        XCTAssertEqual(
            GitHubAPI.PullRequestRequests.reviews(owner: "octo", repo: "cat", number: 42),
            "/repos/octo/cat/pulls/42/reviews"
        )
    }

    func testCreateReviewPath() {
        XCTAssertEqual(
            GitHubAPI.PullRequestRequests.createReview(owner: "octo", repo: "cat", number: 42),
            "/repos/octo/cat/pulls/42/reviews"
        )
    }

    func testIssueCommentsPath() {
        XCTAssertEqual(
            GitHubAPI.PullRequestRequests.issueComments(owner: "octo", repo: "cat", number: 42),
            "/repos/octo/cat/issues/42/comments"
        )
    }

    func testCreateIssueCommentPath() {
        XCTAssertEqual(
            GitHubAPI.PullRequestRequests.createIssueComment(owner: "octo", repo: "cat", number: 42),
            "/repos/octo/cat/issues/42/comments"
        )
    }

    func testCreateReviewBodyEncodesEventAndBody() throws {
        let body = GitHubAPI.CreateReviewBody(event: ReviewEvent.requestChanges.rawValue, body: "Please fix the tests")
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["event"] as? String, "REQUEST_CHANGES")
        XCTAssertEqual(object?["body"] as? String, "Please fix the tests")
    }

    func testCreateReviewBodyOmitsNilBody() throws {
        let body = GitHubAPI.CreateReviewBody(event: ReviewEvent.approve.rawValue, body: nil)
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["event"] as? String, "APPROVE")
        XCTAssertNil(object?["body"])
    }

    func testCreateIssueCommentBodyEncodesBody() throws {
        let body = GitHubAPI.CreateIssueCommentBody(body: "Thanks!")
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["body"] as? String, "Thanks!")
    }

    // MARK: - Merge (L4)

    func testMergePath() {
        XCTAssertEqual(
            GitHubAPI.PullRequestRequests.merge(owner: "octo", repo: "cat", number: 42),
            "/repos/octo/cat/pulls/42/merge"
        )
    }

    func testMergePullRequestBodyEncodesAllFields() throws {
        let body = GitHubAPI.MergePullRequestBody(
            mergeMethod: MergeMethod.squash.rawValue,
            sha: "abc123",
            commitTitle: "Squash it",
            commitMessage: "Details here"
        )
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["merge_method"] as? String, "squash")
        XCTAssertEqual(object?["sha"] as? String, "abc123")
        XCTAssertEqual(object?["commit_title"] as? String, "Squash it")
        XCTAssertEqual(object?["commit_message"] as? String, "Details here")
    }

    func testMergePullRequestBodyOmitsNilFields() throws {
        let body = GitHubAPI.MergePullRequestBody(
            mergeMethod: MergeMethod.merge.rawValue,
            sha: nil,
            commitTitle: nil,
            commitMessage: nil
        )
        let data = try JSONEncoder().encode(body)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["merge_method"] as? String, "merge")
        XCTAssertNil(object?["sha"])
        XCTAssertNil(object?["commit_title"])
        XCTAssertNil(object?["commit_message"])
    }
}
