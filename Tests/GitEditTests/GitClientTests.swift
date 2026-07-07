import XCTest
@testable import GitEdit

final class GitClientTests: XCTestCase {

    private let sep = "\u{1F}"

    func testParseHeadMessageWithSubjectOnly() {
        let raw = "Fix the login bug\(sep)"
        let result = GitClient.parseHeadMessage(raw, separator: sep)
        XCTAssertEqual(result?.summary, "Fix the login bug")
        XCTAssertEqual(result?.body, "")
    }

    func testParseHeadMessageWithSubjectAndMultiLineBody() {
        let raw = "Fix the login bug\(sep)This addresses a regression\nintroduced in the last release.\n"
        let result = GitClient.parseHeadMessage(raw, separator: sep)
        XCTAssertEqual(result?.summary, "Fix the login bug")
        XCTAssertEqual(result?.body, "This addresses a regression\nintroduced in the last release.")
    }

    func testParseHeadMessageWithEmptyString() {
        let result = GitClient.parseHeadMessage("", separator: sep)
        XCTAssertEqual(result?.summary, "")
        XCTAssertEqual(result?.body, "")
    }
}
