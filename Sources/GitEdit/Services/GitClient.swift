import Foundation

/// Mutable holder so a background pipe-reader can hand its result back to the
/// termination handler without tripping Swift's concurrent `var`-capture check.
/// Safety: each box is written by exactly one reader, then read only after the
/// DispatchGroup join (a happens-before barrier).
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

final class GitClient: @unchecked Sendable {
    enum GitError: LocalizedError {
        case commandFailed(status: Int32, stderr: String, command: [String])
        case notARepository(URL)
        case parseFailure(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(_, let stderr, _):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? L("コマンドの実行に失敗しました") : trimmed
            case .notARepository(let url):
                return L("%@ は Git リポジトリではありません", url.path)
            case .parseFailure(let msg):
                return msg
            }
        }
    }

    let repositoryURL: URL

    init(repository: URL) {
        self.repositoryURL = repository
    }

    @discardableResult
    func run(_ arguments: String...) async throws -> String {
        try await Self.runGit(arguments, cwd: repositoryURL)
    }

    @discardableResult
    func run(_ arguments: [String], stdin: Data? = nil, env: [String: String]? = nil) async throws -> String {
        try await Self.runGit(arguments, cwd: repositoryURL, stdin: stdin, env: env)
    }

    // MARK: - Static runner (used by clone/init that don't have a repo yet)

    static func gitEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        env["PATH"] = normalizedPATH(current: env["PATH"], home: env["HOME"])
        env["LC_ALL"] = "C.UTF-8"
        env["GIT_TERMINAL_PROMPT"] = "0"
        // Skip git's "optional" locks so read commands like `status`/`diff`
        // never rewrite `.git/index` to refresh its stat cache. That rewrite
        // is what made our FSEvents watcher loop forever (status → index
        // rewrite → FSEvent → status …), and it also fought the user's own
        // terminal git over `index.lock`. Required locks (commit, add,
        // checkout) are unaffected — this only disables the optional ones.
        // Matches GitHub Desktop's behaviour.
        env["GIT_OPTIONAL_LOCKS"] = "0"
        return env
    }

    static func normalizedPATH(current: String?, home: String?) -> String {
        let fallback = "/usr/bin:/bin:/usr/sbin:/sbin"
        let existing = (current?.isEmpty == false ? current! : fallback)
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)

        let homePrefix = home?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var preferred = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/local/bin",
            "/opt/local/sbin"
        ]

        if let homePrefix, !homePrefix.isEmpty {
            let homePath = "/\(homePrefix)"
            preferred += [
                "\(homePath)/Library/pnpm",
                "\(homePath)/.local/bin",
                "\(homePath)/.npm-global/bin",
                "\(homePath)/.yarn/bin",
                "\(homePath)/.volta/bin",
                "\(homePath)/.asdf/shims",
                "\(homePath)/.nodenv/shims",
                "\(homePath)/.nvm/current/bin",
                "\(homePath)/.bun/bin",
                "\(homePath)/.deno/bin",
                "\(homePath)/.cargo/bin"
            ]
        }

        var seen = Set<String>()
        return (preferred + existing)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
    }

    @discardableResult
    static func runGit(_ arguments: [String], cwd: URL? = nil, stdin: Data? = nil, env: [String: String]? = nil) async throws -> String {
        let data = try await runGitData(arguments, cwd: cwd, stdin: stdin, env: env)
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    static func runGitData(_ arguments: [String], cwd: URL? = nil, stdin: Data? = nil, env: [String: String]? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            if let cwd { process.currentDirectoryURL = cwd }

            // Allow askpass / SSH agent to work but suppress interactive prompts.
            var mergedEnvironment = gitEnvironment()
            if let env {
                for (key, value) in env { mergedEnvironment[key] = value }
            }
            process.environment = mergedEnvironment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let stdinPipe: Pipe? = stdin.map { _ in Pipe() }
            if let stdinPipe { process.standardInput = stdinPipe }

            // Drain both pipes on background threads *while* git runs. Reading
            // only in terminationHandler deadlocks once output exceeds the OS
            // pipe buffer (~64KB): git blocks writing, never exits, and the
            // handler never fires. Affects large diffs, clone, fetch/push.
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "GitClient.pipe", attributes: .concurrent)
            let outBox = DataBox()
            let errBox = DataBox()
            group.enter()
            queue.async {
                outBox.data = stdout.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            queue.async {
                errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            process.terminationHandler = { proc in
                group.wait() // ensure both pipes are fully drained

                if proc.terminationStatus == 0 {
                    cont.resume(returning: outBox.data)
                } else {
                    let errStr = String(data: errBox.data, encoding: .utf8) ?? ""
                    cont.resume(throwing: GitError.commandFailed(
                        status: proc.terminationStatus,
                        stderr: errStr,
                        command: arguments
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
                return
            }

            if let stdin, let stdinPipe {
                queue.async {
                    // If git exits early (e.g. a malformed patch), the read end
                    // is already closed and this write breaks the pipe. That's
                    // not our error to report — the process's exit code /
                    // stderr is, so we just swallow it here with `try?`.
                    try? stdinPipe.fileHandleForWriting.write(contentsOf: stdin)
                    stdinPipe.fileHandleForWriting.closeFile()
                }
            }
        }
    }

    // MARK: - Repository-less ops

    static func clone(url: String, into destination: URL) async throws {
        do {
            let parent = destination.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try await runGit(["clone", "--progress", url, destination.path])
        } catch {
            throw GitErrorClassifier.classify(error, operation: .clone)
        }
    }

    static func initRepository(at directory: URL, initialBranch: String = "main") async throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await runGit(["init", "-b", initialBranch, directory.path])
        } catch {
            throw GitErrorClassifier.classify(error, operation: .initRepo)
        }
    }

    // MARK: - Repo metadata

    func isInsideRepository() async -> Bool {
        do {
            _ = try await run("rev-parse", "--git-dir")
            return true
        } catch {
            return false
        }
    }

    func currentBranch() async throws -> String {
        let output = try await run("symbolic-ref", "--short", "HEAD")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func currentBranchUpstream() async -> (upstream: String, ahead: Int, behind: Int)? {
        do {
            let upstream = try await run("rev-parse", "--abbrev-ref", "@{upstream}")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let ab = try await run("rev-list", "--left-right", "--count", "HEAD...@{upstream}")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = ab.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            let ahead = parts.first.flatMap(Int.init) ?? 0
            let behind = parts.dropFirst().first.flatMap(Int.init) ?? 0
            return (upstream, ahead, behind)
        } catch {
            return nil
        }
    }

    // MARK: - Status

    func status() async throws -> [FileChange] {
        let output = try await run("status", "--porcelain=v1", "-z", "-uall")
        return GitStatusParser.parse(porcelainV1Z: output)
    }

    func hasUncommittedChanges() async -> Bool {
        let output = (try? await run("status", "--porcelain")) ?? ""
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func recentCommitMessages(limit: Int = 100) async throws -> [String] {
        let sep = "\u{1F}"
        let output = try await run("log", "-n", String(limit), "--format=%s\(sep)")
        return output
            .split(separator: Character(sep), omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Staging

    func stage(path: String) async throws {
        try await runClassified(operation: .stage) {
            try await self.run("add", "--", path)
        }
    }

    func unstage(path: String) async throws {
        try await runClassified(operation: .unstage) {
            try await self.run("restore", "--staged", "--", path)
        }
    }

    func stageAll() async throws {
        try await runClassified(operation: .stage) {
            try await self.run("add", "-A")
        }
    }

    func unstageAll() async throws {
        try await runClassified(operation: .unstage) {
            try await self.run("restore", "--staged", ".")
        }
    }

    // MARK: - Discard

    /// Discard all changes to a tracked file, resetting both the index and the
    /// working tree to HEAD. Recoverable via reflog / the original commit.
    func discardTrackedChanges(path: String) async throws {
        try await run("restore", "--staged", "--worktree", "--", path)
    }

    /// Discard an untracked path by moving it to the macOS Trash (recoverable
    /// from Finder), rather than `git clean -f` which deletes permanently.
    /// If the path was `git add`-ed, also drop it from the index afterwards.
    func discardUntracked(path: String, wasStaged: Bool) async throws {
        let url = repositoryURL.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        if wasStaged {
            // Best-effort: clear the now-dangling index entry.
            _ = try? await run("restore", "--staged", "--", path)
        }
    }

    // MARK: - Commit

    func commit(message: String) async throws {
        try await runClassified(operation: .commit) {
            try await self.run("commit", "-m", message)
        }
    }

    /// Rewrites HEAD in place with whatever is currently staged plus `message`.
    func amendCommit(message: String) async throws {
        try await runClassified(operation: .commit) {
            try await self.run("commit", "--amend", "-m", message)
        }
    }

    // MARK: - Diff

    func diffAgainstHEAD(path: String) async throws -> String {
        // Before the first commit there is no HEAD, so `git diff HEAD` fails
        // with `fatal: bad revision 'HEAD'`. Fall back to diffing against the
        // empty tree so a staged-but-never-committed file still shows as added.
        let base: String
        if (try? await run("rev-parse", "--verify", "--quiet", "HEAD")) != nil {
            base = "HEAD"
        } else {
            base = try await run("hash-object", "-t", "tree", "/dev/null")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return try await run("diff", base, "--no-color", "--", path)
    }

    /// Worktree vs index — the part of a file's changes that isn't staged yet.
    func diffUnstaged(path: String) async throws -> String {
        try await run("diff", "--no-color", "--", path)
    }

    /// Index vs HEAD — the part of a file's changes that's already staged.
    func diffStaged(path: String) async throws -> String {
        try await run("diff", "--cached", "--no-color", "--", path)
    }

    /// Applies a hunk/line-level patch (built by `PatchBuilder`) to the index
    /// only. `reverse: false` stages (worktree → index); `reverse: true`
    /// unstages (index → HEAD, applied backwards).
    func applyPatch(_ patch: String, reverse: Bool) async throws {
        try await runClassified(operation: reverse ? .unstage : .stage) {
            var args = ["apply", "--cached", "--whitespace=nowarn"]
            if reverse { args.append("--reverse") }
            _ = try await self.run(args, stdin: Data(patch.utf8))
        }
    }

    func readFileFromWorkTree(path: String) -> String? {
        let url = repositoryURL.appendingPathComponent(path)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Raw bytes of `path` as it exists at `rev` (e.g. "HEAD", a SHA, or
    /// "<sha>^"). Returns `nil` if the path doesn't exist at that revision —
    /// which is the normal case for a file that was added or deleted there.
    func showFileData(rev: String, path: String) async -> Data? {
        try? await Self.runGitData(["show", "\(rev):\(path)"], cwd: repositoryURL)
    }

    /// Raw bytes of `path` as it currently sits in the working tree. Returns
    /// `nil` if the file doesn't exist (e.g. it was deleted).
    func worktreeFileData(path: String) -> Data? {
        let url = repositoryURL.appendingPathComponent(path)
        return try? Data(contentsOf: url)
    }

    // MARK: - Commit details

    /// Returns the list of files changed in a single commit.
    /// Uses `git show --format= --name-status -z` which handles root commits and
    /// merges via the default first-parent comparison.
    func filesInCommit(sha: String) async throws -> [FileChange] {
        let output = try await run("show", "--format=", "--name-status", "-z", "--no-color", sha)
        return Self.parseShowNameStatusZ(output)
    }

    /// Returns the per-file diff for a commit, with the empty commit-message
    /// header stripped so the DiffView gets just the patch portion.
    func diffForFile(in sha: String, path: String) async throws -> String {
        let output = try await run("show", "--format=", "--no-color", sha, "--", path)
        return String(output.drop(while: { $0 == "\n" || $0 == "\r" }))
    }

    private static func parseShowNameStatusZ(_ output: String) -> [FileChange] {
        // `--format=` leaves leading newlines; trim them before NUL-splitting.
        let trimmed = output.drop(while: { $0 == "\n" || $0 == "\r" })
        let entries = trimmed
            .split(separator: "\u{0}", omittingEmptySubsequences: true)
            .map(String.init)

        var result: [FileChange] = []
        var i = 0
        while i < entries.count {
            let statusToken = entries[i]
            guard let firstChar = statusToken.first else {
                i += 1
                continue
            }

            if firstChar == "R" || firstChar == "C" {
                // Rename/Copy: status, orig, new
                guard i + 2 < entries.count else { break }
                let orig = entries[i + 1]
                let new = entries[i + 2]
                result.append(FileChange(
                    path: new,
                    indexStatus: firstChar,
                    workingStatus: " ",
                    renameFrom: orig
                ))
                i += 3
            } else {
                guard i + 1 < entries.count else { break }
                let path = entries[i + 1]
                result.append(FileChange(
                    path: path,
                    indexStatus: firstChar,
                    workingStatus: " ",
                    renameFrom: nil
                ))
                i += 2
            }
        }
        return result
    }

    /// Plain-text search over tracked files via `git grep`.
    /// Returns one result per match (a line that contains `query`).
    func grep(query: String) async throws -> [GrepResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // -n: line numbers
        // -I: skip binary files
        // --null: NUL between path / line / content
        // --no-color: keep output plain
        // -F: treat query as fixed string (literal, not regex)
        // -i: case-insensitive (drop this for case-sensitive search)
        let output: String
        do {
            output = try await run("grep", "-n", "-I", "--null", "--no-color", "-F", "-i", "-e", trimmed)
        } catch let GitError.commandFailed(status, _, _) where status == 1 {
            // `git grep` exits 1 when there are zero matches; treat as empty.
            return []
        }
        return parseGrep(output)
    }

    private func parseGrep(_ output: String) -> [GrepResult] {
        var result: [GrepResult] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\u{0}", omittingEmptySubsequences: false)
            guard parts.count >= 3,
                  let lineNo = Int(parts[1]) else { continue }
            let path = String(parts[0])
            let content = parts.dropFirst(2).joined(separator: "\u{0}")
            result.append(GrepResult(path: path, lineNumber: lineNo, content: String(content)))
        }
        return result
    }

    func writeFile(path: String, content: String) throws {
        let url = repositoryURL.appendingPathComponent(path)
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - History

    /// Separators for `recentCommits`' `git log --format=...` output, exposed
    /// so tests can build matching fixture strings for `parseRecentCommits`.
    static let recentCommitsRecordSeparator = "\u{1E}"
    static let recentCommitsFieldSeparator = "\u{1F}"

    func recentCommits(limit: Int = 200) async throws -> [Commit] {
        let RS = Self.recentCommitsRecordSeparator
        let US = Self.recentCommitsFieldSeparator
        // %B = raw body (including the subject line and any Co-Authored-By
        // trailers). We pull it so CoAuthorParser can extract co-authors.
        // %P = space-separated parent SHAs; two or more means a merge commit.
        let output = try await run(
            "log", "-n", String(limit),
            "--format=%H\(US)%h\(US)%aI\(US)%an\(US)%ae\(US)%s\(US)%P\(US)%B\(RS)"
        )
        return Self.parseRecentCommits(output)
    }

    /// Parses `recentCommits`' `git log` output into `Commit`s. Extracted as
    /// a static, pure function so the field-splitting/isMerge logic can be
    /// unit tested without a real repository.
    static func parseRecentCommits(_ output: String) -> [Commit] {
        let RS = recentCommitsRecordSeparator
        let US = recentCommitsFieldSeparator
        let formatter = ISO8601DateFormatter()
        var commits: [Commit] = []
        for record in output.split(separator: Character(RS), omittingEmptySubsequences: true) {
            // `maxSplits: 7` keeps newlines inside %B from being treated as
            // field boundaries by accident.
            let fields = record
                .split(separator: Character(US), maxSplits: 7, omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count >= 8 else { continue }
            let dateStr = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let date = formatter.date(from: dateStr) ?? .distantPast
            let parentCount = fields[6]
                .split(separator: " ", omittingEmptySubsequences: true)
                .count
            let rawBody = fields[7]
            commits.append(Commit(
                id: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
                shortSHA: fields[1],
                summary: fields[5].trimmingCharacters(in: .whitespacesAndNewlines),
                body: rawBody,
                author: fields[3],
                authorEmail: fields[4],
                date: date,
                coAuthors: CoAuthorParser.parse(from: rawBody),
                isMerge: parentCount >= 2
            ))
        }
        return commits
    }

    /// Full SHAs of commits reachable from HEAD but not from any remote-tracking
    /// branch — i.e. commits that have not been pushed anywhere yet. Returns an
    /// empty set if everything is pushed (or on error).
    func unpushedCommitSHAs() async -> Set<String> {
        guard let output = try? await run("rev-list", "HEAD", "--not", "--remotes") else {
            return []
        }
        let shas = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Set(shas)
    }

    /// The HEAD commit's subject/body, or nil if there is no commit yet.
    func headCommitMessage() async -> (summary: String, body: String)? {
        let sep = "\u{1F}"
        guard let raw = try? await run("log", "-1", "--format=%s\(sep)%b") else { return nil }
        return Self.parseHeadMessage(raw, separator: sep)
    }

    /// Splits `git log --format=%s<sep>%b` output into subject and body.
    static func parseHeadMessage(_ raw: String, separator sep: String) -> (summary: String, body: String)? {
        let parts = raw.components(separatedBy: sep)
        guard let first = parts.first else { return nil }
        return (
            first.trimmingCharacters(in: .whitespacesAndNewlines),
            parts.dropFirst().joined(separator: sep).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// True when HEAD exists and hasn't been pushed to any remote yet.
    func isHeadUnpushed() async -> Bool {
        guard let head = try? await run("rev-parse", "HEAD")
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !head.isEmpty else { return false }
        return await unpushedCommitSHAs().contains(head)
    }

    // MARK: - Commit history editing (reword / squash / drop / reorder)

    /// Full SHA of HEAD, or `nil` if there is no commit yet.
    func headSHA() async -> String? {
        guard let sha = try? await run("rev-parse", "HEAD")
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !sha.isEmpty else { return nil }
        return sha
    }

    /// Points `ref` (e.g. the commit-edit backup ref) at `sha`.
    func updateRef(_ ref: String, to sha: String) async throws {
        try await run("update-ref", ref, sha)
    }

    /// Removes `ref`. Always best-effort: a ref that's already gone (or a
    /// repository that vanished mid-cleanup) isn't something callers need to
    /// react to, so failures are swallowed rather than thrown.
    func deleteRef(_ ref: String) async {
        _ = try? await run("update-ref", "-d", ref)
    }

    /// True when an interactive rebase is in progress (ours or one started
    /// from an external terminal), detected via `<gitdir>/rebase-merge` —
    /// the directory `git rebase -i` uses (as opposed to `rebase-apply`,
    /// used by the non-interactive/am-based path this app never invokes).
    func isRebaseInProgress() async -> Bool {
        guard let gitDir = try? await run("rev-parse", "--absolute-git-dir")
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !gitDir.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: gitDir + "/rebase-merge")
    }

    /// Aborts an in-progress rebase, restoring the pre-rebase HEAD.
    func rebaseAbort() async throws {
        _ = try? await run("rebase", "--abort")
    }

    /// Runs `git rebase -i` with the todo list and (optionally) a commit
    /// message supplied via environment-injected editors instead of an
    /// actual terminal editor.
    ///
    /// `GIT_SEQUENCE_EDITOR="cp '<todoPath>'"` replaces the rebase todo file
    /// with ours; `GIT_EDITOR="cp '<messagePath>'"` replaces the message
    /// editor git would otherwise open for a `reword`/`squash` step.
    /// `-c core.editor` / `-c sequence.editor` do NOT work here — git only
    /// consults those for the outer rebase invocation, not the internal
    /// `commit --amend` it runs per `reword`/`squash` step, so a message set
    /// that way never reaches the rewritten commit and the step silently
    /// keeps git's own placeholder text instead (confirmed by hand before
    /// relying on this).
    ///
    /// - Parameters:
    ///   - base: revision to rebase onto, or `nil` to rewrite from the root.
    ///   - todoPath: file containing the todo list, one line per commit.
    ///   - messagePath: file containing the commit message, required when
    ///     the plan includes a `reword` or `squash` step. When `nil`,
    ///     `GIT_EDITOR=true` is used so no editor launches at all.
    func rebaseInteractive(base: String?, todoPath: String, messagePath: String?) async throws {
        var args = ["rebase", "-i"]
        if let base { args.append(base) } else { args.append("--root") }
        let sequenceEditor = "cp '\(todoPath)'"
        let editor = messagePath.map { "cp '\($0)'" } ?? "true"
        try await run(args, env: [
            "GIT_SEQUENCE_EDITOR": sequenceEditor,
            "GIT_EDITOR": editor
        ])
    }

    /// Fast path for rewording HEAD's message alone: amends HEAD in place
    /// using `-F <file>` for the message, skipping the editor entirely via
    /// `-c core.editor=true`. No rebase needed since only HEAD moves.
    func amendMessageOnly(messageFile: String) async throws {
        try await run(["-c", "core.editor=true", "commit", "--amend", "-F", messageFile])
    }

    /// SHAs of commits reachable from `base` (exclusive) to `HEAD` that are
    /// merge commits, used to double-check a history-edit range doesn't
    /// touch one before running the rebase. `base: nil` checks all the way
    /// back to the root commit.
    func mergeCommitSHAs(base: String?) async -> [String] {
        let range = base.map { "\($0)..HEAD" } ?? "HEAD"
        guard let output = try? await run("rev-list", "--merges", range) else { return [] }
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Stash

    func stashList() async throws -> [StashEntry] {
        let output = try await run("stash", "list", "--format=\(StashListParser.formatTemplate)")
        return StashListParser.parse(output)
    }

    func stashPush(message: String?, includeUntracked: Bool) async throws {
        try await runClassified(operation: .stash) {
            var args = ["stash", "push"]
            if includeUntracked { args.append("-u") }
            if let message, !message.isEmpty { args.append(contentsOf: ["-m", message]) }
            try await self.run(args)
        }
    }

    /// Applies (without dropping) the stash at `selector`. On a real content
    /// conflict, `git` writes conflict markers into the working tree, leaves
    /// the stash in the list, and prints its `CONFLICT` details to *stdout*
    /// (not stderr) — so callers should not rely solely on the thrown error's
    /// message to detect a conflict; check working-tree status afterwards.
    func stashApply(selector: String) async throws {
        try await runClassified(operation: .stashApply) {
            try await self.run("stash", "apply", selector)
        }
    }

    func stashDrop(selector: String) async throws {
        try await runClassified(operation: .stashDrop) {
            try await self.run("stash", "drop", selector)
        }
    }

    /// Resolves a `stash@{N}` selector to its current full SHA, so callers can
    /// confirm a selector still refers to the stash they think it does before
    /// a destructive follow-up (e.g. drop after pop).
    func stashSHA(selector: String) async throws -> String {
        try await run("rev-parse", selector).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Undo (reflog-based)

    func reflogEntries(limit: Int = 2) async throws -> [ReflogEntry] {
        let output = try await run("reflog", "-n", String(limit), "--format=\(ReflogParser.formatTemplate)")
        return ReflogParser.parse(output)
    }

    /// Moves HEAD (and the current branch) to `ref`, keeping the difference
    /// staged. Used to undo a commit/amend.
    func resetSoft(to ref: String) async throws {
        try await runClassified(operation: .other(L("取り消し"))) {
            try await self.run("reset", "--soft", ref)
        }
    }

    /// Moves HEAD (and the current branch) to `ref`, discarding the working
    /// tree and index difference. Used to undo a merge.
    func resetHard(to ref: String) async throws {
        try await runClassified(operation: .other(L("取り消し"))) {
            try await self.run("reset", "--hard", ref)
        }
    }

    /// Checks out `ref` directly (as opposed to `switchBranch`, which uses
    /// `git switch`). Used to undo a branch switch back to the exact prior
    /// ref, which may itself be a branch name.
    func checkoutRef(_ ref: String) async throws {
        try await runClassified(operation: .switchBranch) {
            try await self.run("checkout", ref)
        }
    }

    /// The files touched by a stash entry, for the "退避内容を表示" preview.
    /// `git stash show` diffs the stash against its parent commit, so this
    /// reuses the same `--name-status -z` parsing as `filesInCommit`.
    func stashShowFiles(selector: String) async throws -> [FileChange] {
        let output = try await run("stash", "show", "--name-status", "-z", "--no-color", selector)
        return Self.parseShowNameStatusZ(output)
    }

    /// True when the installed `git` supports `stash push --staged`
    /// (added in git 2.35), which `stashPartial` relies on.
    func supportsStagedStash() async -> Bool {
        guard let output = try? await run("--version") else { return false }
        return Self.gitVersionAtLeast(output, major: 2, minor: 35)
    }

    /// Parses the first `MAJOR.MINOR` version number found in `versionOutput`
    /// (accepts both raw "2.35.0" and full "git version 2.50.1 (Apple
    /// Git-155)" output) and compares it against `major`.`minor`. Returns
    /// `false` for malformed or empty input rather than throwing, since
    /// callers use this only to decide whether to offer a feature.
    static func gitVersionAtLeast(_ versionOutput: String, major: Int, minor: Int) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\.(\d+)"#) else { return false }
        let ns = versionOutput as NSString
        guard let match = regex.firstMatch(in: versionOutput, range: NSRange(location: 0, length: ns.length)),
              let foundMajor = Int(ns.substring(with: match.range(at: 1))),
              let foundMinor = Int(ns.substring(with: match.range(at: 2))) else {
            return false
        }
        if foundMajor != major { return foundMajor > major }
        return foundMinor >= minor
    }

    /// Stashes only the changes described by `patch` (a hunk/line-level patch
    /// built against HEAD by `PatchBuilder`), leaving everything else in the
    /// working tree untouched. Requires git 2.35+ — check
    /// `supportsStagedStash()` before offering this.
    ///
    /// Implementation ("write-tree/read-tree dance"):
    /// 1. `write-tree` snapshots the *current* index so it can be restored
    ///    exactly regardless of what happens below.
    /// 2. `read-tree HEAD` resets the index to HEAD without touching the
    ///    working tree, giving a clean slate to stage only the selection.
    /// 3. `apply --cached` stages just the selected hunks/lines from `patch`.
    /// 4. `stash push --staged` stashes exactly what's now staged and rolls
    ///    back only that content from the working tree.
    /// The index snapshotted in step 1 is restored on every exit path —
    /// success or failure — so this never leaves the index in the
    /// intermediate "HEAD + selection" state.
    func stashPartial(patch: String, message: String?) async throws {
        try await runClassified(operation: .stashPartial) {
            let savedTree = try await self.run("write-tree").trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                try await self.run("read-tree", "HEAD")
                _ = try await self.run(["apply", "--cached", "--whitespace=nowarn"], stdin: Data(patch.utf8))
                var args = ["stash", "push", "--staged"]
                if let message, !message.isEmpty { args.append(contentsOf: ["-m", message]) }
                try await self.run(args)
            } catch {
                _ = try? await self.run("read-tree", savedTree)
                throw error
            }
            try await self.run("read-tree", savedTree)
        }
    }

    // MARK: - Branches

    func listLocalBranches() async throws -> [Branch] {
        let output = try await run(
            "for-each-ref",
            "--sort=-committerdate",
            "--format=\(GitBranchParser.formatTemplate)",
            "refs/heads"
        )
        return GitBranchParser.parse(output, kind: .local)
    }

    func listRemoteBranches() async throws -> [Branch] {
        let remoteNames = (try? await remotes().map(\.name)) ?? []
        let output = try await run(
            "for-each-ref",
            "--sort=-committerdate",
            "--format=\(GitBranchParser.formatTemplate)",
            "refs/remotes"
        )
        let raw = GitBranchParser.parse(output, kind: .remote(name: ""))
        // Each raw branch's `name` is like "origin/main". Re-tag with detected remote prefix.
        return raw.map { b in
            let remoteName: String = {
                if let match = remoteNames.first(where: { b.name.hasPrefix("\($0)/") }) {
                    return match
                }
                return String(b.name.split(separator: "/").first ?? "origin")
            }()
            return Branch(
                name: b.name,
                kind: .remote(name: remoteName),
                isCurrent: false,
                upstream: nil,
                upstreamGone: false,
                ahead: b.ahead,
                behind: b.behind,
                sha: b.sha,
                subject: b.subject,
                authorName: b.authorName,
                lastCommitDate: b.lastCommitDate
            )
        }
    }

    func createBranch(name: String, startingFrom: String? = nil, checkout: Bool = true) async throws {
        try await runClassified(operation: .createBranch) {
            if checkout {
                var args = ["checkout", "-b", name]
                if let start = startingFrom { args.append(start) }
                try await self.run(args)
            } else {
                var args = ["branch", name]
                if let start = startingFrom { args.append(start) }
                try await self.run(args)
            }
        }
    }

    func switchBranch(name: String) async throws {
        try await runClassified(operation: .switchBranch) {
            try await self.run("switch", name)
        }
    }

    /// Creates `name` from `startPoint` and switches to it in one step, with
    /// explicit upstream tracking (`git switch -c <name> --track <startPoint>`).
    /// Used for pull-request checkout so the new branch has the right
    /// upstream wired up immediately, without a separate
    /// `branch --set-upstream-to` call.
    func switchCreatingTrackingBranch(name: String, startPoint: String) async throws {
        try await runClassified(operation: .switchBranch) {
            try await self.run("switch", "-c", name, "--track", startPoint)
        }
    }

    func deleteBranch(name: String, force: Bool = false) async throws {
        try await runClassified(operation: .deleteBranch) {
            try await self.run("branch", force ? "-D" : "-d", name)
        }
    }

    func merge(branch: String, noFastForward: Bool = false) async throws {
        try await runClassified(operation: .merge) {
            var args = ["merge"]
            if noFastForward { args.append("--no-ff") }
            args.append(branch)
            try await self.run(args)
        }
    }

    // MARK: - Merge conflict resolution

    /// Whether a merge is currently in progress (i.e. `MERGE_HEAD` exists).
    func isMergeInProgress() async -> Bool {
        (try? await run("rev-parse", "-q", "--verify", "MERGE_HEAD")) != nil
    }

    /// Replace `path` with the version from the current branch ("ours").
    func checkoutOurs(path: String) async throws {
        try await runClassified(operation: .merge) {
            try await self.run("checkout", "--ours", "--", path)
        }
    }

    /// Replace `path` with the version from the branch being merged in ("theirs").
    func checkoutTheirs(path: String) async throws {
        try await runClassified(operation: .merge) {
            try await self.run("checkout", "--theirs", "--", path)
        }
    }

    /// Mark a conflicted path as resolved by staging it.
    func markResolved(path: String) async throws {
        try await runClassified(operation: .merge) {
            try await self.run("add", "-A", "--", path)
        }
    }

    /// Conclude an in-progress merge. `core.editor=true` skips the commit-message
    /// editor since git already prepared a merge commit message.
    func continueMerge() async throws {
        try await runClassified(operation: .merge) {
            try await self.run("-c", "core.editor=true", "merge", "--continue")
        }
    }

    /// Abort an in-progress merge, restoring the pre-merge working tree.
    func abortMerge() async throws {
        try await runClassified(operation: .merge) {
            try await self.run("merge", "--abort")
        }
    }

    // MARK: - Remotes & Network

    func remotes() async throws -> [Remote] {
        let output = try await run("remote", "-v")
        var byName: [String: (fetch: String?, push: String?)] = [:]
        for raw in output.split(separator: "\n") {
            let line = String(raw)
            // Format: name<TAB>url (fetch|push)
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard parts.count >= 3 else { continue }
            let name = parts[0]
            let url = parts[1]
            let kind = parts[2]
            var entry = byName[name] ?? (nil, nil)
            if kind.contains("fetch") { entry.fetch = url }
            if kind.contains("push") { entry.push = url }
            byName[name] = entry
        }
        return byName.map { Remote(name: $0.key, fetchURL: $0.value.fetch, pushURL: $0.value.push) }
            .sorted { $0.name < $1.name }
    }

    func fetch(remote: String? = nil, allRemotes: Bool = false, prune: Bool = true) async throws {
        try await runClassified(operation: .fetch) {
            var args = ["fetch", "--progress"]
            if prune { args.append("--prune") }
            if allRemotes {
                args.append("--all")
            } else if let remote {
                args.append(remote)
            }
            try await self.run(args)
        }
    }

    /// Fetches a single refspec (e.g. a branch name, or
    /// `pull/42/head:pr/42` to materialize a PR's head as a local branch)
    /// without touching any other refs. Used by pull-request checkout, which
    /// needs an exact ref rather than a full `--prune --all` sync.
    func fetch(remote: String = "origin", refspec: String) async throws {
        try await runClassified(operation: .fetch) {
            try await self.run("fetch", remote, refspec)
        }
    }

    /// Fast-forward only pull. Fails if not fast-forwardable; caller can show the error.
    func pull(remote: String = "origin") async throws {
        try await runClassified(operation: .pull) {
            try await self.run("pull", "--ff-only", "--progress", remote)
        }
    }

    /// Pull that merges instead of fast-forwarding, for when the caller has
    /// already confirmed diverged local/remote histories should be combined.
    func pullMerge(remote: String = "origin") async throws {
        try await runClassified(operation: .pull) {
            try await self.run("pull", "--no-rebase", "--progress", remote)
        }
    }

    /// Push current branch to `remote`. If `setUpstream` is true, also `-u`.
    func push(remote: String = "origin", branch: String? = nil, setUpstream: Bool = false) async throws {
        try await runClassified(operation: .push) {
            var args = ["push", "--progress"]
            if setUpstream { args.append("-u") }
            args.append(remote)
            if let branch { args.append(branch) }
            try await self.run(args)
        }
    }

    // MARK: - Error classification

    /// Runs `body` and translates any thrown `GitError.commandFailed` into a
    /// `GitOperationError` tagged with the given operation. Other errors are
    /// rethrown verbatim. Call sites get a single, structured error type to
    /// drive the UI without duplicating classification logic everywhere.
    @discardableResult
    private func runClassified<T>(
        operation: GitOperationError.Operation,
        _ body: () async throws -> T
    ) async throws -> T {
        do {
            return try await body()
        } catch let opError as GitOperationError {
            throw opError
        } catch {
            throw GitErrorClassifier.classify(error, operation: operation)
        }
    }
}
