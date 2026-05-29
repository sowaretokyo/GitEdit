import Foundation
import SwiftUI

@MainActor
final class ChangesViewModel: ObservableObject {
    enum DiffEditorMode: String, CaseIterable, Identifiable {
        case edit, diff
        var id: String { rawValue }
        var title: String {
            switch self {
            case .edit: return L("編集")
            case .diff: return L("差分")
            }
        }
    }

    // MARK: - File list & selection
    @Published var changes: [FileChange] = []
    @Published var selectedPath: String?

    // MARK: - Diff view
    @Published var diffText: String = ""
    @Published var isLoadingDiff: Bool = false

    // MARK: - Editor view
    @Published var editorViewMode: DiffEditorMode = .diff
    @Published var editorFileContent: String = ""
    @Published var hasEditorUnsavedChanges: Bool = false
    @Published var editorAddedLines: Set<Int> = []
    @Published var selectedFileIsEditable: Bool = false
    @Published var isSavingEditor: Bool = false

    // MARK: - Commit
    @Published var commitMessage: String = ""
    @Published var commitDescription: String = ""
    @Published var commitHistory: [String] = []
    /// Bumped after each successful commit so observers (e.g. RepositoryView)
    /// can refresh ahead/behind counts to light up the Push toolbar button.
    @Published var commitVersion: Int = 0
    @Published var currentBranch: String?
    @Published var isCommitting: Bool = false
    @Published var lastError: String?

    private let git: GitClient

    init(repository: Repository) {
        self.git = GitClient(repository: repository.url)
    }

    var selectedChange: FileChange? {
        guard let path = selectedPath else { return nil }
        return changes.first { $0.path == path }
    }

    var stagedCount: Int { changes.filter { $0.willBeCommitted }.count }

    var allStaged: Bool {
        let stageable = changes.filter { !$0.isIgnored }
        return !stageable.isEmpty && stageable.allSatisfy { $0.willBeCommitted }
    }

    // MARK: - Loading

    func refreshAll() async {
        async let st: Void = refreshStatus()
        async let hi: Void = loadHistory()
        async let br: Void = refreshBranch()
        _ = await (st, hi, br)
    }

    func refreshStatus() async {
        do {
            let prev = selectedPath
            changes = try await git.status()
            if prev == nil || !changes.contains(where: { $0.path == prev }) {
                if let first = changes.first {
                    await select(first)
                } else {
                    selectedPath = nil
                    resetEditorState()
                    diffText = ""
                }
            } else {
                await refreshDiffForSelection()
                await loadEditorContentIfNeeded()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadHistory() async {
        commitHistory = (try? await git.recentCommitMessages(limit: 100)) ?? []
    }

    func refreshBranch() async {
        currentBranch = try? await git.currentBranch()
    }

    // MARK: - Selection

    func select(_ change: FileChange) async {
        if selectedPath == change.path { return }

        if hasEditorUnsavedChanges {
            await saveEditorContent()
        }

        selectedPath = change.path
        await refreshDiffForSelection()
        await loadEditorContentIfNeeded()
    }

    func refreshDiffForSelection() async {
        guard let change = selectedChange else {
            diffText = ""
            return
        }
        isLoadingDiff = true
        defer { isLoadingDiff = false }
        do {
            if change.isUntracked {
                if let content = git.readFileFromWorkTree(path: change.path) {
                    diffText = content
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "+\($0)" }
                        .joined(separator: "\n")
                } else {
                    diffText = ""
                }
            } else {
                diffText = try await git.diffAgainstHEAD(path: change.path)
            }
        } catch {
            diffText = L("差分の取得に失敗: %@", error.localizedDescription)
        }
    }

    // MARK: - Editor

    private func loadEditorContentIfNeeded() async {
        guard let change = selectedChange else {
            resetEditorState()
            return
        }
        selectedFileIsEditable = computeIsEditable(for: change)

        guard selectedFileIsEditable else {
            resetEditorState()
            return
        }

        if let content = git.readFileFromWorkTree(path: change.path) {
            editorFileContent = content
            hasEditorUnsavedChanges = false
            editorAddedLines = DiffLineAnalyzer.addedLines(
                from: diffText,
                isUntracked: change.isUntracked,
                content: content
            )
        } else {
            resetEditorState()
        }
    }

    private func resetEditorState() {
        editorFileContent = ""
        editorAddedLines = []
        hasEditorUnsavedChanges = false
    }

    private func computeIsEditable(for change: FileChange) -> Bool {
        // Deleted files have no current content.
        if change.indexStatus == "D" || change.workingStatus == "D" {
            return false
        }
        guard let content = git.readFileFromWorkTree(path: change.path) else {
            return false
        }
        // Heuristic: binary files contain null bytes in the first 8KB.
        let sample = content.prefix(8192)
        if sample.contains("\0") { return false }
        return true
    }

    func updateEditorContent(_ content: String) {
        if editorFileContent != content {
            editorFileContent = content
            hasEditorUnsavedChanges = true
        }
    }

    func saveEditorContent() async {
        guard let change = selectedChange, selectedFileIsEditable else { return }
        guard hasEditorUnsavedChanges else { return }
        isSavingEditor = true
        defer { isSavingEditor = false }
        do {
            try git.writeFile(path: change.path, content: editorFileContent)
            hasEditorUnsavedChanges = false
            // Refresh diff and re-compute highlights.
            await refreshDiffForSelection()
            editorAddedLines = DiffLineAnalyzer.addedLines(
                from: diffText,
                isUntracked: change.isUntracked,
                content: editorFileContent
            )
            // Refresh status (file might now be clean/dirty differently).
            let prev = selectedPath
            changes = (try? await git.status()) ?? changes
            selectedPath = prev
        } catch {
            lastError = L("保存に失敗: %@", error.localizedDescription)
        }
    }

    func setEditorViewMode(_ mode: DiffEditorMode) async {
        if editorViewMode == mode { return }
        if mode == .diff && hasEditorUnsavedChanges {
            await saveEditorContent()
        }
        editorViewMode = mode
    }

    // MARK: - Staging

    func toggleInclusion(of change: FileChange) async {
        do {
            if change.willBeCommitted {
                try await git.unstage(path: change.path)
            } else {
                try await git.stage(path: change.path)
            }
            await refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleAll() async {
        let target = !allStaged
        do {
            if target {
                try await git.stageAll()
            } else {
                try await git.unstageAll()
            }
            await refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Commit

    func commit() async {
        let summary = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = commitDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return }
        guard stagedCount > 0 else {
            lastError = L("ステージされた変更がありません。チェックボックスでファイルを含めてください。")
            return
        }
        // Combine summary + description into a single git commit message.
        let fullMessage = body.isEmpty ? summary : "\(summary)\n\n\(body)"

        // Auto-save any pending editor changes before committing.
        if hasEditorUnsavedChanges {
            await saveEditorContent()
        }
        isCommitting = true
        defer { isCommitting = false }
        do {
            try await git.commit(message: fullMessage)
            commitMessage = ""
            commitDescription = ""
            await refreshAll()
            commitVersion &+= 1
        } catch {
            lastError = error.localizedDescription
        }
    }
}
