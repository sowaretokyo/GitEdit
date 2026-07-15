import Foundation

/// Builds and executes "abstracted" commit-history edits — reword, squash
/// into the previous commit, drop, and reorder (move up/down one slot) —
/// backed by a non-interactive `git rebase -i` (see `GitClient.rebaseInteractive`
/// for how the todo/message are injected without an actual editor).
///
/// Split into a pure planning half (`buildPlan`, `rowEditability`) that only
/// deals with SHA arrays and can be unit tested without a repository, and an
/// execution half (`Runner`) that talks to a real `GitClient`.
enum CommitHistoryEditor {

    // MARK: - Operations

    enum Operation: Equatable {
        case reword
        case drop
        case squashIntoPrevious
        case moveUp
        case moveDown
    }

    /// The revision the rebase replays onto. `.root` rewrites all the way
    /// back to the repository's first commit (`git rebase -i --root`).
    enum BaseKind: Equatable {
        case sha(String)
        case root

        /// Argument for `GitClient.rebaseInteractive`/`mergeCommitSHAs`:
        /// the base SHA, or `nil` to mean `--root`.
        var revisionArgument: String? {
            switch self {
            case .sha(let sha): return sha
            case .root: return nil
            }
        }
    }

    struct Plan: Equatable {
        let base: BaseKind
        /// One `<verb> <sha>` line per commit in the affected range, oldest
        /// first — the exact order `git rebase -i`'s todo file expects.
        let todoLines: [String]
        /// True when a `reword`/`squash` line is present and the caller must
        /// supply a commit message to `Runner.performEdit`.
        let needsMessage: Bool
    }

    enum PlanError: Error, Equatable {
        case targetIndexOutOfRange
        /// `squashIntoPrevious` on the oldest loaded commit — there's no
        /// earlier commit (loaded or otherwise known) to combine it into.
        case noPreviousCommitToSquashInto
        /// `moveUp` on the newest commit (index 0, HEAD) — nothing above it.
        case noCommitAbove
        /// `moveDown` on the oldest loaded commit — nothing below it that's
        /// actually loaded.
        case noCommitBelow
        /// The edit needs to know the parent of the oldest loaded commit in
        /// its range, but that commit isn't confirmed to be the repository's
        /// root — i.e. the 200-commit history window is truncated right at
        /// the boundary this edit needs. Disable the action rather than
        /// guess.
        case historyNotLoaded
    }

    // MARK: - Plan builder (pure)

    /// - Parameters:
    ///   - commitsNewestFirst: full SHAs, index 0 = HEAD, matching the order
    ///     `HistoryViewModel.commits` is already kept in.
    ///   - targetIndex: index of the commit being edited.
    ///   - isFullHistoryLoaded: true when `commitsNewestFirst` is known to
    ///     reach the repository's actual root commit (i.e. fewer commits
    ///     were returned than the fetch limit). Needed to disambiguate "no
    ///     parent loaded" (fine — that commit IS the root) from "no parent
    ///     loaded because the window is truncated" (not fine — reject).
    static func buildPlan(
        commitsNewestFirst: [String],
        targetIndex: Int,
        operation: Operation,
        isFullHistoryLoaded: Bool
    ) throws -> Plan {
        guard commitsNewestFirst.indices.contains(targetIndex) else {
            throw PlanError.targetIndexOutOfRange
        }

        switch operation {
        case .reword, .drop:
            let base = try resolveBase(
                oldestAffectedIndex: targetIndex,
                commitsNewestFirst: commitsNewestFirst,
                isFullHistoryLoaded: isFullHistoryLoaded
            )
            let verb = operation == .reword ? "reword" : "drop"
            let lines = (0...targetIndex).reversed().map { i -> String in
                let sha = commitsNewestFirst[i]
                return i == targetIndex ? "\(verb) \(sha)" : "pick \(sha)"
            }
            return Plan(base: base, todoLines: lines, needsMessage: operation == .reword)

        case .squashIntoPrevious:
            let previousIndex = targetIndex + 1
            guard commitsNewestFirst.indices.contains(previousIndex) else {
                throw PlanError.noPreviousCommitToSquashInto
            }
            let base = try resolveBase(
                oldestAffectedIndex: previousIndex,
                commitsNewestFirst: commitsNewestFirst,
                isFullHistoryLoaded: isFullHistoryLoaded
            )
            let lines = (0...previousIndex).reversed().map { i -> String in
                let sha = commitsNewestFirst[i]
                return i == targetIndex ? "squash \(sha)" : "pick \(sha)"
            }
            return Plan(base: base, todoLines: lines, needsMessage: true)

        case .moveUp:
            guard targetIndex > 0 else { throw PlanError.noCommitAbove }
            let base = try resolveBase(
                oldestAffectedIndex: targetIndex,
                commitsNewestFirst: commitsNewestFirst,
                isFullHistoryLoaded: isFullHistoryLoaded
            )
            var order = Array(0...targetIndex)
            order.swapAt(targetIndex - 1, targetIndex)
            let lines = order.reversed().map { "pick \(commitsNewestFirst[$0])" }
            return Plan(base: base, todoLines: lines, needsMessage: false)

        case .moveDown:
            let nextIndex = targetIndex + 1
            guard commitsNewestFirst.indices.contains(nextIndex) else {
                throw PlanError.noCommitBelow
            }
            let base = try resolveBase(
                oldestAffectedIndex: nextIndex,
                commitsNewestFirst: commitsNewestFirst,
                isFullHistoryLoaded: isFullHistoryLoaded
            )
            var order = Array(0...nextIndex)
            order.swapAt(targetIndex, nextIndex)
            let lines = order.reversed().map { "pick \(commitsNewestFirst[$0])" }
            return Plan(base: base, todoLines: lines, needsMessage: false)
        }
    }

