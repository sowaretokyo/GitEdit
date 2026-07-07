import XCTest
@testable import GitEdit

final class CheckStatusDecodingTests: XCTestCase {

    func testDecodesCheckRunsResponse() throws {
        let json = """
        {
          "total_count": 2,
          "check_runs": [
            { "id": 1, "name": "build", "status": "completed", "conclusion": "success", "details_url": "https://example.com/1" },
            { "id": 2, "name": "test", "status": "in_progress", "conclusion": null, "details_url": null }
          ]
        }
        """
        let response = try JSONDecoder().decode(CheckRunsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.totalCount, 2)
        XCTAssertEqual(response.checkRuns.count, 2)
        XCTAssertEqual(response.checkRuns[0].name, "build")
        XCTAssertEqual(response.checkRuns[0].conclusion, "success")
        XCTAssertEqual(response.checkRuns[0].detailsURL, "https://example.com/1")
        XCTAssertNil(response.checkRuns[1].conclusion)
        XCTAssertNil(response.checkRuns[1].detailsURL)
    }

    func testDecodesCombinedStatusWithData() throws {
        let json = """
        {
          "state": "pending",
          "total_count": 1,
          "statuses": [
            { "context": "ci/legacy", "state": "pending", "target_url": null }
          ]
        }
        """
        let combined = try JSONDecoder().decode(CombinedStatus.self, from: Data(json.utf8))
        XCTAssertEqual(combined.state, "pending")
        XCTAssertEqual(combined.totalCount, 1)
        XCTAssertEqual(combined.statuses.count, 1)
        XCTAssertEqual(combined.statuses[0].context, "ci/legacy")
        XCTAssertNil(combined.statuses[0].targetURL)
    }

    func testDecodesEmptyCombinedStatus() throws {
        let json = """
        { "state": "success", "total_count": 0, "statuses": [] }
        """
        let combined = try JSONDecoder().decode(CombinedStatus.self, from: Data(json.utf8))
        XCTAssertEqual(combined.totalCount, 0)
        XCTAssertTrue(combined.statuses.isEmpty)
    }
}
