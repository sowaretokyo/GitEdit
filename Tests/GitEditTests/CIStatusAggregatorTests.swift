import XCTest
@testable import GitEdit

final class CIStatusAggregatorTests: XCTestCase {

    private func run(_ id: Int, status: String, conclusion: String?) -> CheckRun {
        CheckRun(id: id, name: "check-\(id)", status: status, conclusion: conclusion, detailsURL: nil)
    }

    func testAllSuccessIsOverallSuccess() {
        let runs = [
            run(1, status: "completed", conclusion: "success"),
            run(2, status: "completed", conclusion: "neutral"),
            run(3, status: "completed", conclusion: "skipped")
        ]
        let summary = CIStatusAggregator.aggregate(checkRuns: runs, combined: nil)
        XCTAssertEqual(summary.overall, .success)
        XCTAssertEqual(summary.success, 3)
        XCTAssertEqual(summary.failure, 0)
        XCTAssertEqual(summary.pending, 0)
        XCTAssertEqual(summary.total, 3)
    }

    func testOneFailureMakesOverallFailure() {
        let runs = [
            run(1, status: "completed", conclusion: "success"),
            run(2, status: "completed", conclusion: "failure")
        ]
        let summary = CIStatusAggregator.aggregate(checkRuns: runs, combined: nil)
        XCTAssertEqual(summary.overall, .failure)
        XCTAssertEqual(summary.success, 1)
        XCTAssertEqual(summary.failure, 1)
    }

    func testInProgressRunIsPending() {
        let runs = [run(1, status: "in_progress", conclusion: nil)]
        let summary = CIStatusAggregator.aggregate(checkRuns: runs, combined: nil)
        XCTAssertEqual(summary.overall, .pending)
        XCTAssertEqual(summary.pending, 1)
    }

    func testEmptyInputIsNone() {
        let summary = CIStatusAggregator.aggregate(checkRuns: [], combined: nil)
        XCTAssertEqual(summary.overall, .none)
        XCTAssertEqual(summary.total, 0)
    }

    func testMixedSuccessAndPendingIsOverallPending() {
        let runs = [
            run(1, status: "completed", conclusion: "success"),
            run(2, status: "queued", conclusion: nil)
        ]
        let summary = CIStatusAggregator.aggregate(checkRuns: runs, combined: nil)
        XCTAssertEqual(summary.overall, .pending)
        XCTAssertEqual(summary.success, 1)
        XCTAssertEqual(summary.pending, 1)
    }

    /// The GitHub-Actions-only-repo trap: the combined status endpoint
    /// reports `total_count: 0` (no legacy statuses posted at all) as state
    /// "pending" — without this guard that would force every such PR to show
    /// "pending" forever even when every real check has already passed.
    func testCombinedStatusWithZeroTotalCountIsIgnored() {
        let runs = [run(1, status: "completed", conclusion: "success")]
        let combined = CombinedStatus(state: "pending", totalCount: 0, statuses: [])
        let summary = CIStatusAggregator.aggregate(checkRuns: runs, combined: combined)
        XCTAssertEqual(summary.overall, .success)
        XCTAssertEqual(summary.total, 1)
    }

    func testCombinedStatusWithRealDataContributesToOverall() {
        let combined = CombinedStatus(state: "failure", totalCount: 1, statuses: [])
        let summary = CIStatusAggregator.aggregate(checkRuns: [], combined: combined)
        XCTAssertEqual(summary.overall, .failure)
        XCTAssertEqual(summary.failure, 1)
        XCTAssertEqual(summary.total, 1)
    }

    func testCombinedStatusErrorStateCountsAsFailure() {
        let combined = CombinedStatus(state: "error", totalCount: 1, statuses: [])
        let summary = CIStatusAggregator.aggregate(checkRuns: [], combined: combined)
        XCTAssertEqual(summary.overall, .failure)
    }
}
