import XCTest
@testable import GitEdit

final class GitStatusParserTests: XCTestCase {
    func testEmptyOutput() {
        XCTAssertTrue(GitStatusParser.parse(porcelainV1Z: "").isEmpty)
    }

    func testSingleModified() {
        // porcelain v1 -z format: "XY<space>path\0"
        let output = "M  src/foo.swift\u{0}"
        let result = GitStatusParser.parse(porcelainV1Z: output)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "src/foo.swift")
        XCTAssertEqual(result[0].indexStatus, "M")
        XCTAssertEqual(result[0].workingStatus, " ")
        XCTAssertNil(result[0].renameFrom)
    }

    func testWorkingTreeOnlyModified() {
        let output = " M src/foo.swift\u{0}"
        let result = GitStatusParser.parse(porcelainV1Z: output)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].indexStatus, " ")
        XCTAssertEqual(result[0].workingStatus, "M")
        XCTAssertTrue(result[0].hasUnstagedChange)
        XCTAssertFalse(result[0].hasStagedChange)
    }

    func testUntracked() {
        let output = "?? new_file.txt\u{0}"
        let result = GitStatusParser.parse(porcelainV1Z: output)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isUntracked)
        XCTAssertEqual(result[0].path, "new_file.txt")
    }

    func testRenameProducesRenameFrom() {
        // R<space><space>new\0old\0
        let output = "R  new.swift\u{0}old.swift\u{0}"
        let result = GitStatusParser.parse(porcelainV1Z: output)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].path, "new.swift")
        XCTAssertEqual(result[0].renameFrom, "old.swift")
        XCTAssertEqual(result[0].category, .renamed)
    }

    func testMultipleEntriesPreserveOrder() {
        let output = "M  a.swift\u{0}A  b.swift\u{0}?? c.txt\u{0}"
        let result = GitStatusParser.parse(porcelainV1Z: output)
        XCTAssertEqual(result.map(\.path), ["a.swift", "b.swift", "c.txt"])
    }

    func testPathContainingSpaces() {
        // -z makes paths NUL-delimited, so internal spaces survive untouched.
        let output = "M  path with spaces.txt\u{0}"
        let result = GitStatusParser.parse(porcelainV1Z: output)
        XCTAssertEqual(result.first?.path, "path with spaces.txt")
    }

    func testShortEntryIgnored() {
        // Entries under 3 chars cannot encode XY + space; skipped.
        let output = "M\u{0}"
        XCTAssertTrue(GitStatusParser.parse(porcelainV1Z: output).isEmpty)
    }
}
