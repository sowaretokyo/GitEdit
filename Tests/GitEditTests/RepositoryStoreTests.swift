import XCTest
@testable import GitEdit

@MainActor
final class RepositoryStoreTests: XCTestCase {
    // `RepositoryStore.repositories`'s didSet persists to UserDefaults.standard;
    // save/restore the two keys it touches so this test doesn't leak state.
    private var savedRepositoriesData: Data?
    private var savedGroupsData: Data?

    override func setUp() {
        super.setUp()
        savedRepositoriesData = UserDefaults.standard.data(forKey: "repositories")
        savedGroupsData = UserDefaults.standard.data(forKey: "repositoryGroups")
    }

    override func tearDown() {
        if let savedRepositoriesData {
            UserDefaults.standard.set(savedRepositoriesData, forKey: "repositories")
        } else {
            UserDefaults.standard.removeObject(forKey: "repositories")
        }
        if let savedGroupsData {
            UserDefaults.standard.set(savedGroupsData, forKey: "repositoryGroups")
        } else {
            UserDefaults.standard.removeObject(forKey: "repositoryGroups")
        }
        super.tearDown()
    }

    func testRepositoryWithIDReturnsMatchForExistingID() {
        let store = RepositoryStore()
        let repo = Repository(url: URL(fileURLWithPath: "/tmp/repo-a"))
        store.repositories = [repo]

        XCTAssertEqual(store.repository(withID: repo.id)?.url, repo.url)
    }

    func testRepositoryWithIDReturnsNilForUnknownID() {
        let store = RepositoryStore()
        store.repositories = [Repository(url: URL(fileURLWithPath: "/tmp/repo-a"))]

        XCTAssertNil(store.repository(withID: UUID()))
    }
}
