import XCTest
@testable import GitEdit

final class AvatarHashTests: XCTestCase {

    // MARK: - initials

    func testInitialsTwoWords() {
        XCTAssertEqual(AvatarHash.initials(for: "Alice Doe"), "AD")
    }

    func testInitialsThreeWordsUsesFirstTwo() {
        XCTAssertEqual(AvatarHash.initials(for: "Alice B Carol"), "AB")
    }

    func testInitialsOneWord() {
        XCTAssertEqual(AvatarHash.initials(for: "alice"), "A")
    }

    func testInitialsEmpty() {
        XCTAssertEqual(AvatarHash.initials(for: ""), "")
    }

    func testInitialsWhitespaceOnly() {
        XCTAssertEqual(AvatarHash.initials(for: "   "), "")
    }

    func testInitialsJapanese() {
        // "森江 遼" → split on whitespace, take first char of each → "森遼"
        XCTAssertEqual(AvatarHash.initials(for: "森江 遼"), "森遼")
    }

    func testInitialsHandlesTabsAndMultipleSpaces() {
        XCTAssertEqual(AvatarHash.initials(for: "Alice\t\tDoe"), "AD")
        XCTAssertEqual(AvatarHash.initials(for: "  Alice   Doe  "), "AD")
    }

    // MARK: - hue

    func testHueIsInUnitRange() {
        for seed in ["alice", "bob@example.com", "x", ""] {
            let h = AvatarHash.hue(for: seed)
            XCTAssertGreaterThanOrEqual(h, 0)
            XCTAssertLessThan(h, 1)
        }
    }

    func testHueDeterministicWithinRun() {
        // Hash values aren't stable across runs but are stable within one.
        XCTAssertEqual(
            AvatarHash.hue(for: "user@example.com"),
            AvatarHash.hue(for: "user@example.com")
        )
    }
}
