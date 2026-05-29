import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var commits: [Commit] = []
    @Published var selectedCommitID: String?
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let git: GitClient

    init(repository: Repository) {
        self.git = GitClient(repository: repository.url)
    }

    var selectedCommit: Commit? {
        guard let id = selectedCommitID else { return nil }
        return commits.first { $0.id == id }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            commits = try await git.recentCommits(limit: 200)
            if selectedCommitID == nil {
                selectedCommitID = commits.first?.id
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