    /// The base is the parent of the oldest commit the rebase needs to
    /// touch. If that parent isn't in the loaded window, we only know it's
    /// safe to treat as "no parent" (`.root`) when the window is confirmed
    /// to reach all the way back to the repository's start.
    static func resolveBase(
        oldestAffectedIndex: Int,
        commitsNewestFirst: [String],
        isFullHistoryLoaded: Bool
    ) throws -> BaseKind {
        let parentIndex = oldestAffectedIndex + 1
        if commitsNewestFirst.indices.contains(parentIndex) {
            return .sha(commitsNewestFirst[parentIndex])
        }
        if isFullHistoryLoaded, oldestAffectedIndex == commitsNewestFirst.count - 1 {
            return .root
        }
        throw PlanError.historyNotLoaded
    }

    // MARK: - Row editability (pure — drives context-menu enablement)

    struct RowEditability: Equatable {
        let canReword: Bool
        let canSquashIntoPrevious: Bool
        let canMoveUp: Bool
        let canMoveDown: Bool
        let canDrop: Bool

        static let allDisabled = RowEditability(
            canReword: false, canSquashIntoPrevious: false,
            canMoveUp: false, canMoveDown: false, canDrop: false
        )
    }

    /// Mirrors the runner's own pre-execution checks (merge commit / pushed
    /// commit in range) so the UI doesn't offer actions doomed to fail.
    static func rowEditability(
        commits: [Commit],
        targetIndex: Int,
        unpushedSHAs: Set<String>,
        isFullHistoryLoaded: Bool
    ) -> RowEditability {
        guard commits.indices.contains(targetIndex) else { return .allDisabled }
        let shas = commits.map(\.id)

        func rangeIsEditable(throughIndex endIndex: Int) -> Bool {
            guard commits.indices.contains(endIndex) else { return false }
            for i in 0...endIndex {
                if commits[i].isMerge { return false }
                if !unpushedSHAs.contains(commits[i].id) { return false }
            }
            return true
        }

        func hasBase(oldestAffectedIndex: Int) -> Bool {
            (try? resolveBase(
                oldestAffectedIndex: oldestAffectedIndex,
                commitsNewestFirst: shas,
                isFullHistoryLoaded: isFullHistoryLoaded
            )) != nil
        }

        let canRewordDrop = rangeIsEditable(throughIndex: targetIndex) && hasBase(oldestAffectedIndex: targetIndex)

        let previousIndex = targetIndex + 1
        let canSquash = rangeIsEditable(throughIndex: previousIndex) && hasBase(oldestAffectedIndex: previousIndex)

        let canUp = targetIndex > 0 && canRewordDrop

        let nextIndex = targetIndex + 1
        let canDown = rangeIsEditable(throughIndex: nextIndex) && hasBase(oldestAffectedIndex: nextIndex)

        return RowEditability(
            canReword: canRewordDrop,
            canSquashIntoPrevious: canSquash,
            canMoveUp: canUp,
            canMoveDown: canDown,
            canDrop: canRewordDrop
        )
    }

    // MARK: - Execution (GitClient-backed)

    enum ExecutionError: Error, Equatable {
        case dirtyWorkingTree
        case mergeCommitInRange
        case pushedCommitInRange
        /// The rebase failed mid-flight (conflict, or a change git couldn't
        /// apply, e.g. a hook rejection) and was aborted, restoring the
        /// pre-edit state.
        case conflict
        /// The rebase never started (or HEAD-reword's amend failed) —
        /// `message` carries the raw underlying description.
        case gitFailure(message: String)
    }

    struct EditResult: Equatable {
        let backupSHA: String
        let newHeadSHA: String
    }

    struct Runner {
        let git: GitClient

