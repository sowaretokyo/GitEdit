import Foundation

/// Translates raw `git` failures into a `GitOperationError` enriched with a
/// friendly title, a one-sentence summary, and actionable suggestions.
///
/// The classifier is intentionally rule-based and case-insensitive: `git`'s
/// stderr is sometimes localized (Japanese installations, custom hooks), but
/// the vast majority of error tokens we care about (e.g. `non-fast-forward`,
/// `Authentication failed`) are stable English phrases the user can search.
///
/// Patterns are evaluated top-down; ordering matters because some messages
/// (e.g. "Authentication failed" inside a push response) must outrank generic
/// network errors. When no pattern matches we fall through to `.unknown` so
/// the user still gets the raw stderr in the details.
enum GitErrorClassifier {

    static func classify(_ error: Error, operation: GitOperationError.Operation) -> GitOperationError {
        // Already classified — don't double-wrap.
        if let opError = error as? GitOperationError {
            return opError
        }

        let (stderr, command): (String, String)
        if case let GitClient.GitError.commandFailed(_, raw, args) = error {
            stderr = raw
            command = "git " + args.joined(separator: " ")
        } else {
            stderr = error.localizedDescription
            command = ""
        }

        let normalized = stderr.lowercased()
        let kind = matchKind(stderr: normalized, operation: operation)
        return build(kind: kind, operation: operation, rawStderr: stderr, command: command)
    }

    /// Convenience wrapper used by tests: takes raw stderr text directly.
    static func classify(stderr: String, operation: GitOperationError.Operation, command: String = "") -> GitOperationError {
        let kind = matchKind(stderr: stderr.lowercased(), operation: operation)
        return build(kind: kind, operation: operation, rawStderr: stderr, command: command)
    }

    // MARK: - Pattern matching

    private static func matchKind(stderr s: String, operation: GitOperationError.Operation) -> GitOperationError.Kind {
        // Authentication — checked first because "Authentication failed" can
        // appear bundled with generic "fatal: unable to access" messages.
        if contains(s, anyOf: [
            "authentication failed",
            "could not read username",
            "could not read password",
            "invalid username or password",
            "support for password authentication was removed",
            "permission denied (publickey)",
            "permission denied, please try again",
            "remote: invalid username or token",
            "fatal: authentication"
        ]) {
            return .authFailed
        }

        // SSH host-key verification.
        if contains(s, anyOf: [
            "host key verification failed",
            "no matching host key type found",
            "the authenticity of host"
        ]) {
            return .hostKeyVerification
        }

        // Network connectivity.
        if contains(s, anyOf: [
            "could not resolve host",
            "could not resolve proxy",
            "connection timed out",
            "operation timed out",
            "failed to connect to",
            "network is unreachable",
            "ssl_connect",
            "ssl certificate problem",
            "could not connect to server",
            "the requested url returned error: 5",
            "rpc failed",
            "early eof",
            "unexpected disconnect"
        ]) {
            return .networkUnreachable
        }

        // Repository / path availability.
        if contains(s, anyOf: [
            "does not appear to be a git repository",
            "repository not found",
            "remote: repository not found",
            "fatal: not a git repository"
        ]) {
            return .repositoryUnavailable
        }

        // Lock file held by another git process.
        if contains(s, anyOf: [
            "index.lock",
            "another git process seems to be running",
            "unable to create '/.*\\.lock'"
        ]) {
            return .lockFileExists
        }

        // Identity (user.name / user.email).
        if contains(s, anyOf: [
            "please tell me who you are",
            "empty ident name",
            "no email was given and auto-detection is disabled"
        ]) {
            return .missingIdentity
        }

        // Nothing to commit.
        if contains(s, anyOf: [
            "nothing to commit",
            "no changes added to commit"
        ]) {
            return .nothingToCommit
        }

        // Push: protected-branch policies (server side).
        if contains(s, anyOf: [
            "protected branch",
            "gh001:",
            "gh006:",
            "policies disallowed",
            "branch is read-only"
        ]) {
            return .protectedBranch
        }

        // Push: src refspec doesn't match any.
        if contains(s, anyOf: [
            "src refspec",
            "does not match any"
        ]) && operation == .push {
            return .srcRefspecMissing
        }

        // Push from a shallow clone.
        if s.contains("shallow update not allowed") {
            return .shallowUpdate
        }

        // Push non-fast-forward.
        if contains(s, anyOf: [
            "non-fast-forward",
            "fetch first",
            "tip of your current branch is behind",
            "updates were rejected because the remote contains work",
            "updates were rejected because the tip of your current branch is behind",
            "updates were rejected because a pushed branch tip is behind"
        ]) {
            return .nonFastForward
        }

        // Generic "remote rejected" left over after the more specific cases.
        if contains(s, anyOf: [
            "remote rejected",
            "pre-receive hook declined",
            "rejected by remote",
            "! [remote rejected]"
        ]) {
            return .remoteRejected
        }

        // No upstream branch.
        if contains(s, anyOf: [
            "no upstream branch",
            "there is no tracking information for the current branch",
            "the current branch .* has no upstream branch"
        ]) {
            return .noUpstream
        }

        // Merge conflict (text-level).
        if contains(s, anyOf: [
            "conflict (content)",
            "conflict (modify/delete)",
            "conflict (add/add)",
            "conflict (rename/rename)",
            "automatic merge failed",
            "fix conflicts and then commit the result",
            "merge conflict in"
        ]) {
            return .mergeConflict
        }

        // Merge in progress.
        if contains(s, anyOf: [
            "you have not concluded your merge",
            "there is no merge to abort",
            "merge_head exists",
            "you are in the middle of a merge"
        ]) {
            return .mergeInProgress
        }

        // Unrelated histories.
        if s.contains("refusing to merge unrelated histories") {
            return .unrelatedHistories
        }

        // Diverged history on pull --ff-only.
        if contains(s, anyOf: [
            "not possible to fast-forward",
            "diverged",
            "non-fast-forward update"
        ]) {
            return .divergedHistory
        }

        // Local changes would be overwritten by checkout / merge / pull.
        if contains(s, anyOf: [
            "your local changes to the following files would be overwritten",
            "please commit your changes or stash them",
            "please, commit your changes or stash them"
        ]) {
            return .localChangesWouldBeOverwritten
        }

        // Untracked files would be overwritten.
        if contains(s, anyOf: [
            "the following untracked working tree files would be overwritten",
            "untracked working tree files would be overwritten"
        ]) {
            return .untrackedWouldBeOverwritten
        }

        // Branch already exists.
        if contains(s, anyOf: [
            "a branch named",
            "already exists"
        ]) && operation == .createBranch {
            return .branchAlreadyExists
        }

        // Branch not fully merged.
        if contains(s, anyOf: [
            "is not fully merged",
            "the branch .* is not fully merged"
        ]) {
            return .branchNotFullyMerged
        }

        // Branch is checked out elsewhere.
        if contains(s, anyOf: [
            "checked out at",
            "cannot delete branch .* checked out"
        ]) {
            return .branchCheckedOut
        }

        // Detached HEAD.
        if contains(s, anyOf: [
            "you are in 'detached head' state",
            "head detached at",
            "head is now at"
        ]) && (operation == .push || operation == .commit) && s.contains("detached") {
            return .detachedHead
        }

        return .unknown
    }

