import Foundation

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
    func run(_ arguments: [String]) async throws -> String {
        try await Self.runGit(arguments, cwd: repositoryURL)
    }

    // MARK: - Static runner (used by clone/init that don't have a repo yet)

    @discardableResult
    static func runGit(_ arguments: [String], cwd: URL? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            if let cwd { process.currentDirectoryURL = cwd }

            var env = ProcessInfo.processInfo.environment
            env["LC_ALL"] = "C.UTF-8"
            env["GIT_TERMINAL_PROMPT"] = "0"
            // Allow askpass / SSH agent to work but suppress interactive prompts.
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    cont.resume(returning: outStr)
                } else {
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
            }
        }
    }

    // MARK: - Repository-less ops

    static func clone(url: String, into destination: URL) async throws {
        let parent = destination.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try await runGit(["clone", "--progress", url, destination.path])
    }

    static func initRepository(at directory: URL, initialBranch: String = "main") async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await runGit(["init", "-b", initialBranch, directory.path])
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
        try await run("add", "--", path)
    }

    func unstage(path: String) async throws {
        try await run("restore", "--staged", "--", path)
    }

    func stageAll() async throws {
        try await run("add", "-A")
    }

    func unstageAll() async throws {
        try await run("restore", "--staged", ".")
    }

    // MARK: - Commit

    func commit(message: String) async throws {
        try await run("commit", "-m", message)
    }

    // MARK: - Diff

    func diffAgainstHEAD(path: String) async throws -> String {
        try await run("diff", "HEAD", "--no-color", "--", path)
    }

    func readFileFromWorkTree(path: String) -> String? {
        let url = repositoryURL.appendingPathComponent(path)
        return try? String(contentsOf: url, encoding: .utf8)
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

    func recentCommits(limit: Int = 200) async throws -> [Commit] {
        let RS = "\u{1E}"
        let US = "\u{1F}"
        // %B = raw body (including the subject line and any Co-Authored-By
        // trailers). We pull it so CoAuthorParser can extract co-authors.
        let output = try await run(
            "log", "-n", String(limit),
            "--format=%H\(US)%h\(US)%aI\(US)%an\(US)%ae\(US)%s\(US)%B\(RS)"
        )

        let formatter = ISO8601DateFormatter()
        var commits: [Commit] = []
        for record in output.split(separator: Character(RS), omittingEmptySubsequences: true) {
            // `maxSplits: 6` keeps newlines inside %B from being treated as
            // field boundaries by accident.
            let fields = record
                .split(separator: Character(US), maxSplits: 6, omittingEmptySubsequences: false)
                .map(String.init)
            guard fields.count >= 7 else { continue }
            let dateStr = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let date = formatter.date(from: dateStr) ?? .distantPast
            let rawBody = fields[6]
            commits.append(Commit(
                id: fields[0].trimmingCharacters(in: .whitespacesAndNewlines),
                shortSHA: fields[1],
                summary: fields[5].trimmingCharacters(in: .whitespacesAndNewlines),
                body: rawBody,
                author: fields[3],
                authorEmail: fields[4],
                date: date,
                coAuthors: CoAuthorParser.parse(from: rawBody)
            ))
        }
        return commits
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
        if checkout {
            var args = ["checkout", "-b", name]
            if let start = startingFrom { args.append(start) }
            try await run(args)
        } else {
            var args = ["branch", name]
            if let start = startingFrom { args.append(start) }
            try await run(args)
        }
    }

    func switchBranch(name: String) async throws {
        try await run("switch", name)
    }

    func deleteBranch(name: String, force: Bool = false) async throws {
        try await run("branch", force ? "-D" : "-d", name)
    }

    func merge(branch: String, noFastForward: Bool = false) async throws {
        var args = ["merge"]
        if noFastForward { args.append("--no-ff") }
        args.append(branch)
        try await run(args)
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
        var args = ["fetch", "--progress"]
        if prune { args.append("--prune") }
        if allRemotes {
            args.append("--all")
        } else if let remote {
            args.append(remote)
        }
        try await run(args)
    }

    /// Fast-forward only pull. Fails if not fast-forwardable; caller can show the error.
    func pull(remote: String = "origin") async throws {
        try await run("pull", "--ff-only", "--progress", remote)
    }

    /// Push current branch to `remote`. If `setUpstream` is true, also `-u`.
    func push(remote: String = "origin", branch: String? = nil, setUpstream: Bool = false) async throws {
        var args = ["push", "--progress"]
        if setUpstream { args.append("-u") }
        args.append(remote)
        if let branch { args.append(branch) }
        try await run(args)
    }
}
