import Foundation
import SwiftUI

@MainActor
final class ChangesViewModel: ObservableObject {
    @Published var changes: [FileChange] = []
    @Published var commitMessage: String = ""
    @Published var commitHistory: [String] = []
    @Published var currentBranch: String?
    @Published var isCommitting: Bool = false
    @Published var lastError: String?

    private let git: GitClient

    init(repository: Repository) {
        self.git = GitClient(repository: repository.url)
    }

    func refreshAll() async {
        async let st: Void = refreshStatus()
        async let hi: Void = loadHistory()
        async let br: Void = refreshBranch()
        _ = await (st, hi, br)
    }

    func refreshStatus() async {
        do {
            changes = try await git.status()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadHistory() async {
        do {
            commitHistory = try await git.recentCommitMessages(limit: 100)
        } catch {
            commitHistory = []
        }
    }

    func refreshBranch() async {
        currentBranch = try? await git.currentBranch()
    }

    func commit() async {
        let trimmed = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !changes.isEmpty else { return }
        isCommitting = true
        defer { isCommitting = false }
        do {
            try await git.stageAll()
            try await git.commit(message: trimmed)
            commitMessage = ""
            await refreshAll()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