        /// Ref GitEdit points at the pre-edit HEAD so undo can restore it.
        static let backupRef = "refs/gitedit/undo"

        /// Performs one history edit end-to-end. Takes `targetIndex` (not a
        /// pre-built `Plan`) so it can special-case `reword` on HEAD
        /// (`targetIndex == 0`) as a plain `commit --amend`, skipping the
        /// rebase machinery entirely.
        func performEdit(
            commitsNewestFirst: [String],
            targetIndex: Int,
            operation: Operation,
            message: String?,
            isFullHistoryLoaded: Bool
        ) async throws -> EditResult {
            if operation == .reword, targetIndex == 0 {
                guard let message else { throw ExecutionError.gitFailure(message: "missing message") }
                return try await executeHeadRewordFastPath(message: message)
            }
            let plan = try buildPlan(
                commitsNewestFirst: commitsNewestFirst,
                targetIndex: targetIndex,
                operation: operation,
                isFullHistoryLoaded: isFullHistoryLoaded
            )
            return try await executeRebase(plan: plan, message: message)
        }

        // MARK: HEAD-reword fast path

        private func executeHeadRewordFastPath(message: String) async throws -> EditResult {
            guard !(await git.hasUncommittedChanges()) else {
                throw ExecutionError.dirtyWorkingTree
            }
            guard await git.isHeadUnpushed() else {
                throw ExecutionError.pushedCommitInRange
            }
            guard let oldHead = await git.headSHA() else {
                throw ExecutionError.gitFailure(message: "no HEAD")
            }
            try await git.updateRef(Runner.backupRef, to: oldHead)

            let messageURL = Self.tempFileURL()
            defer { try? FileManager.default.removeItem(at: messageURL) }
            do {
                try message.write(to: messageURL, atomically: true, encoding: .utf8)
                try await git.amendMessageOnly(messageFile: messageURL.path)
            } catch {
                await git.deleteRef(Runner.backupRef)
                throw ExecutionError.gitFailure(message: error.localizedDescription)
            }

            guard let newHead = await git.headSHA() else {
                throw ExecutionError.gitFailure(message: "no HEAD after amend")
            }
            return EditResult(backupSHA: oldHead, newHeadSHA: newHead)
        }

        // MARK: Rebase path

        private func executeRebase(plan: Plan, message: String?) async throws -> EditResult {
            guard !(await git.hasUncommittedChanges()) else {
                throw ExecutionError.dirtyWorkingTree
            }

            let rangeSHAs = Set(Self.shasInTodo(plan.todoLines))

            let mergeSHAs = await git.mergeCommitSHAs(base: plan.base.revisionArgument)
            guard Set(mergeSHAs).isDisjoint(with: rangeSHAs) else {
                throw ExecutionError.mergeCommitInRange
            }

            let unpushed = await git.unpushedCommitSHAs()
            guard rangeSHAs.isSubset(of: unpushed) else {
                throw ExecutionError.pushedCommitInRange
            }

            guard let oldHead = await git.headSHA() else {
                throw ExecutionError.gitFailure(message: "no HEAD")
            }
            try await git.updateRef(Runner.backupRef, to: oldHead)

            let todoURL = Self.tempFileURL()
            let messageURL: URL? = plan.needsMessage ? Self.tempFileURL() : nil
            defer {
                try? FileManager.default.removeItem(at: todoURL)
                if let messageURL { try? FileManager.default.removeItem(at: messageURL) }
            }

            do {
                try (plan.todoLines.joined(separator: "\n") + "\n")
                    .write(to: todoURL, atomically: true, encoding: .utf8)
                if let messageURL {
                    try (message ?? "").write(to: messageURL, atomically: true, encoding: .utf8)
                }
                try await git.rebaseInteractive(
                    base: plan.base.revisionArgument,
                    todoPath: todoURL.path,
                    messagePath: messageURL?.path
                )
            } catch {
                if await git.isRebaseInProgress() {
                    try? await git.rebaseAbort()
                    await git.deleteRef(Runner.backupRef)
                    throw ExecutionError.conflict
                } else {
                    await git.deleteRef(Runner.backupRef)
                    throw ExecutionError.gitFailure(message: error.localizedDescription)
                }
            }

            guard let newHead = await git.headSHA() else {
                throw ExecutionError.gitFailure(message: "no HEAD after rebase")
            }
            return EditResult(backupSHA: oldHead, newHeadSHA: newHead)
        }

        // MARK: Helpers

        /// Extracts the `<sha>` token from each `"<verb> <sha>"` todo line.
        private static func shasInTodo(_ lines: [String]) -> [String] {
            lines.compactMap { line in
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2 else { return nil }
                return String(parts[1])
            }
        }

        private static func tempFileURL() -> URL {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GitEdit-history-edit", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(UUID().uuidString)
        }
    }
}
