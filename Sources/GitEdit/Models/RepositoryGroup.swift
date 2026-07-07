import Foundation

/// A user-defined folder for organizing repositories in the sidebar.
/// Purely organizational — deleting a group never deletes its repositories.
struct RepositoryGroup: Identifiable, Hashable {
    let id: UUID
    var name: String
    var isCollapsed: Bool

    init(id: UUID = UUID(), name: String, isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.isCollapsed = isCollapsed
    }
}
