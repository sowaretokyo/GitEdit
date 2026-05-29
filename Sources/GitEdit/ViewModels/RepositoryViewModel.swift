import Foundation
import SwiftUI

@MainActor
final class RepositoryViewModel: ObservableObject {
    // MARK: - Repository metadata
    let repository: Repository
    @Published var currentBranchName: String?
    @Published var upstream: String?
    @Published var ahead: Int = 0
    @Published var behind: Int = 0
    @Published var hasUncommittedChanges: Bool = false

    // MARK: - Branches
    @Published var localBranches: [Branch] = []
    @Published var remoteBranches: [Branch] = []
    @Published var isLoadingBranches: Bool = false

    // MARK: - Remotes
    @Published var remotes: [Remote] = []

    // MARK: - Network ops state
    @Published var isFetching: Bool = false
    @Published var isPulling: Bool = false
    @Published var isPushing: Bool = false

    // MARK: - User feedback
    @Published var operationError: String?
    @Published var operationSuccess: String?

    // MARK: - Refresh trigger for downstream view models
    @Published var dataVersion: Int = 0

    // MARK: - Sheet states
    @Published var isShowingCreateBranchSheet: Bool = false
    @Published var pendingSwitchBranch: Branch?  // confirmation dialog for switch with dirty tree

    let git: GitClient

    init(repository: Repository) {
        self.repository = repository
        self.git = GitClient(repository: repository.url)
    }

    var hasRemotes: Bool { !remotes.isEmpty }
    var hasUpstream: Bool { upstream != nil }

    var currentBranch: Branch? {
        guard let name = currentBranchName else { return nil }
        return localBranches.first { $0.name == name }
    }

    var isBusy: Bool { isFetching || isPulling || isPushing }

    // MARK: - Bootstrap & refresh

    func bootstrap() async {
        await refresh()
    }

    func refresh() async {
        async let branch: Void = refreshBranchInfo()
        async let branches: Void = refreshBranches()
        async let rems: Void = refreshRemotes()
        async let dirty: Void = refreshDirty()
        _ = await (branch, branches, rems, dirty)
    }

    func refreshBranchInfo() async {
        currentBranchName = try? await git.currentBranch()
        if let ab = await git.currentBranchUpstream() {
            upstream = ab.upstream
            ahead = ab.ahead
            behind = ab.behind
        } else {
            upstream = nil
            ahead = 0
            behind = 0
        }
    }

    func refreshBranches() async {
        isLoadingBranches = true
        defer { isLoadingBranches = false }
        async let local = try? await git.listLocalBranches()
        async let remote = try? await git.listRemoteBranches()
        localBranches = await local ?? []
        remoteBranches = await remote ?? []
    }

    func refreshRemotes() async {
        remotes = (try? await git.remotes()) ?? []
    }

    func refreshDirty() async {
        hasUncommittedChanges = await git.hasUncommittedChanges()
    }

    private func bumpDataVersion() {
        dataVersion &+= 1
    }

    // MARK: - Branch operations

    func requestSwitchBranch(_ branch: Branch) async {
        guard !branch.isCurrent else { return }
        if hasUncommittedChanges {
            pendingSwitchBranch = branch
        } else {
            await performSwitch(branch)
        }
    }

    func confirmSwitchAfterDirtyWarning() async {
        if let b = pendingSwitchBranch {
            pendingSwitchBranch = nil
            await performSwitch(b)
        }
    }

    func cancelSwitchAfterDirtyWarning() {
        pendingSwitchBranch = nil
    }

    private func performSwitch(_ branch: Branch) async {
        do {
            // For remote branches, create a tracking local branch with the same short name
            let targetName: String
            if branch.isRemote {
                if case .remote(let remoteName) = branch.kind,
                   branch.name.hasPrefix("\(remoteName)/") {
                    targetName = String(branch.name.dropFirst("\(remoteName)/".count))
                } else {
                    targetName = branch.name
                }
                // If a local branch with that name exists, just switch to it; otherwise create tracking branch.
                if localBranches.contains(where: { $0.name == targetName }) {
                    try await git.switchBranch(name: targetName)
                } else {
                    try await git.createBranch(name: targetName, startingFrom: branch.name, checkout: true)
                }
            } else {
                targetName = branch.name
                try await git.switchBranch(name: targetName)
            }
            await refresh()
            bumpDataVersion()
            operationSuccess = L("ブランチを切り替えました: %@", targetName)
        } catch {
            operationError = L("切替に失敗: %@", error.localizedDescription)
        }
    }

    func createBranch(name: String, startingFrom: String?, checkout: Bool) async {
        do {
            try await git.createBranch(name: name, startingFrom: startingFrom, checkout: checkout)
            await refresh()
            bumpDataVersion()
            operationSuccess = L("ブランチを作成しました: %@", name)
        } catch {
            operationError = L("作成に失敗: %@", error.localizedDescription)
        }
    }

    func mergeBranch(_ branch: Branch) async {
        do {
            try await git.merge(branch: branch.name, noFastForward: false)
            await refresh()
            bumpDataVersion()
            operationSuccess = L("マージしました: %@", branch.name)
        } catch {
            operationError = L("マージに失敗: %@", error.localizedDescription)
        }
    }

    func deleteBranch(_ branch: Branch, force: Bool = false) async {
        do {
            try await git.deleteBranch(name: branch.name, force: force)
            await refresh()
            operationSuccess = L("ブランチを削除しました: %@", branch.name)
        } catch {
            operationError = L("削除に失敗: %@", error.localizedDescription)
        }
    }

    // MARK: - Network operations

    func fetch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            try await git.fetch(allRemotes: true, prune: true)
            await refresh()
            bumpDataVersion()
            operationSuccess = L("取得が完了しました")
        } catch {
            operationError = L("取得に失敗: %@", error.localizedDescription)
        }
    }

    func pull() async {
        guard !isPulling else { return }
        isPulling = true
        defer { isPulling = false }
        do {
            try await git.pull()
            await refresh()
            bumpDataVersion()
            operationSuccess = L("取り込みが完了しました")
        } catch {
            operationError = L("取り込みに失敗: %@", error.localizedDescription)
        }
    }

    func push() async {
        guard !isPushing else { return }
        isPushing = true
        defer { isPushing = false }
        let needsUpstream = !hasUpstream
        do {
            try await git.push(setUpstream: needsUpstream)
            await refresh()
            bumpDataVersion()
            operationSuccess = needsUpstream ? L("ブランチを公開しました") : L("反映が完了しました")
        } catch {
            operationError = L("反映に失敗: %@", error.localizedDescription)
        }
    }

    func dismissFeedback() {
        operationError = nil
        operationSuccess = nil
    }
}
