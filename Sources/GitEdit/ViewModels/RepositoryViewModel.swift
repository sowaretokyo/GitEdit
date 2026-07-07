import Foundation
import SwiftUI

/// Whether the most recent history event can be undone.
enum UndoAvailability: Equatable {
    case none
    case available(UndoableOperation)
    case blocked(UndoBlockReason, UndoableOperation)
}

enum UndoBlockReason: Equatable {
    /// Undoing would rewrite a commit that's already been pushed to a remote.
    case pushedHistory
}

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

    // MARK: - Stash
    @Published var stashes: [StashEntry] = []
    @Published var isShowingStashSheet: Bool = false
    @Published var pendingStashDrop: StashEntry?

    // MARK: - Undo
    @Published var undoState: UndoAvailability = .none
    @Published var pendingUndo: UndoableOperation?
    @Published var undoBlockedMessage: String?

    // MARK: - Network ops state
    @Published var isFetching: Bool = false
    @Published var isPulling: Bool = false
    @Published var isPushing: Bool = false

    // MARK: - User feedback
    @Published var operationError: GitOperationError?
    @Published var operationSuccess: String?
    /// When set, the UI presents an inspector sheet with the full error details.
    @Published var inspectingError: GitOperationError?

    // MARK: - Refresh trigger for downstream view models
    @Published var dataVersion: Int = 0

    // MARK: - Merge state
    @Published var isMerging: Bool = false
    @Published var mergingBranchName: String?

    // MARK: - Sheet states
    @Published var isShowingCreateBranchSheet: Bool = false
    @Published var pendingSwitchBranch: Branch?  // confirmation dialog for switch with dirty tree
    @Published var pendingMergePull: Bool = false  // confirmation dialog for pull with diverged history
    @Published var pendingMergeBranch: Branch?
    @Published var pendingDeleteBranch: Branch?
    @Published var pendingForceDeleteBranch: Branch?

    let git: GitClient

    // MARK: - File-system watcher (real-time auto-refresh)
    private var fsWatcher: FileSystemWatcher?
    private var debounceTask: Task<Void, Never>?

    init(repository: Repository) {
        self.repository = repository
        self.git = GitClient(repository: repository.url)
    }

    deinit {
        // Tasks are released; FileSystemWatcher cleans itself up via deinit.
    }

    var hasRemotes: Bool { !remotes.isEmpty }
    var hasUpstream: Bool { upstream != nil }

    var currentBranch: Branch? {
        guard let name = currentBranchName else { return nil }
        return localBranches.first { $0.name == name }
    }

    var isBusy: Bool { isFetching || isPulling || isPushing }

    // MARK: - Issue links

    /// The GitHub repository resolved from `origin`'s fetch URL, or the
    /// first remote that resolves to a GitHub URL if there's no `origin`.
    var githubRepository: GitHubRepositoryRef? {
        if let originRemote = remotes.first(where: { $0.name == "origin" }),
           let fetchURL = originRemote.fetchURL,
           let ref = GitHubRemoteParser.parse(remoteURL: fetchURL) {
            return ref
        }
        for remote in remotes {
            if let fetchURL = remote.fetchURL,
               let ref = GitHubRemoteParser.parse(remoteURL: fetchURL) {
                return ref
            }
        }
        return nil
    }

    /// The GitHub issue URL encoded in the current branch's name (e.g.
    /// `123-fix-bug`). `nil` when there's no recognized GitHub remote, no
    /// current branch, or the branch name doesn't encode an issue number.
    var branchIssueURL: URL? {
        guard let repo = githubRepository,
              let branchName = currentBranchName,
              let number = IssueReferenceDetector.issueNumber(inBranch: branchName) else {
            return nil
        }
        return repo.issueURL(number)
    }

    // MARK: - Bootstrap & refresh

    func bootstrap() async {
        await refresh()
        startWatching()
    }

    // MARK: - File-system watching

    private func startWatching() {
        guard fsWatcher == nil else { return }
        let repoPath = repository.url.path
        fsWatcher = FileSystemWatcher(paths: [repoPath], latency: 0.25) { [weak self] paths in
            Task { @MainActor [weak self] in
                self?.scheduleAutoRefresh(touchedPaths: paths)
            }
        }
    }

    private func scheduleAutoRefresh(touchedPaths: Set<String>) {
        // Skip noise from transient git lock files (every git command bounces these).
        let names = touchedPaths.map { ($0 as NSString).lastPathComponent }
        let onlyTransient = !names.isEmpty && names.allSatisfy {
            $0 == "index.lock"
            || $0 == "HEAD.lock"
            || $0 == "COMMIT_EDITMSG"
            || $0 == "MERGE_MSG"
            || $0 == "ORIG_HEAD"
            || $0.hasSuffix(".swp")
            || $0.hasSuffix("~")
        }
        if onlyTransient { return }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.refreshBranchInfo()
            await self.refreshDirty()
            await self.refreshMergeState()
            await self.refreshUndoState()
            self.dataVersion &+= 1
        }
    }

    func refresh() async {
        async let branch: Void = refreshBranchInfo()
        async let branches: Void = refreshBranches()
        async let rems: Void = refreshRemotes()
        async let dirty: Void = refreshDirty()
        async let merge: Void = refreshMergeState()
        async let stash: Void = loadStashes()
        async let undoS: Void = refreshUndoState()
        _ = await (branch, branches, rems, dirty, merge, stash, undoS)
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

    /// Detects an in-progress merge (own or started from an external terminal).
    /// Only clears `mergingBranchName` when the merge is actually over — it's
    /// otherwise set explicitly by `mergeBranch` so the banner can name the
    /// branch being merged in.
    func refreshMergeState() async {
        let inProgress = await git.isMergeInProgress()
        isMerging = inProgress
        if !inProgress {
            mergingBranchName = nil
        }
    }

    /// Derives whether the last reflog event is undoable. Merges in progress
    /// and unborn/detached HEADs (both surfaced as an empty reflog read) are
    /// treated as "nothing to undo" rather than errors.
    func refreshUndoState() async {
        guard !isMerging else {
            undoState = .none
            return
        }
        let entries = (try? await git.reflogEntries(limit: 2)) ?? []
        guard let top = entries.first,
              let op = ReflogUndoDeriver.undoable(top: top, previous: entries.count > 1 ? entries[1] : nil) else {
            undoState = .none
            return
        }
        if op.isResetBased, !(await git.isHeadUnpushed()) {
            undoState = .blocked(.pushedHistory, op)
        } else {
            undoState = .available(op)
        }
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

    /// Confirmed from the dirty-switch dialog's "変更を退避して切り替え" option:
    /// stash (push only — never auto-pop, see `loadStashes` note on the
    /// stash section below) then proceed with the pending switch.
    func stashThenSwitchAfterDirtyWarning() async {
        guard let branch = pendingSwitchBranch else { return }
        pendingSwitchBranch = nil
        do {
            try await git.stashPush(
                message: L("%@ から切り替え前に退避", currentBranchName ?? ""),
                includeUntracked: true
            )
        } catch {
            report(error, operation: .stash)
            return
        }
        await refreshDirty()
        await loadStashes()
        await performSwitch(branch)
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
            report(error, operation: .switchBranch)
        }
    }

    func createBranch(name: String, startingFrom: String?, checkout: Bool) async {
        do {
            try await git.createBranch(name: name, startingFrom: startingFrom, checkout: checkout)
            await refresh()
            bumpDataVersion()
            operationSuccess = L("ブランチを作成しました: %@", name)
        } catch {
            report(error, operation: .createBranch)
        }
    }

    func requestMerge(_ branch: Branch) {
        pendingMergeBranch = branch
    }

    func cancelMerge() {
        pendingMergeBranch = nil
    }

    func confirmMerge() async {
        guard let branch = pendingMergeBranch else { return }
        pendingMergeBranch = nil
        await mergeBranch(branch)
    }

    func mergeBranch(_ branch: Branch) async {
        do {
            try await git.merge(branch: branch.name, noFastForward: false)
            await refresh()
            bumpDataVersion()
            operationSuccess = L("マージしました: %@", branch.name)
        } catch {
            // A merge conflict leaves MERGE_HEAD behind — confirm against that
            // rather than trusting the classified error kind, then surface it
            // via MergeConflictBanner instead of the red error banner.
            await refreshMergeState()
            if isMerging {
                mergingBranchName = branch.name
                await refresh()
                bumpDataVersion()
            } else {
                report(error, operation: .merge)
            }
        }
    }

    func continueMerge() async {
        do {
            try await git.continueMerge()
            mergingBranchName = nil
            await refresh()
            bumpDataVersion()
            operationSuccess = L("マージを完了しました")
        } catch {
            report(error, operation: .merge)
        }
    }

    func abortMerge() async {
        do {
            try await git.abortMerge()
            mergingBranchName = nil
            await refresh()
            bumpDataVersion()
            operationSuccess = L("マージを中止しました")
        } catch {
            report(error, operation: .merge)
        }
    }

    func requestDeleteBranch(_ branch: Branch) {
        pendingDeleteBranch = branch
    }

    func cancelDelete() {
        pendingDeleteBranch = nil
    }

    func confirmDeleteBranch() async {
        guard let branch = pendingDeleteBranch else { return }
        pendingDeleteBranch = nil
        await deleteBranch(branch)
    }

    func cancelForceDelete() {
        pendingForceDeleteBranch = nil
    }

    func confirmForceDeleteBranch() async {
        guard let branch = pendingForceDeleteBranch else { return }
        pendingForceDeleteBranch = nil
        await deleteBranch(branch, force: true)
    }

    func deleteBranch(_ branch: Branch, force: Bool = false) async {
        do {
            try await git.deleteBranch(name: branch.name, force: force)
            await refresh()
            operationSuccess = L("ブランチを削除しました: %@", branch.name)
        } catch {
            let classified = GitErrorClassifier.classify(error, operation: .deleteBranch)
            if !force, classified.kind == .branchNotFullyMerged {
                // Don't silently force-delete — let the user confirm losing commits.
                pendingForceDeleteBranch = branch
            } else {
                operationError = classified
            }
        }
    }

    // MARK: - Stash operations

    /// Re-reads the stash list from disk. Indexes shift after any drop/apply
    /// that removes an entry, so every mutating stash operation below calls
    /// this again rather than patching `stashes` in place.
    func loadStashes() async {
        stashes = (try? await git.stashList()) ?? []
    }

    func createStash(message: String, includeUntracked: Bool) async {
        do {
            try await git.stashPush(message: message.isEmpty ? nil : message, includeUntracked: includeUntracked)
            await refreshDirty()
            await loadStashes()
            bumpDataVersion()
            operationSuccess = L("変更を退避しました")
        } catch {
            report(error, operation: .stash)
        }
    }

    /// Applies a stash without removing it from the list.
    func applyStash(_ entry: StashEntry) async {
        do {
            try await git.stashApply(selector: entry.selector)
            await refresh()
            bumpDataVersion()
            operationSuccess = L("退避した変更を復元しました")
        } catch {
            await handleStashApplyFailure(error)
        }
    }

    /// Applies a stash and, only if the apply succeeded cleanly, drops it.
    /// Deliberately not implemented as `git stash pop` (which applies and
    /// drops as a single step): that command still drops the stash even when
    /// the apply left conflict markers behind in older git versions, and more
    /// importantly gives us no chance to re-verify the selector still points
    /// at the stash we think it does. We do that ourselves below so a failed
    /// or conflicted apply never loses the stash.
    func popStash(_ entry: StashEntry) async {
        do {
            try await git.stashApply(selector: entry.selector)
        } catch {
            await handleStashApplyFailure(error)
            return
        }
        // Apply succeeded. Re-resolve the selector before dropping — if the
        // stash list changed underneath us (e.g. another drop raced in),
        // `stash@{N}` may now name a different stash than the one we applied.
        if let sha = try? await git.stashSHA(selector: entry.selector), sha == entry.sha {
            do {
                try await git.stashDrop(selector: entry.selector)
            } catch {
                report(error, operation: .stashDrop)
            }
        } else {
            operationError = GitOperationError(
                operation: .stashDrop,
                kind: .unknown,
                title: L("退避の削除に失敗しました"),
                summary: L("退避一覧が変化しました。もう一度お試しください。"),
                suggestions: [],
                rawStderr: "",
                command: ""
            )
        }
        await refresh()
        bumpDataVersion()
        if operationError == nil {
            operationSuccess = L("退避した変更を復元しました")
        }
    }

    func requestDropStash(_ entry: StashEntry) {
        pendingStashDrop = entry
    }

    func cancelDropStash() {
        pendingStashDrop = nil
    }

    /// Re-verifies the selector still points at the stash the user confirmed
    /// dropping (same no-loss guarantee as `popStash`) before actually
    /// dropping it.
    func confirmDropStash() async {
        guard let entry = pendingStashDrop else { return }
        pendingStashDrop = nil
        guard let sha = try? await git.stashSHA(selector: entry.selector), sha == entry.sha else {
            operationError = GitOperationError(
                operation: .stashDrop,
                kind: .unknown,
                title: L("退避の削除に失敗しました"),
                summary: L("退避一覧が変化しました。もう一度お試しください。"),
                suggestions: [],
                rawStderr: "",
                command: ""
            )
            await loadStashes()
            return
        }
        do {
            try await git.stashDrop(selector: entry.selector)
            await loadStashes()
            bumpDataVersion()
            operationSuccess = L("退避を削除しました")
        } catch {
            report(error, operation: .stashDrop)
        }
    }

    /// A failed `stash apply`/`pop` needs special handling: `git` writes the
    /// actual `CONFLICT (...)` explanation to *stdout*, which we don't
    /// capture, so the classifier's stderr-based match on `.stashApplyConflict`
    /// rarely fires on its own (see the note in GitErrorClassifier). We
    /// confirm conflicts the same way `mergeBranch` does for regular merges —
    /// by checking real repo state — and only fall back to the classified
    /// error for other failure modes (e.g. "would be overwritten").
    private func handleStashApplyFailure(_ error: Error) async {
        let classified = GitErrorClassifier.classify(error, operation: .stashApply)
        let hasConflicts = ((try? await git.status()) ?? []).contains { $0.isConflicted }
        operationError = (hasConflicts || classified.kind == .stashApplyConflict)
            ? GitErrorClassifier.build(
                kind: .stashApplyConflict,
                operation: .stashApply,
                rawStderr: classified.rawStderr,
                command: classified.command
              )
            : classified
        await refresh()
        bumpDataVersion()
    }

    // MARK: - Undo operations

    func requestUndo() {
        switch undoState {
        case .none:
            break
        case .available(let op):
            pendingUndo = op
        case .blocked(.pushedHistory, _):
            undoBlockedMessage = L("プッシュ済みのコミットが含まれるため取り消せません。取り消すとリモートとの整合が崩れ、強制プッシュが必要になります。")
        }
    }

    func confirmUndo() async {
        guard let op = pendingUndo else { return }
        pendingUndo = nil
        await performUndo(op)
    }

    func cancelUndo() {
        pendingUndo = nil
    }

    func dismissUndoBlocked() {
        undoBlockedMessage = nil
    }

    private func performUndo(_ op: UndoableOperation) async {
        do {
            switch op {
            case .commit(let summary, let targetSHA), .amendCommit(let summary, let targetSHA):
                try await git.resetSoft(to: targetSHA)
                await refresh()
                bumpDataVersion()
                operationSuccess = L("取り消しました: %@", summary)
            case .mergeCommit(let summary, let targetSHA):
                try await git.resetHard(to: targetSHA)
                await refresh()
                bumpDataVersion()
                operationSuccess = L("取り消しました: %@", summary)
            case .branchSwitch(let from, _):
                try await git.checkoutRef(from)
                await refresh()
                bumpDataVersion()
                operationSuccess = L("取り消しました: %@", from)
            }
        } catch {
            switch op {
            case .branchSwitch:
                report(error, operation: .switchBranch)
            case .commit, .amendCommit, .mergeCommit:
                report(error, operation: .other(L("取り消し")))
            }
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
            operationSuccess = L("フェッチが完了しました")
        } catch {
            report(error, operation: .fetch)
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
            operationSuccess = L("プルが完了しました")
        } catch {
            // Diverged history isn't a failure the user needs an error banner
            // for — offer the merge-pull confirmation instead.
            let classified = GitErrorClassifier.classify(error, operation: .pull)
            if classified.kind == .divergedHistory {
                pendingMergePull = true
            } else {
                operationError = classified
            }
        }
    }

    /// Confirmed from the diverged-history dialog: merge the remote in via a
    /// regular (non-fast-forward) pull.
    func confirmMergePull() async {
        pendingMergePull = false
        guard !isPulling else { return }
        isPulling = true
        defer { isPulling = false }
        do {
            try await git.pullMerge()
            await refresh()
            bumpDataVersion()
            operationSuccess = L("マージしてプルしました")
        } catch {
            report(error, operation: .pull)
        }
    }

    func cancelMergePull() {
        pendingMergePull = false
    }

    func push() async {
        guard !isPushing else { return }
        isPushing = true
        defer { isPushing = false }
        let needsUpstream = !hasUpstream
        do {
            try await git.push(branch: needsUpstream ? currentBranchName : nil, setUpstream: needsUpstream)
            await refresh()
            bumpDataVersion()
            operationSuccess = needsUpstream ? L("ブランチをプッシュしました") : L("プッシュが完了しました")
        } catch {
            report(error, operation: .push)
        }
    }

    func dismissFeedback() {
        operationError = nil
        operationSuccess = nil
    }

    // MARK: - Error handling

    /// Funnels every catch site through the classifier so the banner and the
    /// detail inspector share a single, structured payload.
    func report(_ error: Error, operation: GitOperationError.Operation) {
        operationError = GitErrorClassifier.classify(error, operation: operation)
    }

    /// Show the detailed inspector sheet for the active error.
    func presentErrorDetails() {
        inspectingError = operationError
    }

    func dismissErrorDetails() {
        inspectingError = nil
    }

    // MARK: - Suggestion actions

    /// Executes the suggested follow-up action and dismisses the error.
    func perform(_ action: GitOperationError.Suggestion.Action) async {
        // Clear the visible banner first so the user sees the new operation
        // begin even if it also fails. The inspector sheet (if open) keeps
        // the original error around until explicitly dismissed.
        let originalError = operationError
        operationError = nil
        inspectingError = nil

        switch action {
        case .pull:
            await pull()
        case .fetch:
            await fetch()
        case .push:
            await push()
        case .retry:
            // Replay the original operation, if known.
            if let op = originalError?.operation {
                await retry(operation: op)
            }
        case .openCommitTab, .openIdentitySettings, .openAccountSettings, .openHelp, .copyDetails:
            // Handled by the view layer (it has access to NSWorkspace / clipboard
            // / tab selection state).
            break
        }
    }

    private func retry(operation op: GitOperationError.Operation) async {
        switch op {
        case .push: await push()
        case .pull: await pull()
        case .fetch: await fetch()
        case .merge, .commit, .stage, .unstage,
             .switchBranch, .createBranch, .deleteBranch,
             .clone, .initRepo, .stash, .stashApply, .stashDrop, .other:
            // No-op: these operations need their original arguments which we
            // didn't snapshot. The "Retry" suggestion is only surfaced for
            // network ops where re-running with the same args is safe.
            break
        }
    }
}
