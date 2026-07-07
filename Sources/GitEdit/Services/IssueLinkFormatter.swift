import Foundation
import SwiftUI

/// Renders commit message text with `#123`-style issue references turned
/// into tappable links to the corresponding GitHub issue.
enum IssueLinkFormatter {
    /// - Parameters:
    ///   - text: The plain commit message (summary or body).
    ///   - repo: The GitHub repository to link into. When `nil` (no
    ///     recognized GitHub remote), the text is returned unlinked.
    static func attributedMessage(_ text: String, repo: GitHubRepositoryRef?) -> AttributedString {
        var attr = AttributedString(text)
        guard let repo else { return attr }
        for reference in IssueReferenceDetector.references(inMessage: text) {
            guard let range = Range(reference.range, in: attr) else { continue }
            attr[range].link = repo.issueURL(reference.number)
        }
        return attr
    }
}
