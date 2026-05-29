import Foundation
import SwiftUI

@MainActor
final class ExplorerViewModel: ObservableObject {
    @Published var rootNodes: [FileNode] = []
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    let repositoryURL: URL
    private let index: RepositoryFileIndex

    init(repository: URL) {
        self.repositoryURL = repository
        self.index = RepositoryFileIndex(repository: repository)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let paths = try await index.allPaths()
            rootNodes = FileTreeBuilder.build(from: paths, repositoryURL: repositoryURL)
            lastError = nil
        } catch {
            rootNodes = []
            lastError = error.localizedDescription
        }
    }
}
