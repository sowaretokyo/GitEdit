import XCTest
@testable import GitEdit

final class FileChangeTests: XCTestCase {
    private func make(_ index: Character, _ working: Character, renameFrom: String? = nil) -> FileChange {
        FileChange(path: "x", indexStatus: index, workingStatus: working, renameFrom: renameFrom)
    }

    func testCategoryModifiedFromIndex() {
        XCTAssertEqual(make("M", " ").category, .modified)
    }

    func testCategoryModifiedFromWorkingTree() {
        XCTAssertEqual(make(" ", "M").category, .modified)
    }

    func testCategoryAdded() {
        XCTAssertEqual(make("A", " ").category, .added)
    }

    func testCategoryDeleted() {
        XCTAssertEqual(make("D", " ").category, .deleted)
    }

    func testCategoryRenamed() {
        XCTAssertEqual(make("R", " ").category, .renamed)
    }

    func testCategoryCopied() {
        XCTAssertEqual(make("C", " ").category, .copied)
    }

    func testCategoryTypeChanged() {
        XCTAssertEqual(make("T", " ").category, .typeChanged)
    }

    func testCategoryUnmerged() {
        XCTAssertEqual(make("U", "U").category, .unmerged)
    }

    func testUntrackedFlag() {
        let fc = make("?", "?")
        XCTAssertTrue(fc.isUntracked)
        XCTAssertEqual(fc.category, .untracked)
    }

    func testIgnoredFlag() {
        let fc = make("!", "!")
        XCTAssertTrue(fc.isIgnored)
        XCTAssertEqual(fc.category, .ignored)
    }

    func testHasStagedAndUnstaged() {
        let fc = make("M", "M")
        XCTAssertTrue(fc.hasStagedChange)
        XCTAssertTrue(fc.hasUnstagedChange)
        XCTAssertTrue(fc.willBeCommitted)
    }

    func testStagedOnly() {
        let fc = make("M", " ")
        XCTAssertTrue(fc.hasStagedChange)
        XCTAssertFalse(fc.hasUnstagedChange)
    }

    func testUntrackedHasNoStagedChange() {
        let fc = make("?", "?")
        XCTAssertFalse(fc.hasStagedChange)
        XCTAssertTrue(fc.hasUnstagedChange)
    }

    func testPrimaryStatusSymbolPrefersIndex() {
        XCTAssertEqual(make("M", " ").primaryStatusSymbol, "M")
        XCTAssertEqual(make(" ", "M").primaryStatusSymbol, "M")
        XCTAssertEqual(make("?", "?").primaryStatusSymbol, "?")
        XCTAssertEqual(make("!", "!").primaryStatusSymbol, "!")
    }

    func testDisplayPathRenamed() {
        let fc = FileChange(
            path: "new.swift",
            indexStatus: "R",
            workingStatus: " ",
            renameFrom: "old.swift"
        )
        XCTAssertEqual(fc.displayPath, "old.swift → new.swift")
    }

    func testDisplayPathNoRename() {
        XCTAssertEqual(make("M", " ").displayPath, "x")
    }
}
