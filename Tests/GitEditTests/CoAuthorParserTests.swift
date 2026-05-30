import XCTest
@testable import GitEdit

final class CoAuthorParserTests: XCTestCase {

    func testEmptyBodyYieldsNoCoAuthors() {
        XCTAssertTrue(CoAuthorParser.parse(from: "").isEmpty)
    }

    func testBodyWithoutTrailerYieldsNoCoAuthors() {
        let body = """
        Fix something.

        This is the long description.
        """
        XCTAssertTrue(CoAuthorParser.parse(from: body).isEmpty)
    }

    func testSingleCoAuthor() {
        let body = """
        feat: do a thing

        Co-Authored-By: Alice <alice@example.com>
        """
        let result = CoAuthorParser.parse(from: body)
        XCTAssertEqual(result, [CommitAuthor(name: "Alice", email: "alice@example.com")])
    }

    func testMultipleCoAuthorsPreserveOrder() {
        let body = """
        chore: refactor

        Co-Authored-By: Alice <alice@example.com>
        Co-Authored-By: Bob <bob@example.com>
        Co-Authored-By: Carol <carol@example.com>
        """
        let result = CoAuthorParser.parse(from: body)
        XCTAssertEqual(result.map(\.name), ["Alice", "Bob", "Carol"])
    }

    func testDuplicateEmailIsDeduplicatedCaseInsensitively() {
        let body = """
        x

        Co-Authored-By: Alice <alice@example.com>
        Co-Authored-By: alice <ALICE@example.com>
        """
        let result = CoAuthorParser.parse(from: body)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].email, "alice@example.com")
    }

    func testLowercaseTrailerIsAccepted() {
        let body = """
        x

        co-authored-by: Alice <alice@example.com>
        """
        let result = CoAuthorParser.parse(from: body)
        XCTAssertEqual(result.count, 1)
    }

    func testNameWithSpacesIsCaptured() {
        let body = "x\n\nCo-Authored-By: Alice Q. Doe <alice@example.com>\n"
        let result = CoAuthorParser.parse(from: body)
        XCTAssertEqual(result.first?.name, "Alice Q. Doe")
    }

    func testIndentedTrailerIsAccepted() {
        let body = "x\n\n   Co-Authored-By: Alice <a@example.com>\n"
        let result = CoAuthorParser.parse(from: body)
        XCTAssertEqual(result.first?.email, "a@example.com")
    }

    func testTrailerInlineInBodyTextIsIgnored() {
        // Not at the start of a line — must not match.
        let body = "Here is a note: Co-Authored-By: Alice <a@example.com> said so"
        XCTAssertTrue(CoAuthorParser.parse(from: body).isEmpty)
    }

    func testMalformedTrailerIsSkipped() {
        let body = """
        x

        Co-Authored-By: Alice no_brackets@example.com
        Co-Authored-By: Bob <bob@example.com>
        """
        let result = CoAuthorParser.parse(from: body)
        XCTAssertEqual(result.map(\.name), ["Bob"])
    }

    func testClaudeCodeStyleTrailer() {
        // Matches what Claude Code adds today.
        let body = """
        feat: ship it

        Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
        """
        let result = CoAuthorParser.parse(from: body)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Claude Opus 4.7 (1M context)")
        XCTAssertEqual(result[0].email, "noreply@anthropic.com")
    }
}
