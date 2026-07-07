import XCTest
import SwiftUI
@testable import GitEdit

final class IssueLinkFormatterTests: XCTestCase {

    private let repo = GitHubRepositoryRef(owner: "owner", repo: "repo")

    private func linkRuns(_ attr: AttributedString) -> [URL] {
        attr.runs.compactMap { $0.link }
    }

    func testLinkRunCountAndURLsMatchReferences() {
        let text = "fixes #1 and refs #23"
        let attr = IssueLinkFormatter.attributedMessage(text, repo: repo)
        let urls = linkRuns(attr)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls[0].absoluteString, "https://github.com/owner/repo/issues/1")
        XCTAssertEqual(urls[1].absoluteString, "https://github.com/owner/repo/issues/23")
    }

    func testNilRepoProducesNoLinkRuns() {
        let attr = IssueLinkFormatter.attributedMessage("fixes #1", repo: nil)
        XCTAssertTrue(linkRuns(attr).isEmpty)
    }

    func testNoReferencesProducesNoLinkRuns() {
        let attr = IssueLinkFormatter.attributedMessage("just a plain message", repo: repo)
        XCTAssertTrue(linkRuns(attr).isEmpty)
    }
}
