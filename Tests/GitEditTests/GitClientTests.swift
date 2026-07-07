import XCTest
@testable import GitEdit

final class GitClientTests: XCTestCase {

    private let sep = "\u{1F}"

    func testParseHeadMessageWithSubjectOnly() {
        let raw = "Fix the login bug\(sep)"
        let result = GitClient.parseHeadMessage(raw, separator: sep)
        XCTAssertEqual(result?.summary, "Fix the login bug")
        XCTAssertEqual(result?.body, "")
    }

    func testParseHeadMessageWithSubjectAndMultiLineBody() {
        let raw = "Fix the login bug\(sep)This addresses a regression\nintroduced in the last release.\n"
        let result = GitClient.parseHeadMessage(raw, separator: sep)
        XCTAssertEqual(result?.summary, "Fix the login bug")
        XCTAssertEqual(result?.body, "This addresses a regression\nintroduced in the last release.")
    }

    func testParseHeadMessageWithEmptyString() {
        let result = GitClient.parseHeadMessage("", separator: sep)
        XCTAssertEqual(result?.summary, "")
        XCTAssertEqual(result?.body, "")
    }

    // MARK: - gitVersionAtLeast (partial-stash feature gate: git 2.35+)

    func testGitVersionAtLeastAcceptsExactBoundaryVersion() {
        XCTAssertTrue(GitClient.gitVersionAtLeast("2.35.0", major: 2, minor: 35))
    }

    func testGitVersionAtLeastRejectsVersionBelowBoundary() {
        XCTAssertFalse(GitClient.gitVersionAtLeast("2.34.1", major: 2, minor: 35))
    }

    func testGitVersionAtLeastParsesFullGitVersionOutputWithVendorSuffix() {
        XCTAssertTrue(GitClient.gitVersionAtLeast("git version 2.50.1 (Apple Git-155)", major: 2, minor: 35))
    }

    func testGitVersionAtLeastAcceptsNewerMajorVersion() {
        XCTAssertTrue(GitClient.gitVersionAtLeast("3.0.0", major: 2, minor: 35))
    }

    func testGitVersionAtLeastRejectsMalformedInput() {
        XCTAssertFalse(GitClient.gitVersionAtLeast("not a version", major: 2, minor: 35))
    }

    func testGitVersionAtLeastRejectsEmptyInput() {
        XCTAssertFalse(GitClient.gitVersionAtLeast("", major: 2, minor: 35))
    }
}
