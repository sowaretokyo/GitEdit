import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    // MARK: - Commit list
    @Published var commits: [Commit] = []
    @Published var selectedCommitID: String?
    @Published var isLoading: Bool = false
    @Published var error: String?

    /// Full SHAs of commits not yet pushed to any remote. Drives the "unpushed"
    /// marker in the commit list.
    @Published var unpushedSHAs: Set<String> = []

    // MARK: - Commit detail (files + diff)
    @Published var commitFiles: [FileChange] = []
    @Published var selectedCommitFilePath: String?
    @Published var commitFileDiff: String = ""
    @Published var isLoadingCommitFiles: Bool = false
    @Published var isLoadingCommitFileDiff: Bool = false

    private let git: GitClient
    private var lastLoadedCommitID: String?

    init(repository: Repository) {
        self.git = GitClient(repository: repository.url)
    }

    // MARK: - Derived

    var selectedCommit: Commit? {
        guard let id = selectedCommitID else { return nil }
        return commits.first { $0.id == id }
    }

    var selectedCommitFile: FileChange? {
        guard let path = selectedCommitFilePath else { return nil }
        return commitFiles.first { $0.path == path }
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let loaded = git.recentCommits(limit: 200)
            async let unpushed = git.unpushedCommitSHAs()
            commits = try await loaded
            unpushedSHAs = await unpushed
            if selectedCommitID == nil {
                selectedCommitID = commits.first?.id
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Load the list of files changed in `id` (if not already loaded), and
    /// auto-select the first file so its diff appears.
    func loadFilesForCommit(_ id: String) async {
        guard id != lastLoadedCommitID else { return }
        lastLoadedCommitID = id

        isLoadingCommitFiles = true
        defer { isLoadingCommitFiles = false }

        do {
            commitFiles = try await git.filesInCommit(sha: id)
            selectedCommitFilePath = commitFiles.first?.path
            await loadDiffForSelectedFile(commitID: id)
        } catch {
            commitFiles = []
            commitFileDiff = ""
            selectedCommitFilePath = nil
            self.error = error.localizedDescription
        }
    }

    func selectCommitFile(_ file: FileChange) async {
        guard selectedCommitFilePath != file.path else { return }
        selectedCommitFilePath = file.path
        guard let commitID = lastLoadedCommitID else { return }
        await loadDiffForSelectedFile(commitID: commitID)
    }

    private func loadDiffForSelectedFile(commitID: String) async {
        guard let path = selectedCommitFilePath else {
            commitFileDiff = ""
            return
        }
        isLoadingCommitFileDiff = true
        defer { isLoadingCommitFileDiff = false }
        do {
            commitFileDiff = try await git.diffForFile(in: commitID, path: path)
        } catch {
            commitFileDiff = L("差分の取得に失敗: %@", error.localizedDescription)
        }
    }
}
