import Foundation

/// On-disk (UserDefaults) representation of `Repository` and `RepositoryGroup`.
///
/// Kept separate from the models so the persisted schema can grow without
/// touching the in-memory types. New fields are always optional, so data
/// written by a newer app version still decodes on an older one (unknown
/// keys are ignored) — the older version just won't preserve pin/group
/// state if it happens to write the data back out.
enum RepositoryPersistence {
    /// `currentBranch` is derived state, re-fetched on launch, so it isn't
    /// persisted here.
    struct StoredRepository: Codable {
        let id: UUID
        let path: String
        var pinned: Bool?
        var groupID: UUID?
    }

    struct StoredGroup: Codable, Equatable {
        let id: UUID
        var name: String
        var collapsed: Bool?
    }

    static func decodeRepositories(_ data: Data?) -> [StoredRepository] {
        guard let data,
              let items = try? JSONDecoder().decode([StoredRepository].self, from: data)
        else { return [] }
        return items
    }

    static func decodeGroups(_ data: Data?) -> [StoredGroup] {
        guard let data,
              let items = try? JSONDecoder().decode([StoredGroup].self, from: data)
        else { return [] }
        return items
    }

    static func encodeRepositories(_ repositories: [StoredRepository]) -> Data? {
        try? JSONEncoder().encode(repositories)
    }

    static func encodeGroups(_ groups: [StoredGroup]) -> Data? {
        try? JSONEncoder().encode(groups)
    }

    /// Clears `groupID` references that don't match any known group, so a
    /// group lost elsewhere (e.g. partial writes, manual defaults editing)
    /// never leaves a repository pointing at a dangling id.
    static func sanitize(
        repositories: [StoredRepository],
        groups: [StoredGroup]
    ) -> [StoredRepository] {
        let knownGroupIDs = Set(groups.map(\.id))
        return repositories.map { repository in
            var repository = repository
            if let groupID = repository.groupID, !knownGroupIDs.contains(groupID) {
                repository.groupID = nil
            }
            return repository
        }
    }
}
