import Foundation

struct Commit: Identifiable, Hashable {
    let id: String
    let shortSHA: String
    let summary: String
    let body: String
    let author: String
    let authorEmail: String
    let date: Date
}
