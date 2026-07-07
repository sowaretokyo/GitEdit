import XCTest
@testable import GitEdit

final class GitHubResponseHeadersTests: XCTestCase {

    func testExtractsNextPageURLFromLinkHeader() {
        let header = "<https://api.github.com/repos/o/r/pulls?page=2>; rel=\"next\", <https://api.github.com/repos/o/r/pulls?page=5>; rel=\"last\""
        XCTAssertEqual(
            GitHubResponseHeaders.nextPageURL(linkHeader: header)?.absoluteString,
            "https://api.github.com/repos/o/r/pulls?page=2"
        )
    }

    func testReturnsNilWithoutNextRel() {
        let header = "<https://api.github.com/repos/o/r/pulls?page=1>; rel=\"prev\""
        XCTAssertNil(GitHubResponseHeaders.nextPageURL(linkHeader: header))
    }

    func testReturnsNilForMissingLinkHeader() {
        XCTAssertNil(GitHubResponseHeaders.nextPageURL(linkHeader: nil))
    }

    func testParsesOAuthScopesCSV() {
        XCTAssertEqual(GitHubResponseHeaders.scopes(oauthScopesHeader: "repo, user:email"), ["repo", "user:email"])
    }

    func testParsesEmptyOrMissingOAuthScopes() {
        XCTAssertEqual(GitHubResponseHeaders.scopes(oauthScopesHeader: ""), [])
        XCTAssertEqual(GitHubResponseHeaders.scopes(oauthScopesHeader: nil), [])
    }

    func testParsesRateLimitHeaders() {
        let limit = GitHubResponseHeaders.rateLimit(limitHeader: "5000", remainingHeader: "10", resetHeader: "1700000000")
        XCTAssertEqual(limit?.limit, 5000)
        XCTAssertEqual(limit?.remaining, 10)
        XCTAssertEqual(limit?.reset, Date(timeIntervalSince1970: 1700000000))
    }

    func testRateLimitReturnsNilWhenAnyHeaderIsMissing() {
        XCTAssertNil(GitHubResponseHeaders.rateLimit(limitHeader: nil, remainingHeader: "10", resetHeader: "1700000000"))
        XCTAssertNil(GitHubResponseHeaders.rateLimit(limitHeader: "5000", remainingHeader: nil, resetHeader: "1700000000"))
        XCTAssertNil(GitHubResponseHeaders.rateLimit(limitHeader: "5000", remainingHeader: "10", resetHeader: nil))
    }

    func testRateLimitReturnsNilForMalformedNumbers() {
        XCTAssertNil(GitHubResponseHeaders.rateLimit(limitHeader: "not-a-number", remainingHeader: "10", resetHeader: "1700000000"))
    }
}
