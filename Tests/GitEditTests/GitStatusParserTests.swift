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

    func testUnmergedConflictEntry() {
        let output = "UU conflict.txt\u{0}"
        let result = GitStatusParser.parse(porcelainV1Z: output)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].indexStatus, "U")
        XCTAssertEqual(result[0].workingStatus, "U")
        XCTAssertNil(result[0].renameFrom)
        XCTAssertTrue(result[0].isConflicted)
    }

    func testAddAddConflictEntryDoesNotConsumeNextField() {
        // Regression guard: only R/C entries consume a second NUL field (the
        // rename source). AA is a conflict state, not a rename, and must not
        // swallow the following "M  next.swift" entry.
        let output = "AA both.txt\u{0}M  next.swift\u{0}"
        let result = GitStatusParser.parse(porcelainV1Z: output)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].path, "both.txt")
        XCTAssertTrue(result[0].isConflicted)
        XCTAssertEqual(result[1].path, "next.swift")
        XCTAssertEqual(result[1].indexStatus, "M")
    }
}
