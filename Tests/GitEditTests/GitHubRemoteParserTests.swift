import XCTest
@testable import GitEdit

final class GitHubRemoteParserTests: XCTestCase {

    private let expected = GitHubRepositoryRef(owner: "owner", repo: "repo")

    func testSCPStyleSSHWithGit() {
        XCTAssertEqual(GitHubRemoteParser.parse(remoteURL: "git@github.com:owner/repo.git"), expected)
    }

    func testHTTPSWithoutGitSuffix() {
        XCTAssertEqual(GitHubRemoteParser.parse(remoteURL: "https://github.com/owner/repo"), expected)
    }

    func testHTTPSWithGitSuffix() {
        XCTAssertEqual(GitHubRemoteParser.parse(remoteURL: "https://github.com/owner/repo.git"), expected)
    }

    func testHTTPSWithTrailingSlash() {
        XCTAssertEqual(GitHubRemoteParser.parse(remoteURL: "https://github.com/owner/repo/"), expected)
    }

    func testSSHSchemeForm() {
        XCTAssertEqual(GitHubRemoteParser.parse(remoteURL: "ssh://git@github.com/owner/repo.git"), expected)
    }

    func testCaseInsensitiveHost() {
        XCTAssertEqual(GitHubRemoteParser.parse(remoteURL: "https://GitHub.com/owner/repo"), expected)
    }

    func testGitLabRemoteReturnsNil() {
        XCTAssertNil(GitHubRemoteParser.parse(remoteURL: "git@gitlab.com:owner/repo.git"))
    }

    func testBitbucketRemoteReturnsNil() {
        XCTAssertNil(GitHubRemoteParser.parse(remoteURL: "https://bitbucket.org/owner/repo.git"))
    }

    func testMissingRepoReturnsNil() {
        XCTAssertNil(GitHubRemoteParser.parse(remoteURL: "https://github.com/owner/"))
    }

    func testEmptyStringReturnsNil() {
        XCTAssertNil(GitHubRemoteParser.parse(remoteURL: ""))
    }

    func testIssueURL() {
        let ref = GitHubRepositoryRef(owner: "owner", repo: "repo")
        XCTAssertEqual(ref.issueURL(123).absoluteString, "https://github.com/owner/repo/issues/123")
    }
}
