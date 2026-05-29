import Foundation

struct Repository: Identifiable, Hashable {
    let id: UUID
    var url: URL
    var currentBranch: String?

    var name: String { url.lastPathComponent }

    init(id: UUID = UUID(), url: URL, currentBranch: String? = nil) {
        self.id = id
        self.url = url
        self.currentBranch = currentBranch
    }
}
