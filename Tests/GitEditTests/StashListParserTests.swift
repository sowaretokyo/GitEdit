import XCTest
@testable import GitEdit

final class StashListParserTests: XCTestCase {

    // MARK: - parseIndex

    func testParseIndexDirect() {
        XCTAssertEqual(StashListParser.parseIndex("stash@{0}"), 0)
        XCTAssertEqual(StashListParser.parseIndex("stash@{12}"), 12)
        XCTAssertNil(StashListParser.parseIndex("not-a-selector"))
    }

    // MARK: - parse

    private func makeLine(_ fields: [String]) -> String {
        fields.joined(separator: StashListParser.fieldSep)
    }

    func testParseSingleEntry() {
        let line = makeLine([
            "stash@{0}", "abc123def456", "2 hours ago", "On develop: wip changes"
        ])
        let entries = StashListParser.parse(line)
        XCTAssertEqual(entries.count, 1)
        let e = entries[0]
        XCTAssertEqual(e.selector, "stash@{0}")
        XCTAssertEqual(e.index, 0)
        XCTAssertEqual(e.sha, "abc123def456")
        XCTAssertEqual(e.relativeDate, "2 hours ago")
        XCTAssertEqual(e.message, "On develop: wip changes")
    }

    func testMessageWithColonAndSpacesSurvives() {
        let line = makeLine([
            "stash@{0}", "sha1", "3 days ago", "On feature/x: fix: handle edge case: done"
        ])
        let entries = StashListParser.parse(line)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].message, "On feature/x: fix: handle edge case: done")
    }

    func testMultipleEntriesPreserveIndexOrder() {
        let l1 = makeLine(["stash@{0}", "sha0", "1 hour ago", "WIP on main: aaa"])
        let l2 = makeLine(["stash@{1}", "sha1", "1 day ago", "WIP on main: bbb"])
        let entries = StashListParser.parse([l1, l2].joined(separator: "\n"))
        XCTAssertEqual(entries.map(\.index), [0, 1])
        XCTAssertEqual(entries.map(\.sha), ["sha0", "sha1"])
    }

    func testEmptyOutputReturnsEmpty() {
        XCTAssertTrue(StashListParser.parse("").isEmpty)
    }

    func testMalformedLineIsSkipped() {
        // Only two fields instead of four.
        let broken = "stash@{0}\u{1F}onlyonefield"
        XCTAssertTrue(StashListParser.parse(broken).isEmpty)
    }

    func testMalformedLineSkippedAmongValidOnes() {
        let valid = makeLine(["stash@{0}", "sha0", "1 hour ago", "WIP on main: aaa"])
        let broken = "stash@{1}\u{1F}onlyonefield"
        let entries = StashListParser.parse([valid, broken].joined(separator: "\n"))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].sha, "sha0")
    }

    func testDoubleDigitIndex() {
        let line = makeLine(["stash@{12}", "sha12", "2 weeks ago", "WIP"])
        let entries = StashListParser.parse(line)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].index, 12)
    }
}
