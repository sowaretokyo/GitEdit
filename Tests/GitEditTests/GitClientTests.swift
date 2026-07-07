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

    // MARK: - parseRecentCommits (%P parsing / Commit.isMerge)

    private func makeCommitRecord(
        sha: String, subject: String, parents: String, body: String? = nil
    ) -> String {
        let US = GitClient.recentCommitsFieldSeparator
        let RS = GitClient.recentCommitsRecordSeparator
        let fullBody = body ?? subject
        return "\(sha)\(US)\(String(sha.prefix(7)))\(US)2026-01-15T10:00:00+09:00\(US)Test\(US)test@example.com\(US)\(subject)\(US)\(parents)\(US)\(fullBody)\(RS)"
    }

    func testParseRecentCommitsWithNoParentsIsNotAMerge() {
        let output = makeCommitRecord(sha: "aaa111", subject: "initial commit", parents: "")
        let commits = GitClient.parseRecentCommits(output)
        XCTAssertEqual(commits.count, 1)
        XCTAssertFalse(commits[0].isMerge)
    }

    func testParseRecentCommitsWithOneParentIsNotAMerge() {
        let output = makeCommitRecord(sha: "bbb222", subject: "normal commit", parents: "aaa111")
        let commits = GitClient.parseRecentCommits(output)
        XCTAssertEqual(commits.count, 1)
        XCTAssertFalse(commits[0].isMerge)
    }

    func testParseRecentCommitsWithTwoParentsIsAMerge() {
        let output = makeCommitRecord(sha: "ccc333", subject: "Merge branch 'foo'", parents: "bbb222 ddd444")
        let commits = GitClient.parseRecentCommits(output)
        XCTAssertEqual(commits.count, 1)
        XCTAssertTrue(commits[0].isMerge)
    }

    func testParseRecentCommitsPreservesOrderAcrossMultipleRecords() {
        let output = makeCommitRecord(sha: "ccc333", subject: "newest", parents: "bbb222")
            + makeCommitRecord(sha: "bbb222", subject: "oldest", parents: "")
        let commits = GitClient.parseRecentCommits(output)
        XCTAssertEqual(commits.map(\.id), ["ccc333", "bbb222"])
        XCTAssertEqual(commits.map(\.summary), ["newest", "oldest"])
    }
}
