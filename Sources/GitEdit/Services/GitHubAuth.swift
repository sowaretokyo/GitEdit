import Foundation

/// GitHub OAuth Device Authorization Grant (RFC 8628) client.
///
/// The Device Flow is what `gh` CLI and VS Code's GitHub auth use. It avoids
/// embedding a `client_secret` (unlike the Web Flow), so it's well-suited to
/// an open-source desktop app without a backend.
///
/// Flow:
/// 1. POST /login/device/code with client_id + scope → device_code + user_code + verification_uri
/// 2. Show user_code to the user, open verification_uri in a browser
/// 3. Poll POST /login/oauth/access_token with device_code until access_token is returned
final class GitHubAuth: @unchecked Sendable {
    struct DeviceCode: Codable {
        let deviceCode: String
        let userCode: String
        let verificationURI: String
        let expiresIn: Int
        let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }
    }

    private struct TokenResponse: Codable {
        let accessToken: String?
        let tokenType: String?
        let scope: String?
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case scope
            case error
            case errorDescription = "error_description"
        }
    }

    enum AuthError: LocalizedError {
        case requestFailed(String)
        case authorizationDenied
        case expiredCode
        case unknownError(String)

        var errorDescription: String? {
            switch self {
            case .requestFailed(let msg):
                return L("認証リクエスト失敗: %@", msg)
            case .authorizationDenied:
                return L("ユーザーが承認をキャンセルしました。")
            case .expiredCode:
                return L("認証コードの有効期限が切れました。もう一度お試しください。")
            case .unknownError(let msg):
                return L("認証エラー: %@", msg)
            }
        }
    }

    let clientID: String
    let scopes: [String]
    private let session: URLSession

    init(clientID: String, scopes: [String] = ["repo", "user:email"]) {
        self.clientID = clientID
        self.scopes = scopes
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "GitEdit/0.6 (macOS; Swift)",
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Steps

    /// Step 1: ask GitHub for a device_code and matching user_code.
    func requestDeviceCode() async throws -> DeviceCode {
        let url = URL(string: "https://github.com/login/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let scopeString = scopes.joined(separator: " ")
        let body = "client_id=\(clientID.urlEncoded)&scope=\(scopeString.urlEncoded)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.requestFailed("invalid response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.requestFailed("HTTP \(http.statusCode): \(body)")
        }
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }

    /// Step 2: poll until the user authorizes (or until we hit a terminal error
    /// such as expired_token / access_denied).
    func pollForToken(deviceCode: String, initialInterval: Int) async throws -> String {
        var interval = max(5, initialInterval)
        let deadline = Date().addingTimeInterval(15 * 60)

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            try Task.checkCancellation()

            let url = URL(string: "https://github.com/login/oauth/access_token")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let body =
                "client_id=\(clientID.urlEncoded)" +
                "&device_code=\(deviceCode.urlEncoded)" +
                "&grant_type=urn:ietf:params:oauth:grant-type:device_code"
            request.httpBody = body.data(using: .utf8)

            do {
                let (data, _) = try await session.data(for: request)
                let resp = try JSONDecoder().decode(TokenResponse.self, from: data)

                if let token = resp.accessToken, !token.isEmpty {
                    return token
                }

                switch resp.error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    interval += 5
                    continue
                case "expired_token":
                    throw AuthError.expiredCode
                case "access_denied":
                    throw AuthError.authorizationDenied
                case let other?:
                    throw AuthError.unknownError(other)
                case .none:
                    throw AuthError.unknownError("empty response")
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let authError as AuthError {
                throw authError
            } catch {
                // transient network error — retry
                continue
            }
        }

        throw AuthError.expiredCode
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? self
    }
}
