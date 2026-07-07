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

    // MARK: - Commit history editing (reword / squash / drop / reorder)

    /// Presents `CommitMessageSheet` when set — reword or squash awaiting a
    /// message from the user.
    @Published var pendingMessageEdit: PendingMessageEdit?
    /// Presents the drop confirmation dialog when set.
    @Published var pendingDropCommit: Commit?
    @Published var isEditingHistory: Bool = false
    /// Set once after a successful edit; `RepositoryView` forwards this into
    /// `RepositoryViewModel`'s undo/backup state and success banner, then
    /// nils it back out.
    @Published var completedEdit: CommitEditCompletion?
    /// Set on a failed edit; `RepositoryView` forwards this into the shared
    /// error banner, then nils it back out.
    @Published var editError: GitOperationError?

    struct PendingMessageEdit: Identifiable {
        enum Kind { case reword, squash }
        let id = UUID()
        let kind: Kind
        let targetIndex: Int
        let initialMessage: String
    }

    struct CommitEditCompletion: Equatable {
        let backup: CommitEditBackup
        let successMessage: String
    }

    /// True when `commits` reaches the repository's actual root commit
    /// (fewer commits were returned than the fetch limit) — see
    /// `CommitHistoryEditor.buildPlan`'s `isFullHistoryLoaded` parameter.
    private var isFullHistoryLoaded: Bool { commits.count < Self.historyLoadLimit }
    private static let historyLoadLimit = 200

    // MARK: - Commit detail (files + diff)
    @Published var commitFiles: [FileChange] = []
    @Published var selectedCommitFilePath: String?
    @Published var commitFileDiff: String = ""
    /// Set instead of `commitFileDiff` when the selected file is an image.
    /// `nil` for non-image files (and for images with no decodable content
    /// on either side).
    @Published var commitImageDiff: ImageDiffContent?
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
            async let loaded = git.recentCommits(limit: Self.historyLoadLimit)
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
            commitImageDiff = nil
            return
        }
        isLoadingCommitFileDiff = true
        defer { isLoadingCommitFileDiff = false }

        if ImageDiff.isImagePath(path), let file = selectedCommitFile {
            let before = file.category == .added ? nil : await git.showFileData(rev: "\(commitID)^", path: path)
            let after = file.category == .deleted ? nil : await git.showFileData(rev: commitID, path: path)
            let content = ImageDiffContent(before: before, after: after)
            commitImageDiff = content.hasAny ? content : nil
            commitFileDiff = ""
            return
        }
        commitImageDiff = nil

        do {
            commitFileDiff = try await git.diffForFile(in: commitID, path: path)
        } catch {
            commitFileDiff = L("差分の取得に失敗: %@", error.localizedDescription)
        }
    }

    // MARK: - Commit history editing (reword / squash / drop / reorder)

    /// Whether each history-editing action should be enabled for the commit
    /// at `index` — drives `CommitRow`'s context menu.
    func editability(at index: Int) -> CommitHistoryEditor.RowEditability {
        CommitHistoryEditor.rowEditability(
            commits: commits,
            targetIndex: index,
            unpushedSHAs: unpushedSHAs,
            isFullHistoryLoaded: isFullHistoryLoaded
        )
    }

    func requestReword(at index: Int) {
        guard commits.indices.contains(index) else { return }
        pendingMessageEdit = PendingMessageEdit(kind: .reword, targetIndex: index, initialMessage: commits[index].body)
    }

    func requestSquashIntoPrevious(at index: Int) {
        let previousIndex = index + 1
        guard commits.indices.contains(index), commits.indices.contains(previousIndex) else { return }
        let parentMessage = commits[previousIndex].body.trimmingCharacters(in: .whitespacesAndNewlines)
        let childMessage = commits[index].body.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingMessageEdit = PendingMessageEdit(
            kind: .squash,
            targetIndex: index,
            initialMessage: parentMessage + "\n\n" + childMessage
        )
    }

    func cancelMessageEdit() {
        pendingMessageEdit = nil
    }

    func confirmMessageEdit(_ message: String) async {
        guard let pending = pendingMessageEdit else { return }
        pendingMessageEdit = nil
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch pending.kind {
        case .reword:
            await performEdit(
                targetIndex: pending.targetIndex,
                operation: .reword,
                message: trimmed,
                undoLabel: L("メッセージ編集"),
                successMessage: L("メッセージを更新しました")
            )
        case .squash:
            await performEdit(
                targetIndex: pending.targetIndex,
                operation: .squashIntoPrevious,
                message: trimmed,
                undoLabel: L("コミットの統合"),
                successMessage: L("コミットを統合しました")
            )
        }
    }

    func requestDrop(at index: Int) {
        guard commits.indices.contains(index) else { return }
        pendingDropCommit = commits[index]
    }

    func cancelDrop() {
        pendingDropCommit = nil
    }

    func confirmDrop() async {
        guard let commit = pendingDropCommit,
              let index = commits.firstIndex(where: { $0.id == commit.id }) else {
            pendingDropCommit = nil
            return
        }
        pendingDropCommit = nil
        await performEdit(
            targetIndex: index,
            operation: .drop,
            message: nil,
            undoLabel: L("コミットの削除"),
            successMessage: L("コミットを削除しました")
        )
    }

    func moveUp(at index: Int) async {
        await performEdit(
            targetIndex: index,
            operation: .moveUp,
            message: nil,
            undoLabel: L("並び替え"),
            successMessage: L("コミットを並び替えました")
        )
    }

    func moveDown(at index: Int) async {
        await performEdit(
            targetIndex: index,
            operation: .moveDown,
            message: nil,
            undoLabel: L("並び替え"),
            successMessage: L("コミットを並び替えました")
        )
    }

    private func performEdit(
        targetIndex: Int,
        operation: CommitHistoryEditor.Operation,
        message: String?,
        undoLabel: String,
        successMessage: String
    ) async {
        guard commits.indices.contains(targetIndex), !isEditingHistory else { return }
        isEditingHistory = true
        defer { isEditingHistory = false }

        let shas = commits.map(\.id)
        let runner = CommitHistoryEditor.Runner(git: git)
        do {
            let result = try await runner.performEdit(
                commitsNewestFirst: shas,
                targetIndex: targetIndex,
                operation: operation,
                message: message,
                isFullHistoryLoaded: isFullHistoryLoaded
            )
            completedEdit = CommitEditCompletion(
                backup: CommitEditBackup(backupSHA: result.backupSHA, resultSHA: result.newHeadSHA, summary: undoLabel),
                successMessage: successMessage
            )
            // Rewriting history mints new SHAs for everything from the edit
            // point up to HEAD, so the old selection/file-cache no longer
            // refers to anything real. Clearing `selectedCommitID` before
            // `load()` lets its own "select HEAD if nothing's selected"
            // logic land on the fresh HEAD.
            selectedCommitID = nil
            lastLoadedCommitID = nil
            await load()
        } catch {
            editError = Self.classifyEditError(error, operation: operation)
        }
    }

    /// Maps `CommitHistoryEditor.ExecutionError` (and any raw `PlanError`/git
    /// failure) onto the shared `GitOperationError` banner type, since the
    /// editor's own error type doesn't carry `GitErrorClassifier`-style copy.
    private static func classifyEditError(_ error: Error, operation: CommitHistoryEditor.Operation) -> GitOperationError {
        let opLabel: GitOperationError.Operation = .other({
            switch operation {
            case .reword: return L("メッセージ編集")
            case .squashIntoPrevious: return L("コミットの統合")
            case .drop: return L("コミットの削除")
            case .moveUp, .moveDown: return L("並び替え")
            }
        }())

        let summary: String
        switch error {
        case CommitHistoryEditor.ExecutionError.dirtyWorkingTree:
            summary = L("作業ツリーに変更があります。コミットまたは退避してから編集してください。")
        case CommitHistoryEditor.ExecutionError.mergeCommitInRange:
            summary = L("マージコミットを含む範囲は編集できません。")
        case CommitHistoryEditor.ExecutionError.pushedCommitInRange:
            summary = L("プッシュ済みのコミットは編集できません。")
        case CommitHistoryEditor.ExecutionError.conflict:
            summary = L("コミットの編集を中止し、元の状態に戻しました（競合または適用できない変更のため）。")
        case CommitHistoryEditor.ExecutionError.gitFailure(let message):
            summary = message
        default:
            summary = error.localizedDescription
        }

        return GitOperationError(
            operation: opLabel,
            kind: .unknown,
            title: opLabel.failureLabel,
            summary: summary,
            suggestions: [],
            rawStderr: "",
            command: ""
        )
    }
}
