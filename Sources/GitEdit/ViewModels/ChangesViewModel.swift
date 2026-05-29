import Foundation
import SwiftUI

@MainActor
final class ChangesViewModel: ObservableObject {
    @Published var changes: [FileChange] = []
    @Published var selectedPath: String?
    @Published var diffText: String = ""
    @Published var isLoadingDiff: Bool = false
    @Published var commitMessage: String = ""
    @Published var commitHistory: [String] = []
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

    var stagedCount: Int {
        changes.filter { $0.willBeCommitted }.count
    }

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
                selectedPath = changes.first?.path
            }
            await refreshDiffForSelection()
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

    // MARK: - Selection / Diff

    func select(_ change: FileChange) {
        guard selectedPath != change.path else { return }
        selectedPath = change.path
        Task { await refreshDiffForSelection() }
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
            diffText = "差分の取得に失敗: \(error.localizedDescription)"
        }
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
        let trimmed = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard stagedCount > 0 else {
            lastError = "ステージされた変更がありません。チェックボックスでファイルを含めてください。"
            return
        }
        isCommitting = true
        defer { isCommitting = false }
        do {
            try await git.commit(message: trimmed)
            commitMessage = ""
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
