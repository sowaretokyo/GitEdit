import Foundation
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [GrepResult] = []
    @Published var isSearching: Bool = false
    @Published var lastError: String?

    private let git: GitClient
    private var searchTask: Task<Void, Never>?

    init(repository: URL) {
        self.git = GitClient(repository: repository)
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

    func run() {
        searchTask?.cancel()
        let q = query
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        isSearching = true
        lastError = nil
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let matches = try await self.git.grep(query: q)
                if !Task.isCancelled {
                    self.results = matches
                }
            } catch {
                if !Task.isCancelled {
                    self.results = []
                    self.lastError = error.localizedDescription
                }
            }
            if !Task.isCancelled {
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
