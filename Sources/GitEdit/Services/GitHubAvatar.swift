import Foundation
import CryptoKit

/// Builds an avatar URL from a commit author's email.
///
/// Strategy:
/// 1. GitHub `noreply` patterns are resolved to canonical `avatars.githubusercontent.com` URLs.
/// 2. Everything else falls back to Gravatar (MD5 of the lowercased email),
///    which serves an identicon if the user has no Gravatar account.
enum GitHubAvatar {
    /// Returns the avatar URL for `email`, requesting a `size` × `size` image.
    static func url(for email: String, size: Int = 80) -> URL? {
        let trimmed = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let noReplySuffix = "@users.noreply.github.com"
        if trimmed.hasSuffix(noReplySuffix) {
            let local = String(trimmed.dropLast(noReplySuffix.count))
            // New canonical form: "<userid>+<username>@users.noreply.github.com"
            if let plusIdx = local.firstIndex(of: "+") {
                let userIDPart = String(local[..<plusIdx])
                let usernamePart = String(local[local.index(after: plusIdx)...])
                if Int(userIDPart) != nil {
                    return URL(string: "https://avatars.githubusercontent.com/u/\(userIDPart)?s=\(size)&v=4")
                }
                if !usernamePart.isEmpty {
                    return URL(string: "https://avatars.githubusercontent.com/\(usernamePart)?s=\(size)&v=4")
                }
            } else if !local.isEmpty {
                // Legacy form: "<username>@users.noreply.github.com"
                return URL(string: "https://avatars.githubusercontent.com/\(local)?s=\(size)&v=4")
            }
        }

        // Gravatar fallback (matches GitHub Desktop's approach).
        let md5 = md5Hex(of: trimmed)
        return URL(string: "https://www.gravatar.com/avatar/\(md5)?s=\(size)&d=identicon")
    }

    private static func md5Hex(of string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