    // MARK: - Building the error payload

    private static func build(
        kind: GitOperationError.Kind,
        operation: GitOperationError.Operation,
        rawStderr: String,
        command: String
    ) -> GitOperationError {
        let copy = Texts.copy(kind: kind, operation: operation)
        return GitOperationError(
            operation: operation,
            kind: kind,
            title: copy.title,
            summary: copy.summary,
            suggestions: copy.suggestions,
            rawStderr: rawStderr,
            command: command
        )
    }

    // MARK: - Helpers

    /// Case-insensitive containment, with implicit regex when the needle looks
    /// like a pattern (contains `.*`). Plain strings are matched as literals.
    private static func contains(_ haystack: String, anyOf needles: [String]) -> Bool {
        for needle in needles {
            if needle.contains(".*") {
                if haystack.range(of: needle, options: .regularExpression) != nil {
                    return true
                }
            } else if haystack.contains(needle) {
                return true
            }
        }
        return false
    }
}

// MARK: - Friendly copy

extension GitErrorClassifier {

    /// Localized strings (title / summary / suggestions) for each classified
    /// kind. Centralized so tests and UI share the same wording.
    enum Texts {
        struct Copy {
            let title: String
            let summary: String
            let suggestions: [GitOperationError.Suggestion]
        }

        static func copy(kind: GitOperationError.Kind, operation: GitOperationError.Operation) -> Copy {
            switch kind {
            case .nonFastForward:
                return Copy(
                    title: L("リモートに新しいコミットがあります"),
                    summary: L("ローカルにない変更がリモートにあるため、このままではプッシュできません。先にプルしてリモートの変更を取り込んでください。"),
                    suggestions: [
                        .init(
                            label: L("プルして取り込む"),
                            detail: L("最新のリモートを取得してから再度プッシュします。"),
                            action: .pull,
                            isPrimary: true
                        ),
                        .init(
                            label: L("フェッチして差分を確認"),
                            detail: L("マージはせずに、まずリモートの状態を取得して確認します。"),
                            action: .fetch
                        ),
                        .init(
                            label: L("詳細をコピー"),
                            action: .copyDetails
                        )
                    ]
                )

            case .mergeConflict:
                return Copy(
                    title: L("マージコンフリクトが発生しました"),
                    summary: L("ローカルとリモートで同じ箇所が編集されているため、自動でマージできませんでした。各ファイルの競合マーカー（<<<<<<<）を解消してからコミットしてください。"),
                    suggestions: [
                        .init(
                            label: L("変更タブで競合ファイルを確認"),
                            detail: L("競合しているファイルを編集して、問題のある行を修正します。"),
                            action: .openCommitTab,
                            isPrimary: true
                        ),
                        .init(
                            label: L("競合解決のヘルプを開く"),
                            action: .openHelp(URL(string: "https://docs.github.com/ja/pull-requests/collaborating-with-pull-requests/addressing-merge-conflicts/about-merge-conflicts")!)
                        ),
                        .init(
                            label: L("詳細をコピー"),
                            action: .copyDetails
                        )
                    ]
                )

            case .localChangesWouldBeOverwritten:
                return Copy(
                    title: L("未コミットの変更で上書きされてしまいます"),
                    summary: L("作業ツリーに未コミットの変更があるため、この操作を続行すると変更が失われてしまいます。先にコミットするか退避（stash）してください。"),
                    suggestions: [
                        .init(
                            label: L("変更タブを開いてコミット"),
                            detail: L("作業中の変更をコミットしてから操作をやり直します。"),
                            action: .openCommitTab,
                            isPrimary: true
                        ),
                        .init(
                            label: L("詳細をコピー"),
                            action: .copyDetails
                        )
                    ]
                )

            case .untrackedWouldBeOverwritten:
                return Copy(
                    title: L("未追跡ファイルで上書きされてしまいます"),
                    summary: L("操作対象のブランチに、ローカルにある未追跡ファイルと同じパスのファイルが存在します。先にローカルのファイルを退避するか削除してから再度お試しください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .noUpstream:
                return Copy(
                    title: L("追跡先ブランチが設定されていません"),
                    summary: L("このブランチはまだリモートに紐付いていません。初回プッシュで追跡先を設定します。"),
                    suggestions: [
                        .init(
                            label: L("追跡先を設定してプッシュ"),
                            detail: L("origin に同名ブランチを作成し、以降のプッシュ／プルで自動的に追跡されるようにします。"),
                            action: .push,
                            isPrimary: true
                        ),
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .authFailed:
                return Copy(
                    title: L("認証に失敗しました"),
                    summary: L("リモートに対する認証が拒否されました。GitHub のトークンが期限切れ・権限不足、または SSH 鍵が登録されていない可能性があります。"),
                    suggestions: [
                        .init(
                            label: L("アカウント設定を開く"),
                            detail: L("GitHub に再サインインして、有効なトークンを発行し直します。"),
                            action: .openAccountSettings,
                            isPrimary: true
                        ),
                        .init(
                            label: L("認証のヘルプを開く"),
                            action: .openHelp(URL(string: "https://docs.github.com/ja/authentication/keeping-your-account-and-data-secure/about-authentication-to-github")!)
                        ),
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .networkUnreachable:
                return Copy(
                    title: L("ネットワークに接続できません"),
                    summary: L("リモートサーバーに到達できませんでした。インターネット接続・VPN・プロキシ設定を確認してください。"),
                    suggestions: [
                        .init(label: L("もう一度試す"), action: .retry, isPrimary: true),
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .unrelatedHistories:
                return Copy(
                    title: L("関連のない履歴をマージしようとしています"),
                    summary: L("ローカルとリモートに共通の祖先がありません。意図的にマージしたい場合は、コマンドラインで `git pull --allow-unrelated-histories` を実行してください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .remoteRejected:
                return Copy(
                    title: L("リモートサーバーに拒否されました"),
                    summary: L("プッシュがリモート側で拒否されました。サーバー側のフック（pre-receive など）またはポリシーで止められている可能性があります。詳細を確認してください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails, isPrimary: true)
                    ]
                )

            case .protectedBranch:
                return Copy(
                    title: L("保護されたブランチにはプッシュできません"),
                    summary: L("リモート側でこのブランチが保護されており、直接プッシュできません。プルリクエストを作成するか、別ブランチにプッシュしてください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .missingIdentity:
                return Copy(
                    title: L("コミット作者情報が未設定です"),
                    summary: L("`user.name` と `user.email` が設定されていないため、コミットを作成できません。Git のグローバル設定を行ってください。"),
                    suggestions: [
                        .init(
                            label: L("設定方法を表示"),
                            detail: L("ターミナルで以下を実行: git config --global user.name \"Your Name\" / git config --global user.email \"you@example.com\""),
                            action: .copyDetails,
                            isPrimary: true
                        )
                    ]
                )

            case .nothingToCommit:
                return Copy(
                    title: L("コミットできる変更がありません"),
                    summary: L("ステージされたファイルがないため、コミットを作成できません。変更タブでファイルにチェックを入れてからもう一度お試しください。"),
                    suggestions: [
                        .init(label: L("変更タブを開く"), action: .openCommitTab, isPrimary: true)
                    ]
                )

            case .branchAlreadyExists:
                return Copy(
                    title: L("同名のブランチがすでに存在します"),
                    summary: L("同じ名前のブランチがローカルに存在するため、新規作成できませんでした。別の名前を指定してください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .branchNotFullyMerged:
                return Copy(
                    title: L("ブランチが完全にマージされていません"),
                    summary: L("このブランチにはまだマージされていないコミットがあるため、通常の削除は拒否されました。意図的に削除する場合は強制削除を選んでください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .branchCheckedOut:
                return Copy(
                    title: L("チェックアウト中のブランチは削除できません"),
                    summary: L("削除しようとしているブランチは現在チェックアウトされています。別のブランチに切り替えてから削除してください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .lockFileExists:
                return Copy(
                    title: L("別の git プロセスが実行中の可能性があります"),
                    summary: L("リポジトリの `index.lock` が残っているため、新しい操作を開始できません。他の Git ツールが動いていないか確認し、少し待ってから再試行してください。"),
                    suggestions: [
                        .init(label: L("もう一度試す"), action: .retry, isPrimary: true),
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .srcRefspecMissing:
                return Copy(
                    title: L("プッシュ対象のブランチが見つかりません"),
                    summary: L("指定したブランチがローカルに存在しないため、プッシュできませんでした。一度ブランチを作成・コミットしてから再試行してください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .shallowUpdate:
                return Copy(
                    title: L("浅いクローンからはプッシュできません"),
                    summary: L("このリポジトリは shallow clone のため、リモートが受け入れない更新が含まれています。`git fetch --unshallow` で完全な履歴を取得してから再試行してください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .detachedHead:
                return Copy(
                    title: L("デタッチド HEAD 状態です"),
                    summary: L("現在どのブランチにもいません。先にブランチを作成または切り替えてから操作してください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .hostKeyVerification:
                return Copy(
                    title: L("SSH ホスト鍵を検証できませんでした"),
                    summary: L("リモートホストの SSH 鍵が `known_hosts` に登録されていないか、変更されています。一度ターミナルから接続して鍵を受け入れてください。"),
                    suggestions: [
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .mergeInProgress:
                return Copy(
                    title: L("マージが進行中です"),
                    summary: L("前回のマージがまだ完了していません。競合を解消してコミットするか、マージを中止してから再操作してください。"),
                    suggestions: [
                        .init(label: L("変更タブを開く"), action: .openCommitTab, isPrimary: true),
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .divergedHistory:
                return Copy(
                    title: L("ローカルとリモートの履歴が分岐しています"),
                    summary: L("Fast-forward でプルできません。ローカルにリモートにないコミットがあるため、マージかリベースが必要です。"),
                    suggestions: [
                        .init(label: L("フェッチして状況を確認"), action: .fetch, isPrimary: true),
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .repositoryUnavailable:
                return Copy(
                    title: L("リポジトリにアクセスできません"),
                    summary: L("リモートリポジトリが見つからないか、アクセス権がありません。URL とアクセス権限を確認してください。"),
                    suggestions: [
                        .init(label: L("アカウント設定を開く"), action: .openAccountSettings),
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )

            case .unknown:
                let trimmed = trim(operation)
                return Copy(
                    title: operation.failureLabel,
                    summary: trimmed.isEmpty ? L("詳細はログをご確認ください。") : trimmed,
                    suggestions: [
                        .init(label: L("もう一度試す"), action: .retry, isPrimary: true),
                        .init(label: L("詳細をコピー"), action: .copyDetails)
                    ]
                )
            }
        }

        private static func trim(_ operation: GitOperationError.Operation) -> String {
            // Unused for now but kept so the unknown copy can be enriched per-op
            // (e.g. tailoring the fallback summary) without touching call sites.
            _ = operation
            return ""
        }
    }
}
