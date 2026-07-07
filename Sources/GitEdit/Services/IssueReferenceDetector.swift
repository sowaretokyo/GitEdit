import Foundation

/// A `#123`-style issue/PR reference found inside a commit message.
struct IssueReference: Equatable {
    let number: Int
    /// The full token range, including the leading `#`.
    let range: Range<String.Index>
}

/// Detects issue references in commit messages and branch names.
enum IssueReferenceDetector {
    /// Matches `#123` when it isn't glued to other word characters on either
    /// side, so `abc#12`, `#12a`, `#0`, and `#012` are all excluded.
    private static let messageRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?<![0-9A-Za-z_])#([1-9][0-9]*)(?![0-9A-Za-z_])"#
    )

    static func references(inMessage text: String) -> [IssueReference] {
        guard let messageRegex, !text.isEmpty else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        var result: [IssueReference] = []
        for match in messageRegex.matches(in: text, range: nsRange) {
            guard match.numberOfRanges == 2,
                  let fullRange = Range(match.range(at: 0), in: text),
                  let numberRange = Range(match.range(at: 1), in: text),
                  let number = Int(text[numberRange]) else { continue }
            result.append(IssueReference(number: number, range: fullRange))
        }
        return result
    }

    // MARK: - Branch name detection
    //
    // Tried in priority order; the first pattern to match wins.

    /// `#123` anywhere in the branch name (e.g. `feature/#123`).
    private static let branchHashRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"#([1-9][0-9]*)"#
    )
    /// `issue-123`, `issue_123`, `issue/123`, or `issue123` (case-insensitive).
    private static let branchIssueWordRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)issue[-_/]?([1-9][0-9]*)"#
    )
    /// A number at the start of a path segment immediately followed by `-`
    /// or `_`, e.g. `123-fix-bug` or `feature/123_fix`. Requiring the
    /// trailing separator keeps this from misfiring on version-like names
    /// such as `release/2.0.1` or `v2`.
    private static let branchLeadingNumberRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:^|/)([1-9][0-9]*)[-_]"#
    )

    static func issueNumber(inBranch branch: String) -> Int? {
        for regex in [branchHashRegex, branchIssueWordRegex, branchLeadingNumberRegex] {
            if let number = firstNumber(regex, in: branch) {
                return number
            }
        }
        return nil
    }

    private static func firstNumber(_ regex: NSRegularExpression?, in text: String) -> Int? {
        guard let regex, !text.isEmpty else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges == 2,
              let numberRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[numberRange])
    }
}
