import XCTest
@testable import GitEdit

/// Pure-logic tests for `CommitHistoryEditor.buildPlan` / `rowEditability`.
/// Fixtures use letter labels (E = HEAD/newest … A = oldest) instead of real
/// SHAs since the planner only ever compares/copies strings.
final class CommitHistoryEditorTests: XCTestCase {

    /// E (HEAD) D C B A (oldest of this 5-commit sample).
    private let fiveCommits = ["E", "D", "C", "B", "A"]

    // MARK: - buildPlan: reword / drop

    func testRewordBuildsRewordLineAndBaseFromParent() throws {
        let plan = try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 2, operation: .reword, isFullHistoryLoaded: false
        )
        XCTAssertEqual(plan.base, .sha("B"))
        XCTAssertEqual(plan.todoLines, ["reword C", "pick D", "pick E"])
        XCTAssertTrue(plan.needsMessage)
    }

    func testDropBuildsDropLineAndBaseFromParent() throws {
        let plan = try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 3, operation: .drop, isFullHistoryLoaded: false
        )
        XCTAssertEqual(plan.base, .sha("A"))
        XCTAssertEqual(plan.todoLines, ["drop B", "pick C", "pick D", "pick E"])
        XCTAssertFalse(plan.needsMessage)
    }

    func testDropAtRootUsesRootBaseWhenFullHistoryLoaded() throws {
        let plan = try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 4, operation: .drop, isFullHistoryLoaded: true
        )
        XCTAssertEqual(plan.base, .root)
        XCTAssertEqual(plan.todoLines, ["drop A", "pick B", "pick C", "pick D", "pick E"])
    }

    func testDropAtTruncationBoundaryThrowsHistoryNotLoaded() {
        XCTAssertThrowsError(try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 4, operation: .drop, isFullHistoryLoaded: false
        )) { error in
            XCTAssertEqual(error as? CommitHistoryEditor.PlanError, .historyNotLoaded)
        }
    }

    // MARK: - buildPlan: squash into previous

    func testSquashBuildsSquashLineWithPickForOlderAndNewerCommits() throws {
        let plan = try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 1, operation: .squashIntoPrevious, isFullHistoryLoaded: false
        )
        XCTAssertEqual(plan.base, .sha("B"))
        // "続きあり": E (newer than the squash target) still gets a plain pick.
        XCTAssertEqual(plan.todoLines, ["pick C", "squash D", "pick E"])
        XCTAssertTrue(plan.needsMessage)
    }

    func testSquashAtRootUsesRootBaseWhenFullHistoryLoaded() throws {
        let plan = try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 3, operation: .squashIntoPrevious, isFullHistoryLoaded: true
        )
        XCTAssertEqual(plan.base, .root)
        XCTAssertEqual(plan.todoLines, ["pick A", "squash B", "pick C", "pick D", "pick E"])
    }

    func testSquashOnOldestLoadedCommitThrowsNoPreviousCommit() {
        XCTAssertThrowsError(try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 4, operation: .squashIntoPrevious, isFullHistoryLoaded: true
        )) { error in
            XCTAssertEqual(error as? CommitHistoryEditor.PlanError, .noPreviousCommitToSquashInto)
        }
    }

    // MARK: - buildPlan: reorder (moveUp / moveDown)

    func testMoveUpSwapsWithNewerNeighbor() throws {
        let plan = try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 2, operation: .moveUp, isFullHistoryLoaded: false
        )
        XCTAssertEqual(plan.base, .sha("B"))
        XCTAssertEqual(plan.todoLines, ["pick D", "pick C", "pick E"])
        XCTAssertFalse(plan.needsMessage)
    }

    func testMoveUpAtHeadThrowsNoCommitAbove() {
        XCTAssertThrowsError(try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 0, operation: .moveUp, isFullHistoryLoaded: true
        )) { error in
            XCTAssertEqual(error as? CommitHistoryEditor.PlanError, .noCommitAbove)
        }
    }

    func testMoveDownSwapsWithOlderNeighbor() throws {
        // Moving D down one slot swaps the same pair as moving C up, above.
        let plan = try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 1, operation: .moveDown, isFullHistoryLoaded: false
        )
        XCTAssertEqual(plan.base, .sha("B"))
        XCTAssertEqual(plan.todoLines, ["pick D", "pick C", "pick E"])
    }

    func testMoveDownAtOldestLoadedThrowsNoCommitBelowRegardlessOfFullHistoryFlag() {
        for isFullHistoryLoaded in [true, false] {
            XCTAssertThrowsError(try CommitHistoryEditor.buildPlan(
                commitsNewestFirst: fiveCommits, targetIndex: 4, operation: .moveDown, isFullHistoryLoaded: isFullHistoryLoaded
            )) { error in
                XCTAssertEqual(error as? CommitHistoryEditor.PlanError, .noCommitBelow)
            }
        }
    }

    func testTargetIndexOutOfRangeThrows() {
        XCTAssertThrowsError(try CommitHistoryEditor.buildPlan(
            commitsNewestFirst: fiveCommits, targetIndex: 5, operation: .reword, isFullHistoryLoaded: true
        )) { error in
            XCTAssertEqual(error as? CommitHistoryEditor.PlanError, .targetIndexOutOfRange)
        }
    }

    // MARK: - rowEditability

    private func makeCommit(_ id: String, isMerge: Bool = false) -> Commit {
        Commit(
            id: id, shortSHA: String(id.prefix(7)), summary: "summary \(id)", body: "summary \(id)",
            author: "Test", authorEmail: "test@example.com", date: Date(), coAuthors: [], isMerge: isMerge
        )
    }

    func testRowEditabilityAllEnabledWhenEverythingIsCleanAndUnpushed() {
        let commits = fiveCommits.map { makeCommit($0) }
        let unpushed = Set(fiveCommits)
        let editability = CommitHistoryEditor.rowEditability(
            commits: commits, targetIndex: 2, unpushedSHAs: unpushed, isFullHistoryLoaded: true
        )
        XCTAssertEqual(editability, CommitHistoryEditor.RowEditability(
            canReword: true, canSquashIntoPrevious: true, canMoveUp: true, canMoveDown: true, canDrop: true
        ))
    }

    func testRowEditabilityDisablesOnlyActionsWhosePushedRangeReachesTheTarget() {
        // B (index 3) is already pushed. Reword/drop/moveUp only touch
        // index...targetIndex, so they're unaffected for target C (index 2);
        // squash/moveDown reach one commit further (into B) and get blocked.
        let commits = fiveCommits.map { makeCommit($0) }
        let unpushed = Set(fiveCommits).subtracting(["B"])
        let editability = CommitHistoryEditor.rowEditability(
            commits: commits, targetIndex: 2, unpushedSHAs: unpushed, isFullHistoryLoaded: true
        )
        XCTAssertTrue(editability.canReword)
        XCTAssertTrue(editability.canDrop)
        XCTAssertTrue(editability.canMoveUp)
        XCTAssertFalse(editability.canSquashIntoPrevious)
        XCTAssertFalse(editability.canMoveDown)
    }

    func testRowEditabilityDisablesOnlyActionsWhoseRangeReachesAMergeCommit() {
        // Same shape as the pushed-range test above, but via a merge commit.
        var commits = fiveCommits.map { makeCommit($0) }
        commits[3] = makeCommit("B", isMerge: true)
        let editability = CommitHistoryEditor.rowEditability(
            commits: commits, targetIndex: 2, unpushedSHAs: Set(fiveCommits), isFullHistoryLoaded: true
        )
        XCTAssertTrue(editability.canReword)
        XCTAssertTrue(editability.canDrop)
        XCTAssertTrue(editability.canMoveUp)
        XCTAssertFalse(editability.canSquashIntoPrevious)
        XCTAssertFalse(editability.canMoveDown)
    }

    func testRowEditabilityAtTruncationBoundaryDisablesEverything() {
        // Oldest loaded commit, but the window might just be truncated there
        // (not necessarily the repo's actual root) — disable rather than guess.
        let commits = fiveCommits.map { makeCommit($0) }
        let editability = CommitHistoryEditor.rowEditability(
            commits: commits, targetIndex: 4, unpushedSHAs: Set(fiveCommits), isFullHistoryLoaded: false
        )
        XCTAssertEqual(editability, .allDisabled)
    }

    func testRowEditabilityAtConfirmedRootEnablesRewordDropAndMoveUpButNotSquashOrMoveDown() {
        // Same oldest-loaded commit, but now confirmed to be the actual root:
        // reword/drop/moveUp are fine (there's nothing wrong with rewriting
        // or promoting the root commit itself — it still has a newer
        // neighbor to swap with); squash/moveDown have no earlier commit to
        // interact with, full stop, regardless of the root confirmation.
        let commits = fiveCommits.map { makeCommit($0) }
        let editability = CommitHistoryEditor.rowEditability(
            commits: commits, targetIndex: 4, unpushedSHAs: Set(fiveCommits), isFullHistoryLoaded: true
        )
        XCTAssertTrue(editability.canReword)
        XCTAssertTrue(editability.canDrop)
        XCTAssertTrue(editability.canMoveUp)
        XCTAssertFalse(editability.canSquashIntoPrevious)
        XCTAssertFalse(editability.canMoveDown)
    }

    func testRowEditabilityAtHeadDisablesMoveUpOnly() {
        let commits = fiveCommits.map { makeCommit($0) }
        let editability = CommitHistoryEditor.rowEditability(
            commits: commits, targetIndex: 0, unpushedSHAs: Set(fiveCommits), isFullHistoryLoaded: true
        )
        XCTAssertTrue(editability.canReword)
        XCTAssertTrue(editability.canDrop)
        XCTAssertFalse(editability.canMoveUp)
        XCTAssertTrue(editability.canMoveDown)
        XCTAssertTrue(editability.canSquashIntoPrevious)
    }

    func testRowEditabilityOutOfRangeIndexReturnsAllDisabled() {
        let commits = fiveCommits.map { makeCommit($0) }
        let editability = CommitHistoryEditor.rowEditability(
            commits: commits, targetIndex: 99, unpushedSHAs: Set(fiveCommits), isFullHistoryLoaded: true
        )
        XCTAssertEqual(editability, .allDisabled)
    }
}
