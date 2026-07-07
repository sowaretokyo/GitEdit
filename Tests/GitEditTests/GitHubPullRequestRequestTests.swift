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
}
