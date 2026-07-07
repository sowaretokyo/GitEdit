import XCTest
@testable import GitEdit

final class PullRequestDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> PullRequest {
        try GitHubAPI.sharedDecoder.decode(PullRequest.self, from: Data(json.utf8))
    }

    func testDecodesListItemWithNullMergeable() throws {
        let json = """
        {
          "number": 42,
          "title": "Add login flow",
          "state": "open",
          "draft": false,
          "body": "Implements the new login flow.",
          "html_url": "https://github.com/owner/repo/pull/42",
          "user": { "login": "octocat", "avatar_url": "https://example.com/a.png" },
          "head": {
            "ref": "feature/login", "sha": "abc123", "label": "owner:feature/login",
            "repo": { "full_name": "owner/repo", "name": "repo", "owner": { "login": "owner" } }
          },
          "base": {
            "ref": "main", "sha": "def456", "label": "owner:main",
            "repo": { "full_name": "owner/repo", "name": "repo", "owner": { "login": "owner" } }
          },
          "created_at": "2024-01-01T00:00:00Z",
          "updated_at": "2024-01-02T00:00:00Z",
          "merged": false,
          "mergeable": null,
          "mergeable_state": "unknown"
        }
        """
        let pr = try decode(json)
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.title, "Add login flow")
        XCTAssertTrue(pr.isOpen)
        XCTAssertFalse(pr.isMerged)
        XCTAssertFalse(pr.isDraft)
        XCTAssertNil(pr.mergeable)
        XCTAssertEqual(pr.head.ref, "feature/login")
        XCTAssertEqual(pr.user?.login, "octocat")
        XCTAssertTrue(pr.isSameRepo)
    }

    func testDecodesDetailWithMergeableTrue() throws {
        let json = """
        {
          "number": 7, "title": "Fix crash", "state": "open", "draft": true, "body": null,
          "html_url": "https://github.com/owner/repo/pull/7",
          "user": null,
          "head": { "ref": "fix/crash", "sha": "111", "label": "owner:fix/crash",
                    "repo": { "full_name": "owner/repo", "name": "repo", "owner": { "login": "owner" } } },
          "base": { "ref": "main", "sha": "222", "label": "owner:main",
                    "repo": { "full_name": "owner/repo", "name": "repo", "owner": { "login": "owner" } } },
          "created_at": "2024-02-01T00:00:00Z",
          "updated_at": "2024-02-02T00:00:00Z",
          "merged": false,
          "mergeable": true,
          "mergeable_state": "clean"
        }
        """
        let pr = try decode(json)
        XCTAssertTrue(pr.isDraft)
        XCTAssertNil(pr.body)
        XCTAssertNil(pr.user)
        XCTAssertEqual(pr.mergeable, true)
    }

    func testDecodesForkPullRequestWithNullHeadRepo() throws {
        let json = """
        {
          "number": 9, "title": "From a fork", "state": "open", "draft": false, "body": "",
          "html_url": "https://github.com/owner/repo/pull/9",
          "user": { "login": "contributor", "avatar_url": null },
          "head": { "ref": "patch-1", "sha": "333", "label": "contributor:patch-1", "repo": null },
          "base": { "ref": "main", "sha": "444", "label": "owner:main",
                    "repo": { "full_name": "owner/repo", "name": "repo", "owner": { "login": "owner" } } },
          "created_at": "2024-03-01T00:00:00Z",
          "updated_at": "2024-03-02T00:00:00Z",
          "merged": null,
          "mergeable": null,
          "mergeable_state": null
        }
        """
        let pr = try decode(json)
        XCTAssertNil(pr.head.repo)
        XCTAssertNil(pr.user?.avatarURL)
        XCTAssertFalse(pr.isSameRepo)
    }

    func testMergedPullRequestState() throws {
        let json = """
        {
          "number": 1, "title": "Merged one", "state": "closed", "draft": false, "body": "",
          "html_url": "https://github.com/owner/repo/pull/1",
          "user": { "login": "octocat", "avatar_url": "https://example.com/a.png" },
          "head": { "ref": "feature", "sha": "555", "label": "owner:feature",
                    "repo": { "full_name": "owner/repo", "name": "repo", "owner": { "login": "owner" } } },
          "base": { "ref": "main", "sha": "666", "label": "owner:main",
                    "repo": { "full_name": "owner/repo", "name": "repo", "owner": { "login": "owner" } } },
          "created_at": "2024-04-01T00:00:00Z",
          "updated_at": "2024-04-02T00:00:00Z",
          "merged": true,
          "mergeable": null,
          "mergeable_state": null
        }
        """
        let pr = try decode(json)
        XCTAssertTrue(pr.isMerged)
        XCTAssertFalse(pr.isOpen)
        XCTAssertTrue(pr.isSameRepo)
    }
}
