import XCTest
@testable import GitEdit

final class RepositoryPersistenceTests: XCTestCase {
    /// Mirrors the pre-grouping on-disk shape (no `pinned`/`groupID` keys),
    /// used to prove old data still decodes and new data stays legacy-readable.
    private struct LegacyStoredRepository: Codable, Equatable {
        let id: UUID
        let path: String
    }

    func testLegacyDataDecodesWithDefaults() throws {
        let id = UUID()
        let json = """
        [{"id":"\(id.uuidString)","path":"/tmp/repo"}]
        """
        let data = Data(json.utf8)

        let items = RepositoryPersistence.decodeRepositories(data)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, id)
        XCTAssertEqual(items[0].path, "/tmp/repo")
        XCTAssertNil(items[0].pinned)
        XCTAssertNil(items[0].groupID)
    }

    func testNewDataRoundTrips() throws {
        let groupID = UUID()
        let original = [
            RepositoryPersistence.StoredRepository(
                id: UUID(),
                path: "/tmp/repo-a",
                pinned: true,
                groupID: groupID
            ),
            RepositoryPersistence.StoredRepository(
                id: UUID(),
                path: "/tmp/repo-b",
                pinned: nil,
                groupID: nil
            )
        ]

        let data = try XCTUnwrap(RepositoryPersistence.encodeRepositories(original))
        let decoded = RepositoryPersistence.decodeRepositories(data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].id, original[0].id)
        XCTAssertEqual(decoded[0].path, original[0].path)
        XCTAssertEqual(decoded[0].pinned, true)
        XCTAssertEqual(decoded[0].groupID, groupID)
        XCTAssertEqual(decoded[1].pinned, nil)
        XCTAssertEqual(decoded[1].groupID, nil)
    }

    func testNewDataReadableByLegacyStruct() throws {
        let stored = [
            RepositoryPersistence.StoredRepository(
                id: UUID(),
                path: "/tmp/repo",
                pinned: true,
                groupID: UUID()
            )
        ]
        let data = try XCTUnwrap(RepositoryPersistence.encodeRepositories(stored))

        let legacy = try JSONDecoder().decode([LegacyStoredRepository].self, from: data)

        XCTAssertEqual(legacy.count, 1)
        XCTAssertEqual(legacy[0].id, stored[0].id)
        XCTAssertEqual(legacy[0].path, stored[0].path)
    }

    func testGroupsRoundTripAndOptionalCollapsed() throws {
        let original = [
            RepositoryPersistence.StoredGroup(id: UUID(), name: "仕事", collapsed: true),
            RepositoryPersistence.StoredGroup(id: UUID(), name: "個人", collapsed: nil)
        ]

        let data = try XCTUnwrap(RepositoryPersistence.encodeGroups(original))
        let decoded = RepositoryPersistence.decodeGroups(data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "仕事")
        XCTAssertEqual(decoded[0].collapsed, true)
        XCTAssertEqual(decoded[1].name, "個人")
        XCTAssertNil(decoded[1].collapsed)
    }

    func testMissingGroupsKeyYieldsEmpty() {
        XCTAssertEqual(RepositoryPersistence.decodeGroups(nil), [])
    }

    func testOrphanGroupReferenceIsCleared() {
        let knownGroup = UUID()
        let orphanGroup = UUID()
        let repositories = [
            RepositoryPersistence.StoredRepository(id: UUID(), path: "/tmp/a", pinned: nil, groupID: knownGroup),
            RepositoryPersistence.StoredRepository(id: UUID(), path: "/tmp/b", pinned: nil, groupID: orphanGroup),
            RepositoryPersistence.StoredRepository(id: UUID(), path: "/tmp/c", pinned: nil, groupID: nil)
        ]
        let groups = [RepositoryPersistence.StoredGroup(id: knownGroup, name: "仕事", collapsed: nil)]

        let sanitized = RepositoryPersistence.sanitize(repositories: repositories, groups: groups)

        XCTAssertEqual(sanitized.count, 3)
        XCTAssertEqual(sanitized[0].groupID, knownGroup)
        XCTAssertNil(sanitized[1].groupID)
        XCTAssertNil(sanitized[2].groupID)
        // Array order is preserved.
        XCTAssertEqual(sanitized.map(\.path), ["/tmp/a", "/tmp/b", "/tmp/c"])
    }
}
