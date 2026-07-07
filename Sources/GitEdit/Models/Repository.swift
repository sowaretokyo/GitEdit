import Foundation

struct Repository: Identifiable, Hashable {
    let id: UUID
    var url: URL
    var currentBranch: String?
    var isPinned: Bool
    var groupID: UUID?

    var name: String { url.lastPathComponent }

    init(
        id: UUID = UUID(),
        url: URL,
        currentBranch: String? = nil,
        isPinned: Bool = false,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.url = url
        self.currentBranch = currentBranch
        self.isPinned = isPinned
        self.groupID = groupID
    }
}
