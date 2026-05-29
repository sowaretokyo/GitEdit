import Foundation

/// Minimal authenticated GitHub REST client.
/// Hardcoded to `api.github.com`; GHE support is deferred.
final class GitHubAPI: @unchecked Sendable {
    enum APIError: LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case decodingError(Error)
        case unauthorized
        case insufficientScopes

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
                return L("このトークンには必要な権限がありません。")
            }
        }
    }

    static let defaultEndpoint = URL(string: "https://api.github.com")!

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
        try await get("/user", as: GitHubAccount.self)
    }

    // MARK: - Generic GET

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: endpoint.appending(path: path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.insufficientScopes
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(http.statusCode, body)
        }
    }
}
