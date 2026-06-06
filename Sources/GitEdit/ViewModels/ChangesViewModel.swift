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
    /// Structured error from the most recent operation. The host view observes
    /// this and forwards it to the shared repository-level error banner so
    /// commit / stage / save errors surface in the same UI as push / pull.
    @Published var lastError: GitOperationError?

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
            report(error, operation: .other(L("ステータス取得")))
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
                    let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
                    // Synthesize a unified diff so every line renders as an added
                    // (green) line. The `@@` hunk header is required — without it
                    // the parser treats the `+` lines as file headers (gray).
                    let body = lines.map { "+\($0)" }.joined(separator: "\n")
                    diffText = "@@ -0,0 +1,\(lines.count) @@\n" + body
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
            // If this file is already staged, re-stage it so the commit captures
            // the just-saved content instead of the stale index snapshot.
            if change.willBeCommitted {
                try await git.stage(path: change.path)
            }
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
            report(error, operation: .other(L("ファイル保存")))
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

    /// Anchor row for shift-range toggles: the last row whose checkbox was operated.
    private var lastToggledPath: String?

    func toggleInclusion(of change: FileChange) async {
        do {
            if change.willBeCommitted {
                try await git.unstage(path: change.path)
            } else {
                try await git.stage(path: change.path)
            }
            await refreshStatus()
        } catch {
            report(error, operation: change.willBeCommitted ? .unstage : .stage)
        }
        lastToggledPath = change.path
    }

    /// Toggle a single row, or — when `extendingRange` is set and a previous anchor
    /// exists — the whole inclusive range between the anchor and `change`, matching
    /// the clicked row's new state. `visible` should be the on-screen (filtered) list
    /// so the range follows what the user actually sees.
    func toggleInclusion(of change: FileChange, extendingRange: Bool, in visible: [FileChange]) async {
        guard extendingRange,
              let anchor = lastToggledPath,
              let a = visible.firstIndex(where: { $0.path == anchor }),
              let b = visible.firstIndex(where: { $0.path == change.path }),
              a != b
        else {
            await toggleInclusion(of: change)
            return
        }
        let target = !change.willBeCommitted
        let slice = visible[min(a, b)...max(a, b)]
        do {
            for file in slice where !file.isIgnored && file.willBeCommitted != target {
                if target {
                    try await git.stage(path: file.path)
                } else {
                    try await git.unstage(path: file.path)
                }
            }
            await refreshStatus()
        } catch {
            report(error, operation: target ? .stage : .unstage)
        }
        lastToggledPath = change.path
    }

    // MARK: - Discard

    /// Discard a file's changes. Tracked files are reset to HEAD; untracked files
    /// are moved to the Trash. Destructive — callers should confirm first.
    func discard(_ change: FileChange) async {
        do {
            if change.isUntracked {
                try await git.discardUntracked(
                    path: change.path,
                    wasStaged: change.hasStagedChange
                )
            } else {
                try await git.discardTrackedChanges(path: change.path)
            }
            if selectedPath == change.path {
                resetEditorState()
            }
            await refreshStatus()
        } catch {
            report(error, operation: .other(L("変更の破棄")))
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
            report(error, operation: target ? .stage : .unstage)
        }
    }

    // MARK: - Commit

    func commit() async {
        let summary = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = commitDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return }
        guard stagedCount > 0 else {
            lastError = GitErrorClassifier.classify(
                stderr: "nothing to commit",
                operation: .commit
            )
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
            report(error, operation: .commit)
        }
    }

    // MARK: - Error reporting

    /// Classifies the error and exposes it as `lastError`. The host view
    /// (`RepositoryView`) observes this property and forwards it to the
    /// shared repository-level error banner.
    func report(_ error: Error, operation: GitOperationError.Operation) {
        lastError = GitErrorClassifier.classify(error, operation: operation)
    }

    func clearLastError() {
        lastError = nil
    }
}
