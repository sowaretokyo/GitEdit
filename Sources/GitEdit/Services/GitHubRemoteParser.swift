import Foundation

/// A GitHub repository identified from a remote URL. Used to build web
/// links (e.g. to issues) — GitLab, Bitbucket, and GitHub Enterprise remotes
/// are intentionally not recognized.
struct GitHubRepositoryRef: Equatable {
    let owner: String
    let repo: String

    var webBaseURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)")!
    }

    func issueURL(_ number: Int) -> URL {
        webBaseURL.appendingPathComponent("issues/\(number)")
    }
}

/// Parses `git remote` URLs into a `GitHubRepositoryRef`, if they point at
/// github.com.
enum GitHubRemoteParser {
    /// SCP-like SSH form: `git@github.com:owner/repo.git`
    private static let scpRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)^[^@/\s]+@github\.com:([^/]+)/([^/]+?)(?:\.git)?/?$"#
    )
    /// URL forms: `https://github.com/owner/repo(.git)`, `ssh://git@github.com/owner/repo.git`
    private static let urlRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)^(?:https?|ssh)://(?:[^@/\s]+@)?github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$"#
    )

    static func parse(remoteURL: String) -> GitHubRepositoryRef? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for regex in [scpRegex, urlRegex] {
            if let ref = firstMatch(regex, in: trimmed) {
                return ref
            }
        }
        return nil
    }

    private static func firstMatch(_ regex: NSRegularExpression?, in text: String) -> GitHubRepositoryRef? {
        guard let regex else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges == 3,
              let ownerRange = Range(match.range(at: 1), in: text),
              let repoRange = Range(match.range(at: 2), in: text) else { return nil }
        let owner = String(text[ownerRange])
        let repo = String(text[repoRange])
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        return GitHubRepositoryRef(owner: owner, repo: repo)
    }
}
