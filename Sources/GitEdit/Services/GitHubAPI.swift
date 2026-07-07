import Foundation

/// Minimal authenticated GitHub REST client.
/// Hardcoded to `api.github.com`; GHE support is deferred.
final class GitHubAPI: @unchecked Sendable {
    enum APIError: LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case decodingError(Error)
        case unauthorized
        /// A 403 where the token is simply missing the scope a write needs.
        /// Distinguished from `.forbidden` by checking `X-OAuth-Scopes`
        /// against the scope the call declared it needs.
        case insufficientScopes
        /// A 403 that isn't a rate limit or a known scope gap (e.g. blocked
        /// by an org policy, or a repo the token can't see).
        case forbidden
        case rateLimited(reset: Date)
        case notMergeable
        case conflict
        case validationFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return L("不正なレスポンス")
            case .httpError(let code, let body):
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(trimmed)"
            case .decodingError(let underlying):
                return L("レスポンスの解析に失敗: %@", underlying.localizedDescription)
            case .unauthorized:
                return L("トークンが無効です。再発行してください。")
            case .insufficientScopes:
                return L("権限が不足しています。再サインインしてください")
            case .forbidden:
                return L("この操作を行う権限がありません。")
            case .rateLimited(let reset):
                return L("GitHub API のレート制限に達しました。%@ 以降に再試行してください", Self.timeFormatter.string(from: reset))
            case .notMergeable:
                return L("このプルリクエストはマージできません。")
            case .conflict:
                return L("競合が発生しました。")
            case .validationFailed(let message):
                return message
            }
        }

        private static let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateStyle = .none
            f.timeStyle = .short
            return f
        }()
    }

    static let defaultEndpoint = URL(string: "https://api.github.com")!

    /// Shared decoder for all GitHub responses. GitHub's timestamps
    /// (`created_at`, `updated_at`, …) are standard ISO 8601.
    static let sharedDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    let endpoint: URL
    private let token: String
    private let session: URLSession

    init(endpoint: URL = GitHubAPI.defaultEndpoint, token: String) {
        self.endpoint = endpoint
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "GitEdit/0.6 (macOS; Swift)",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Endpoints

    func currentUser() async throws -> GitHubAccount {
        try await send(method: "GET", path: "/user", as: GitHubAccount.self).value
    }

    // MARK: - Generic request

    /// Issues an authenticated request against `path` (relative to
    /// `endpoint`), decodes the JSON body as `T`, and surfaces the response's
    /// rate-limit / scope / pagination headers alongside it.
    ///
    /// `requiredScope`, when given, is only consulted on a 403: if the
    /// response's `X-OAuth-Scopes` header is present and doesn't include it,
    /// the failure is reported as `.insufficientScopes` rather than the
    /// generic `.forbidden` — this app doesn't run a re-consent flow (the
    /// default Device Flow scope, `repo`, already covers every write we make),
    /// but a token created with a narrower custom scope should still get a
    /// specific error instead of an opaque 403.
    func send<T: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        as type: T.Type,
        requiredScope: String? = nil
    ) async throws -> GitHubResponse<T> {
        var components = URLComponents(url: endpoint.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        let rateLimit = GitHubResponseHeaders.rateLimit(
            limitHeader: http.value(forHTTPHeaderField: "X-RateLimit-Limit"),
            remainingHeader: http.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
            resetHeader: http.value(forHTTPHeaderField: "X-RateLimit-Reset")
        )
        let scopes = GitHubResponseHeaders.scopes(oauthScopesHeader: http.value(forHTTPHeaderField: "X-OAuth-Scopes"))
        let nextPageURL = GitHubResponseHeaders.nextPageURL(linkHeader: http.value(forHTTPHeaderField: "Link"))

        switch http.statusCode {
        case 200...299:
            do {
                let value = try Self.sharedDecoder.decode(T.self, from: data)
                return GitHubResponse(value: value, rateLimit: rateLimit, scopes: scopes, nextPageURL: nextPageURL)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            if let rateLimit, rateLimit.remaining == 0 {
                throw APIError.rateLimited(reset: rateLimit.reset)
            }
            if let requiredScope, !scopes.isEmpty, !scopes.contains(requiredScope) {
                throw APIError.insufficientScopes
            }
            throw APIError.forbidden
        case 405:
            throw APIError.notMergeable
        case 409:
            throw APIError.conflict
        case 422:
            throw APIError.validationFailed(Self.errorMessage(from: data) ?? L("入力内容を確認してください。"))
        default:
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(http.statusCode, bodyText)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable { let message: String? }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).message
    }
}
