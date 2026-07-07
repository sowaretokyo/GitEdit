import XCTest
@testable import GitEdit

final class IssueReferenceDetectorTests: XCTestCase {

    // MARK: - references(inMessage:)

    func testSingleReference() {
        let refs = IssueReferenceDetector.references(inMessage: "fix: crash on launch #42")
        XCTAssertEqual(refs.map(\.number), [42])
    }

    func testMultipleReferencesPreserveOrderAndRanges() {
        let text = "fixes #1 and refs #23"
        let refs = IssueReferenceDetector.references(inMessage: text)
        XCTAssertEqual(refs.map(\.number), [1, 23])
        XCTAssertEqual(refs.map { String(text[$0.range]) }, ["#1", "#23"])
    }

    func testNoReferences() {
        XCTAssertTrue(IssueReferenceDetector.references(inMessage: "just a normal commit message").isEmpty)
    }

    func testHashZeroExcluded() {
        XCTAssertTrue(IssueReferenceDetector.references(inMessage: "see #0 for context").isEmpty)
    }

    func testLeadingZeroExcluded() {
        XCTAssertTrue(IssueReferenceDetector.references(inMessage: "see #012 for context").isEmpty)
    }

    func testWordGluedBeforeHashExcluded() {
        XCTAssertTrue(IssueReferenceDetector.references(inMessage: "abc#12").isEmpty)
    }

    func testWordGluedAfterNumberExcluded() {
        XCTAssertTrue(IssueReferenceDetector.references(inMessage: "#12a").isEmpty)
    }

    func testReferenceInParenthesesMatches() {
        let refs = IssueReferenceDetector.references(inMessage: "closes (#12).")
        XCTAssertEqual(refs.map(\.number), [12])
    }

    // MARK: - issueNumber(inBranch:)

    func testBranchLeadingNumberWithDash() {
        XCTAssertEqual(IssueReferenceDetector.issueNumber(inBranch: "123-foo"), 123)
    }

    func testBranchLeadingNumberInPathSegment() {
        XCTAssertEqual(IssueReferenceDetector.issueNumber(inBranch: "feature/123-foo"), 123)
    }

    func testBranchIssueWordWithDash() {
        XCTAssertEqual(IssueReferenceDetector.issueNumber(inBranch: "issue-123"), 123)
    }

    func testBranchIssueWordWithSlash() {
        XCTAssertEqual(IssueReferenceDetector.issueNumber(inBranch: "issue/123"), 123)
    }

    func testBranchIssueWordCaseInsensitive() {
        XCTAssertEqual(IssueReferenceDetector.issueNumber(inBranch: "ISSUE-99"), 99)
    }

    func testBranchHashInPathSegment() {
        XCTAssertEqual(IssueReferenceDetector.issueNumber(inBranch: "feature/#123"), 123)
    }

    func testBranchHashOnly() {
        XCTAssertEqual(IssueReferenceDetector.issueNumber(inBranch: "#45"), 45)
    }

    func testBranchWithoutNumberReturnsNil() {
        XCTAssertNil(IssueReferenceDetector.issueNumber(inBranch: "main"))
    }

    func testBranchVersionLikeNameReturnsNil() {
        XCTAssertNil(IssueReferenceDetector.issueNumber(inBranch: "release/2.0.1"))
    }

    func testBranchVShorthandReturnsNil() {
        XCTAssertNil(IssueReferenceDetector.issueNumber(inBranch: "v2"))
    }

    func testBranchVersionRCReturnsNil() {
        XCTAssertNil(IssueReferenceDetector.issueNumber(inBranch: "2.0-rc"))
    }
}
