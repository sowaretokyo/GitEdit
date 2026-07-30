import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [GrepResult] = []
    @Published var isSearching: Bool = false
    @Published var lastError: String?

    private let git: GitClient
    private let debounceDuration: Duration
    private var searchTask: Task<Void, Never>?

    init(repository: URL, debounceDuration: Duration = .milliseconds(300)) {
        self.git = GitClient(repository: repository)
        self.debounceDuration = debounceDuration
    }

    /// Files-as-sections projection of the results.
    var groupedResults: [(path: String, matches: [GrepResult])] {
        let groups = Dictionary(grouping: results, by: { $0.path })
        return groups
            .map { (path: $0.key, matches: $0.value.sorted { $0.lineNumber < $1.lineNumber }) }
            .sorted { $0.path < $1.path }
    }

    var totalMatches: Int { results.count }
    var totalFiles: Int { Set(results.map(\.path)).count }

    func scheduleSearch() {
        startSearch(after: debounceDuration)
    }

    func searchImmediately() {
        startSearch(after: nil)
    }

    private func startSearch(after delay: Duration?) {
        searchTask?.cancel()
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchQuery.isEmpty else {
            results = []
            isSearching = false
            lastError = nil
            return
        }
        isSearching = true
        lastError = nil
        let git = self.git
        searchTask = Task { [weak self] in
            do {
                if let delay {
                    try await Task.sleep(for: delay)
                }
                try Task.checkCancellation()
                let matches = try await git.grep(query: searchQuery)
                try Task.checkCancellation()
                guard let self else { return }
                self.results = matches
                self.isSearching = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.results = []
                self.lastError = error.localizedDescription
                self.isSearching = false
            }
        }
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        results = []
        isSearching = false
        lastError = nil
    }
}
