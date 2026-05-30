import Foundation

/// User-facing, classified error for a git operation.
///
/// Wraps a raw `git` stderr message into a structured form the UI can present:
/// a friendly title, a one-sentence summary, and a set of suggested recovery
/// actions the user can take. The original stderr/command is retained so the
/// "詳細" (Details) section can still surface the underlying message.
struct GitOperationError: Identifiable, LocalizedError, Equatable {
    let id = UUID()
    let operation: Operation
    let kind: Kind
    let title: String
    let summary: String
    let suggestions: [Suggestion]
    let rawStderr: String
    let command: String

    var errorDescription: String? { title }

    static func == (lhs: GitOperationError, rhs: GitOperationError) -> Bool {
        // Identity-based equality is enough for SwiftUI redraw triggers.
        lhs.id == rhs.id
    }

    // MARK: - Operation context

    enum Operation: Equatable {
        case push
        case pull
        case fetch
        case merge
        case commit
        case stage
        case unstage
        case switchBranch
        case createBranch
        case deleteBranch
        case clone
        case initRepo
        case other(String)

        var label: String {
            switch self {
            case .push: return L("プッシュ")
            case .pull: return L("プル")
            case .fetch: return L("フェッチ")
            case .merge: return L("マージ")
            case .commit: return L("コミット")
            case .stage: return L("ステージ")
            case .unstage: return L("アンステージ")
            case .switchBranch: return L("ブランチ切替")
            case .createBranch: return L("ブランチ作成")
            case .deleteBranch: return L("ブランチ削除")
            case .clone: return L("クローン")
            case .initRepo: return L("リポジトリ初期化")
            case .other(let s): return s
            }
        }

        /// Headline used as the error title when no kind-specific override is
        /// provided (e.g. unknown error categories).
        var failureLabel: String {
            switch self {
            case .push: return L("プッシュに失敗しました")
            case .pull: return L("プルに失敗しました")
            case .fetch: return L("フェッチに失敗しました")
            case .merge: return L("マージに失敗しました")
            case .commit: return L("コミットに失敗しました")
            case .stage: return L("ステージに失敗しました")
            case .unstage: return L("アンステージに失敗しました")
            case .switchBranch: return L("ブランチ切替に失敗しました")
            case .createBranch: return L("ブランチ作成に失敗しました")
            case .deleteBranch: return L("ブランチ削除に失敗しました")
            case .clone: return L("クローンに失敗しました")
            case .initRepo: return L("リポジトリ初期化に失敗しました")
            case .other: return L("操作に失敗しました")
            }
        }
    }

    // MARK: - Classified kinds

    /// Concrete failure categories that the classifier recognizes from `git`'s
    /// stderr. Keep these stable so UI / tests can switch on them.
    enum Kind: String, Equatable {
        /// Push rejected because remote has commits we don't have locally.
        case nonFastForward
        /// Pull / merge produced text-conflict markers in one or more files.
        case mergeConflict
        /// A merge / pull / checkout would clobber dirty working-tree changes.
        case localChangesWouldBeOverwritten
        /// Untracked working-tree files would be overwritten by a checkout / merge.
        case untrackedWouldBeOverwritten
        /// The current branch has no upstream set.
        case noUpstream
        /// Authentication failed (token expired, wrong password, SSH denied).
        case authFailed
        /// Network is unreachable / DNS lookup failed / TLS handshake failed.
        case networkUnreachable
        /// `git pull` was asked to merge two repos with no common history.
        case unrelatedHistories
        /// Remote server rejected push for non-FF / hook reasons.
        case remoteRejected
        /// Push was blocked by a protected-branch policy.
        case protectedBranch
        /// `user.name` / `user.email` is not configured.
        case missingIdentity
        /// `git commit` had nothing staged.
        case nothingToCommit
        /// `git branch <name>` collided with an existing branch.
        case branchAlreadyExists
        /// `git branch -d <name>` blocked because branch isn't fully merged.
        case branchNotFullyMerged
        /// `git branch -d <name>` blocked because branch is checked out.
        case branchCheckedOut
        /// Another git process is holding `index.lock`.
        case lockFileExists
        /// `git push` couldn't find the local ref to push.
        case srcRefspecMissing
        /// `git push` refused because we'd push from a shallow clone.
        case shallowUpdate
        /// We're in detached-HEAD state where the op makes no sense.
        case detachedHead
        /// SSH host key verification failed / not known.
        case hostKeyVerification
        /// A merge is already in progress; new merge attempt blocked.
        case mergeInProgress
        /// `pull --ff-only` could not fast-forward (diverged history).
        case divergedHistory
        /// Repo or path is not accessible (permissions / missing dir).
        case repositoryUnavailable
        /// Catch-all when no pattern matched.
        case unknown
    }

    // MARK: - Suggestions

    /// A recommended next step shown next to the error message. Some suggestions
    /// are *actionable* (e.g. open Pull from the UI); others are *advisory* and
    /// only carry text.
    struct Suggestion: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let detail: String?
        let action: Action?
        let isPrimary: Bool

        static func == (lhs: Suggestion, rhs: Suggestion) -> Bool { lhs.id == rhs.id }

        init(label: String, detail: String? = nil, action: Action? = nil, isPrimary: Bool = false) {
            self.label = label
            self.detail = detail
            self.action = action
            self.isPrimary = isPrimary
        }

        enum Action: Equatable {
            case pull
            case fetch
            case push
            case retry
            case openCommitTab
            case openIdentitySettings
            case openAccountSettings
            case openHelp(URL)
            case copyDetails
        }
    }
}
