import XCTest
@testable import GitEdit

final class PullRequestMergeabilityTests: XCTestCase {

    private func makePR(
        state: String = "open",
        isDraft: Bool = false,
        merged: Bool? = false,
        mergeable: Bool? = true,
        mergeableState: String? = "clean"
    ) -> PullRequest {
        let branch = PullRequestBranchRef(ref: "feature", sha: "abc123", label: "owner:feature", repo: nil)
        return PullRequest(
            number: 1,
            title: "Test PR",
            state: state,
            isDraft: isDraft,
            body: nil,
            htmlURL: "https://github.com/owner/repo/pull/1",
            user: nil,
            head: branch,
            base: branch,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            merged: merged,
            mergeable: mergeable,
            mergeableState: mergeableState
        )
    }

    func testAlreadyMergedBlocksMerge() {
        let pr = makePR(merged: true)
        let readiness = PullRequestMergeability.evaluate(pr: pr, ci: .success)
        XCTAssertFalse(readiness.canMerge)
        XCTAssertEqual(readiness.reason, .alreadyMerged)
    }

    func testClosedBlocksMerge() {
        let pr = makePR(state: "closed", merged: false)
        let readiness = PullRequestMergeability.evaluate(pr: pr, ci: .success)
        XCTAssertFalse(readiness.canMerge)
        XCTAssertEqual(readiness.reason, .closed)
    }

    func testDraftBlocksMerge() {
        let pr = makePR(isDraft: true)
        let readiness = PullRequestMergeability.evaluate(pr: pr, ci: .success)
        XCTAssertFalse(readiness.canMerge)
        XCTAssertEqual(readiness.reason, .draft)
    }

    func testConflictsBlockMerge() {
        let pr = makePR(mergeable: false, mergeableState: "dirty")
        let readiness = PullRequestMergeability.evaluate(pr: pr, ci: .success)
        XCTAssertFalse(readiness.canMerge)
        XCTAssertEqual(readiness.reason, .conflicts)
    }

    func testComputingBlocksMerge() {
        let pr = makePR(mergeable: nil, mergeableState: "unknown")
        let readiness = PullRequestMergeability.evaluate(pr: pr, ci: .success)
        XCTAssertFalse(readiness.canMerge)
        XCTAssertEqual(readiness.reason, .computing)
    }

    func testBranchProtectionBlocksMerge() {
        let pr = makePR(mergeable: true, mergeableState: "blocked")
        let readiness = PullRequestMergeability.evaluate(pr: pr, ci: .success)
        XCTAssertFalse(readiness.canMerge)
        XCTAssertEqual(readiness.reason, .blocked)
    }

    func testCleanStateAllowsMerge() {
        let pr = makePR(mergeable: true, mergeableState: "clean")
        let readiness = PullRequestMergeability.evaluate(pr: pr, ci: .success)
        XCTAssertTrue(readiness.canMerge)
        XCTAssertNil(readiness.reason)
        XCTAssertFalse(readiness.ciWarning)
    }

    func testFailingCIDoesNotBlockMergeButSetsWarning() {
        let pr = makePR(mergeable: true, mergeableState: "clean")
        let readiness = PullRequestMergeability.evaluate(pr: pr, ci: .failure)
        XCTAssertTrue(readiness.canMerge)
        XCTAssertNil(readiness.reason)
        XCTAssertTrue(readiness.ciWarning)
    }

    func testAlreadyMergedTakesPriorityOverDraft() {
        // Ordering check: a merged PR should never surface as "draft" even
        // if some inconsistent combination of fields were returned.
        let pr = makePR(isDraft: true, merged: true)
        let readiness = PullRequestMergeability.evaluate(pr: pr, ci: .success)
        XCTAssertEqual(readiness.reason, .alreadyMerged)
    }
}
