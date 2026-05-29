import Foundation

/// A signed-in GitHub user — the projection of `/user` we care about.
struct GitHubAccount: Codable, Identifiable, Hashable {
    let login: String
    let userID: Int
    let name: String?
    let email: String?
    let avatarURL: String?
    let htmlURL: String?
    let company: String?

    var id: String { login }

    enum CodingKeys: String, CodingKey {
        case login
        case userID = "id"
        case name
        case email
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
        case company
    }
}
