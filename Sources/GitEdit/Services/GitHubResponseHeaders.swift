import Foundation

struct RateLimit: Equatable {
    let limit: Int
    let remaining: Int
    let reset: Date
}

/// Wraps a decoded response body together with the response headers we care
/// about, so callers that only want `.value` can ignore the rest while
/// callers that need pagination / rate-limit / scope info still have it.
struct GitHubResponse<T> {
    let value: T
    let rateLimit: RateLimit?
    let scopes: [String]
    let nextPageURL: URL?
}

/// Pure parsing functions for the handful of GitHub response headers this
/// app reads. Kept independent of `URLSession`/`HTTPURLResponse` so they can
/// be unit-tested without a network stack.
enum GitHubResponseHeaders {
    /// Extracts the `rel="next"` URL from a `Link` header, e.g.:
    /// `<https://api.github.com/…?page=2>; rel="next", <…>; rel="last"`
    static func nextPageURL(linkHeader: String?) -> URL? {
        guard let linkHeader else { return nil }
        for part in linkHeader.split(separator: ",") {
            let segments = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard segments.count >= 2, segments[1] == "rel=\"next\"" else { continue }
            var urlPart = segments[0]
            guard urlPart.hasPrefix("<"), urlPart.hasSuffix(">") else { continue }
            urlPart.removeFirst()
            urlPart.removeLast()
            return URL(string: String(urlPart))
        }
        return nil
    }

    /// Parses the comma-separated `X-OAuth-Scopes` header into individual
    /// scope names. Returns an empty array when the header is absent or empty.
    static func scopes(oauthScopesHeader: String?) -> [String] {
        guard let oauthScopesHeader, !oauthScopesHeader.isEmpty else { return [] }
        return oauthScopesHeader
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Parses the `X-RateLimit-Limit` / `-Remaining` / `-Reset` trio. Returns
    /// `nil` if any of the three is missing or not a valid number, since a
    /// partial reading isn't useful to callers.
    static func rateLimit(
        limitHeader: String?,
        remainingHeader: String?,
        resetHeader: String?
    ) -> RateLimit? {
        guard let limitHeader, let limit = Int(limitHeader),
              let remainingHeader, let remaining = Int(remainingHeader),
              let resetHeader, let resetEpoch = TimeInterval(resetHeader) else {
            return nil
        }
        return RateLimit(limit: limit, remaining: remaining, reset: Date(timeIntervalSince1970: resetEpoch))
    }
}
