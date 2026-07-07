import XCTest
@testable import GitEdit

final class PullRequestReviewDecodingTests: XCTestCase {

    private func decodeReview(_ json: String) throws -> PullRequestReview {
        try GitHubAPI.sharedDecoder.decode(PullRequestReview.self, from: Data(json.utf8))
    }

    private func decodeComment(_ json: String) throws -> IssueComment {
        try GitHubAPI.sharedDecoder.decode(IssueComment.self, from: Data(json.utf8))
    }

    func testDecodesApprovedReviewWithBody() throws {
        let json = """
        {
          "id": 1, "state": "APPROVED", "body": "Looks good!",
          "user": { "login": "octocat", "avatar_url": "https://example.com/a.png" },
          "submitted_at": "2024-01-01T00:00:00Z"
        }
        """
        let review = try decodeReview(json)
        XCTAssertEqual(review.id, 1)
        XCTAssertEqual(review.state, "APPROVED")
        XCTAssertEqual(review.body, "Looks good!")
        XCTAssertEqual(review.user?.login, "octocat")
        XCTAssertNotNil(review.submittedAt)
    }

    func testDecodesChangesRequestedReview() throws {
        let json = """
        {
          "id": 2, "state": "CHANGES_REQUESTED", "body": "Please fix the tests.",
          "user": { "login": "reviewer", "avatar_url": null },
          "submitted_at": "2024-01-02T00:00:00Z"
        }
        """
        let review = try decodeReview(json)
        XCTAssertEqual(review.state, "CHANGES_REQUESTED")
        XCTAssertEqual(review.body, "Please fix the tests.")
    }

    func testDecodesReviewWithNullBodyAndSubmittedAt() throws {
        // A "PENDING" review can have a null body and no submitted_at yet.
        let json = """
        {
          "id": 3, "state": "PENDING", "body": null,
          "user": { "login": "octocat", "avatar_url": null },
          "submitted_at": null
        }
        """
        let review = try decodeReview(json)
        XCTAssertEqual(review.state, "PENDING")
        XCTAssertNil(review.body)
        XCTAssertNil(review.submittedAt)
    }

    func testDecodesReviewWithNullUser() throws {
        let json = """
        {
          "id": 4, "state": "COMMENTED", "body": "",
          "user": null,
          "submitted_at": "2024-01-03T00:00:00Z"
        }
        """
        let review = try decodeReview(json)
        XCTAssertNil(review.user)
        XCTAssertEqual(review.body, "")
    }

    func testDecodesIssueComment() throws {
        let json = """
        {
          "id": 10, "body": "Thanks for the PR!",
          "user": { "login": "octocat", "avatar_url": "https://example.com/a.png" },
          "created_at": "2024-01-01T12:00:00Z"
        }
        """
        let comment = try decodeComment(json)
        XCTAssertEqual(comment.id, 10)
        XCTAssertEqual(comment.body, "Thanks for the PR!")
        XCTAssertEqual(comment.user?.login, "octocat")
    }

    func testDecodesIssueCommentWithNullUser() throws {
        let json = """
        {
          "id": 11, "body": "A comment from a deleted account.",
          "user": null,
          "created_at": "2024-01-01T12:00:00Z"
        }
        """
        let comment = try decodeComment(json)
        XCTAssertNil(comment.user)
    }

    func testReviewEventRawValues() {
        XCTAssertEqual(ReviewEvent.approve.rawValue, "APPROVE")
        XCTAssertEqual(ReviewEvent.requestChanges.rawValue, "REQUEST_CHANGES")
        XCTAssertEqual(ReviewEvent.comment.rawValue, "COMMENT")
    }
}
