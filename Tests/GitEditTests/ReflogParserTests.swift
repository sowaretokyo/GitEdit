import XCTest
@testable import GitEdit

final class ReflogParserTests: XCTestCase {

    // MARK: - parse

    private func makeRecord(_ fields: [String]) -> String {
        fields.joined(separator: ReflogParser.fieldSep) + ReflogParser.recordSep
    }

    func testParseSingleEntry() {
        let record = makeRecord([
            "HEAD@{0}", "abc123def456", "abc123d", "commit: Add feature"
        ])
        let entries = ReflogParser.parse(record)
        XCTAssertEqual(entries.count, 1)
        let e = entries[0]
        XCTAssertEqual(e.selector, "HEAD@{0}")
        XCTAssertEqual(e.sha, "abc123def456")
        XCTAssertEqual(e.shortSHA, "abc123d")
        XCTAssertEqual(e.subject, "commit: Add feature")
    }

    func testParseMultipleRecords() {
        let r0 = makeRecord(["HEAD@{0}", "sha0", "sha0short", "commit: Add feature"])
        let r1 = makeRecord(["HEAD@{1}", "sha1", "sha1short", "commit (initial): Initial commit"])
        let entries = ReflogParser.parse(r0 + r1)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].selector, "HEAD@{0}")
        XCTAssertEqual(entries[1].selector, "HEAD@{1}")
        XCTAssertEqual(entries[1].subject, "commit (initial): Initial commit")
    }

    func testSubjectWithColonAndSpacesSurvives() {
        let record = makeRecord([
            "HEAD@{0}", "sha", "shortsha", "checkout: moving from feature/x: wip to main"
        ])
        let entries = ReflogParser.parse(record)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].subject, "checkout: moving from feature/x: wip to main")
    }

    func testEmptyOutputReturnsEmpty() {
        XCTAssertTrue(ReflogParser.parse("").isEmpty)
    }

    // MARK: - ReflogUndoDeriver.undoable

    private func entry(_ selector: String, sha: String, subject: String) -> ReflogEntry {
        ReflogEntry(selector: selector, sha: sha, shortSHA: String(sha.prefix(7)), subject: subject)
    }

    func testCommitIsUndoable() {
        let top = entry("HEAD@{0}", sha: "new123", subject: "commit: Add feature")
        let previous = entry("HEAD@{1}", sha: "old456", subject: "commit: Prior work")
        let op = ReflogUndoDeriver.undoable(top: top, previous: previous)
        XCTAssertEqual(op, .commit(summary: "Add feature", targetSHA: "old456"))
    }

    func testAmendIsUndoable() {
        let top = entry("HEAD@{0}", sha: "new123", subject: "commit (amend): Fixed message")
        let previous = entry("HEAD@{1}", sha: "old456", subject: "commit: Original")
        let op = ReflogUndoDeriver.undoable(top: top, previous: previous)
        XCTAssertEqual(op, .amendCommit(summary: "Fixed message", targetSHA: "old456"))
    }

    func testCommitMergeIsUndoable() {
        let top = entry("HEAD@{0}", sha: "new123", subject: "commit (merge): Merge branch 'foo'")
        let previous = entry("HEAD@{1}", sha: "old456", subject: "checkout: moving from foo to main")
        let op = ReflogUndoDeriver.undoable(top: top, previous: previous)
        XCTAssertEqual(op, .mergeCommit(summary: "Merge branch 'foo'", targetSHA: "old456"))
    }

    func testMergeFastForwardIsUndoable() {
        let top = entry("HEAD@{0}", sha: "new123", subject: "merge feature: Fast-forward")
        let previous = entry("HEAD@{1}", sha: "old456", subject: "checkout: moving from feature to main")
        let op = ReflogUndoDeriver.undoable(top: top, previous: previous)
        XCTAssertEqual(op, .mergeCommit(summary: "feature", targetSHA: "old456"))
    }

    func testMergeOrtStrategyIsUndoable() {
        let top = entry("HEAD@{0}", sha: "new123", subject: "merge feature: Merge made by the 'ort' strategy.")
        let previous = entry("HEAD@{1}", sha: "old456", subject: "checkout: moving from feature to main")
        let op = ReflogUndoDeriver.undoable(top: top, previous: previous)
        XCTAssertEqual(op, .mergeCommit(summary: "feature", targetSHA: "old456"))
    }

    func testInitialCommitIsNotUndoable() {
        let top = entry("HEAD@{0}", sha: "new123", subject: "commit (initial): Initial commit")
        let op = ReflogUndoDeriver.undoable(top: top, previous: nil)
        XCTAssertNil(op)
    }

    func testCheckoutBetweenBranchesIsUndoable() {
        let top = entry("HEAD@{0}", sha: "sha1", subject: "checkout: moving from main to feature")
        let previous = entry("HEAD@{1}", sha: "sha1", subject: "commit: something")
        let op = ReflogUndoDeriver.undoable(top: top, previous: previous)
        XCTAssertEqual(op, .branchSwitch(from: "main", to: "feature"))
    }

    func testCheckoutFromDetachedSHAIsNotUndoable() {
        let sha40 = String(repeating: "a", count: 40)
        let top = entry("HEAD@{0}", sha: "sha1", subject: "checkout: moving from \(sha40) to main")
        let op = ReflogUndoDeriver.undoable(top: top, previous: nil)
        XCTAssertNil(op)
    }

    func testResetIsNotUndoable() {
        let top = entry("HEAD@{0}", sha: "sha1", subject: "reset: moving to HEAD~1")
        let previous = entry("HEAD@{1}", sha: "sha0", subject: "commit: something")
        let op = ReflogUndoDeriver.undoable(top: top, previous: previous)
        XCTAssertNil(op)
    }

    func testPullIsNotUndoable() {
        let top = entry("HEAD@{0}", sha: "sha1", subject: "pull: Fast-forward")
        let previous = entry("HEAD@{1}", sha: "sha0", subject: "commit: something")
        let op = ReflogUndoDeriver.undoable(top: top, previous: previous)
        XCTAssertNil(op)
    }

    func testCommitWithNoPreviousIsNotUndoable() {
        let top = entry("HEAD@{0}", sha: "sha1", subject: "commit: only commit")
        let op = ReflogUndoDeriver.undoable(top: top, previous: nil)
        XCTAssertNil(op)
    }

    func testAmendWithNoPreviousIsNotUndoable() {
        let top = entry("HEAD@{0}", sha: "sha1", subject: "commit (amend): only commit")
        let op = ReflogUndoDeriver.undoable(top: top, previous: nil)
        XCTAssertNil(op)
    }

    func testMergeWithNoPreviousIsNotUndoable() {
        let top = entry("HEAD@{0}", sha: "sha1", subject: "merge feature: Fast-forward")
        let op = ReflogUndoDeriver.undoable(top: top, previous: nil)
        XCTAssertNil(op)
    }

    // MARK: - UndoableOperation flags

    func testOnlyMergeCommitRequiresHardReset() {
        XCTAssertTrue(UndoableOperation.mergeCommit(summary: "x", targetSHA: "s").requiresHardReset)
        XCTAssertFalse(UndoableOperation.commit(summary: "x", targetSHA: "s").requiresHardReset)
        XCTAssertFalse(UndoableOperation.amendCommit(summary: "x", targetSHA: "s").requiresHardReset)
        XCTAssertFalse(UndoableOperation.branchSwitch(from: "a", to: "b").requiresHardReset)
    }

    func testBranchSwitchIsNotResetBased() {
        XCTAssertFalse(UndoableOperation.branchSwitch(from: "a", to: "b").isResetBased)
        XCTAssertTrue(UndoableOperation.commit(summary: "x", targetSHA: "s").isResetBased)
        XCTAssertTrue(UndoableOperation.amendCommit(summary: "x", targetSHA: "s").isResetBased)
        XCTAssertTrue(UndoableOperation.mergeCommit(summary: "x", targetSHA: "s").isResetBased)
    }

    func testEditHistoryIsResetBasedAndRequiresHardReset() {
        let op = UndoableOperation.editHistory(summary: "メッセージ編集", targetSHA: "s")
        XCTAssertTrue(op.isResetBased)
        XCTAssertTrue(op.requiresHardReset)
    }
}
