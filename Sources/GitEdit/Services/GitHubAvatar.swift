import Foundation

/// Builds an avatar URL from a commit author's email.
///
/// Uses GitHub's email-to-user resolution endpoint, the same one GitHub Desktop
/// hits for arbitrary commit emails (see `desktop/app/src/ui/lib/avatar.tsx`):
///
///   https://avatars.githubusercontent.com/u/e?email=<email>&s=<size>
///
/// GitHub resolves the email to a real user avatar if it's associated with a
/// GitHub account, and returns a GitHub-style identicon otherwise — so this
/// single URL handles both `noreply` and arbitrary emails uniformly.
enum GitHubAvatar {
    static func url(for email: String, size: Int = 80) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "avatars.githubusercontent.com"
        components.path = "/u/e"
        components.queryItems = [
            URLQueryItem(name: "email", value: trimmed),
            URLQueryItem(name: "s", value: String(size))
        ]
        return components.url
    }
}
