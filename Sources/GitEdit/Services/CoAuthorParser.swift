import Foundation

/// Extracts `Co-Authored-By: Name <email>` trailers from a commit body.
///
/// Per git convention these live on their own line at the bottom of the
/// commit body, but we scan the whole body — duplicate entries are folded
/// by email (case-insensitive) so a malformed body won't yield the same
/// author twice.
enum CoAuthorParser {
    /// Case-insensitive multi-line regex. Allows mixed casing
    /// (`Co-Authored-By`, `co-authored-by`, …) and trims any horizontal
    /// whitespace around the name and email.
    private static let regex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?im)^\s*Co-Authored-By:\s*([^<\n]+?)\s*<([^>\n]+)>"#
    )

    static func parse(from body: String) -> [CommitAuthor] {
        guard let regex, !body.isEmpty else { return [] }
        let nsRange = NSRange(body.startIndex..., in: body)
        var seen: Set<String> = []
        var result: [CommitAuthor] = []
        for match in regex.matches(in: body, range: nsRange) {
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: body),
                  let emailRange = Range(match.range(at: 2), in: body) else { continue }
            let name = String(body[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let email = String(body[emailRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !email.isEmpty else { continue }
            let key = email.lowercased()
            if seen.insert(key).inserted {
                result.append(CommitAuthor(name: name, email: email))
            }
        }
        return result
    }
}
