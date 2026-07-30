import XCTest
@testable import GitEdit

@MainActor
final class SearchViewModelTests: XCTestCase {
    private var repoURL: URL!
    private var git: GitClient!

    override func setUp() async throws {
        try await super.setUp()
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        git = GitClient(repository: repoURL)
        try await git.run("init", "-q", "-b", "main")
        try "first needle\nsecond target\n"
            .write(to: repoURL.appendingPathComponent("sample.txt"), atomically: true, encoding: .utf8)
        try await git.run("add", "sample.txt")
    }

    override func tearDown() async throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        repoURL = nil
        git = nil
        try await super.tearDown()
    }

    func testScheduledSearchRunsAfterDebounce() async throws {
        let viewModel = SearchViewModel(repository: repoURL, debounceDuration: .milliseconds(10))
        viewModel.query = "needle"

        viewModel.scheduleSearch()
        try await waitForSearch(viewModel)

        XCTAssertEqual(viewModel.results.count, 1)
        XCTAssertEqual(viewModel.results.first?.path, "sample.txt")
        XCTAssertEqual(viewModel.results.first?.lineNumber, 1)
    }

    func testScheduledSearchKeepsOnlyLatestQuery() async throws {
        let viewModel = SearchViewModel(repository: repoURL, debounceDuration: .milliseconds(30))
        viewModel.query = "needle"
        viewModel.scheduleSearch()

        viewModel.query = "target"
        viewModel.scheduleSearch()
        try await waitForSearch(viewModel)

        XCTAssertEqual(viewModel.results.count, 1)
        XCTAssertEqual(viewModel.results.first?.lineNumber, 2)
        XCTAssertTrue(viewModel.results.first?.content.contains("target") == true)
    }

    func testEmptyQueryClearsResultsWithoutSearching() async throws {
        let viewModel = SearchViewModel(repository: repoURL, debounceDuration: .milliseconds(10))
        viewModel.query = "needle"
        viewModel.searchImmediately()
        try await waitForSearch(viewModel)
        XCTAssertFalse(viewModel.results.isEmpty)

        viewModel.query = "   "
        viewModel.scheduleSearch()

        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertNil(viewModel.lastError)
    }

    private func waitForSearch(_ viewModel: SearchViewModel) async throws {
        for _ in 0..<200 {
            if !viewModel.isSearching {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Search did not finish before timeout")
    }
}
