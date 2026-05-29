import XCTest
@testable import GitEdit

final class GitBranchParserTests: XCTestCase {

    // MARK: - parseAheadBehind

    func testParseAheadBehindEmpty() {
        let (a, b) = GitBranchParser.parseAheadBehind("")
        XCTAssertEqual(a, 0)
        XCTAssertEqual(b, 0)
    }

    func testParseAheadOnly() {
        let (a, b) = GitBranchParser.parseAheadBehind("[ahead 3]")
        XCTAssertEqual(a, 3)
        XCTAssertEqual(b, 0)
    }

    func testParseBehindOnly() {
        let (a, b) = GitBranchParser.parseAheadBehind("[behind 5]")
        XCTAssertEqual(a, 0)
        XCTAssertEqual(b, 5)
    }

    func testParseAheadBehindBoth() {
        let (a, b) = GitBranchParser.parseAheadBehind("[ahead 2, behind 4]")
        XCTAssertEqual(a, 2)
        XCTAssertEqual(b, 4)
    }

    func testParseAheadBehindGone() {
        let (a, b) = GitBranchParser.parseAheadBehind("[gone]")
        XCTAssertEqual(a, 0)
        XCTAssertEqual(b, 0)
    }

    // MARK: - parse

    private func makeRecord(_ fields: [String]) -> String {
        fields.joined(separator: GitBranchParser.fieldSep) + GitBranchParser.recordSep
    }

    func testParseSingleLocalBranch() {
        let record = makeRecord([
            "main", "*", "origin/main", "",
            "abc1234", "2024-01-15T10:00:00+09:00", "Alice", "Initial commit"
        ])
        let branches = GitBranchParser.parse(record, kind: .local)
        XCTAssertEqual(branches.count, 1)
        let b = branches[0]
        XCTAssertEqual(b.name, "main")
        XCTAssertTrue(b.isCurrent)
        XCTAssertEqual(b.upstream, "origin/main")
        XCTAssertEqual(b.sha, "abc1234")
        XCTAssertEqual(b.subject, "Initial commit")
        XCTAssertEqual(b.authorName, "Alice")
        XCTAssertFalse(b.upstreamGone)
        XCTAssertEqual(b.ahead, 0)
        XCTAssertEqual(b.behind, 0)
    }

    func testParseAheadBehindFromTrack() {
        let record = makeRecord([
            "feature", " ", "origin/feature", "[ahead 2, behind 1]",
            "def5678", "2024-02-01T00:00:00+00:00", "Bob", "WIP"
        ])
        let branches = GitBranchParser.parse(record, kind: .local)
        XCTAssertEqual(branches.count, 1)
        XCTAssertEqual(branches[0].ahead, 2)
        XCTAssertEqual(branches[0].behind, 1)
    }

    func testGoneUpstreamFlagsBranch() {
        let record = makeRecord([
            "stale", " ", "origin/stale", "[gone]",
            "ghi9012", "2024-01-01T00:00:00+00:00", "Carol", "Old"
        ])
        let branches = GitBranchParser.parse(record, kind: .local)
        XCTAssertTrue(branches[0].upstreamGone)
    }

    func testRemoteHEADIsSkipped() {
        let record = makeRecord([
            "origin/HEAD", " ", "", "",
            "abc", "2024-01-01T00:00:00+00:00", "X", "Y"
        ])
        XCTAssertTrue(GitBranchParser.parse(record, kind: .remote(name: "origin")).isEmpty)
    }

    func testEmptyRefnameSkipped() {
        let record = makeRecord([
            "", " ", "", "", "", "", "", ""
        ])
        XCTAssertTrue(GitBranchParser.parse(record, kind: .local).isEmpty)
    }

    func testMultipleRecords() {
        let r1 = makeRecord([
            "main", "*", "", "", "a", "2024-01-01T00:00:00+00:00", "X", "S1"
        ])
        let r2 = makeRecord([
            "dev", " ", "", "", "b", "2024-01-02T00:00:00+00:00", "Y", "S2"
        ])
        let branches = GitBranchParser.parse(r1 + r2, kind: .local)
        XCTAssertEqual(branches.map(\.name), ["main", "dev"])
    }
}
