import Foundation

final class GitClient: @unchecked Sendable {
    enum GitError: LocalizedError {
        case commandFailed(status: Int32, stderr: String, command: [String])
        case notARepository(URL)
        case parseFailure(String)

        var errorDescription: String? {
            switch self {
            case .commandFailed(let status, let stderr, let command):
                return "git \(command.joined(separator: " "))\n失敗 (終了コード \(status))\n\(stderr)"
            case .notARepository(let url):
                return "\(url.path) は Git リポジトリではありません"
            case .parseFailure(let msg):
                return "Git 出力のパース失敗: \(msg)"
            }
        }
    }

    let repositoryURL: URL

    init(repository: URL) {
        self.repositoryURL = repository
    }

    @discardableResult
    func run(_ arguments: String...) async throws -> String {
        try await run(arguments)
    }

    @discardableResult
    func run(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + arguments
            process.currentDirectoryURL = repositoryURL

            var env = ProcessInfo.processInfo.environment
            env["LC_ALL"] = "C.UTF-8"
            env["GIT_TERMINAL_PROMPT"] = "0"
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
                    continuation.resume(returning: outStr)
                } else {
                    continuation.resume(throwing: GitError.commandFailed(
                        status: proc.terminationStatus,
                        stderr: errStr,
                        command: arguments
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - High-level operations

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

    func status() async throws -> [FileChange] {
        let output = try await run("status", "--porcelain=v1", "-z", "-uall")
        return GitStatusParser.parse(porcelainV1Z: output)
    }

    func recentCommitMessages(limit: Int = 100) async throws -> [String] {
        let sep = "\u{1F}"
        let output = try await run("log", "-n", String(limit), "--format=%s\(sep)")
        return output
            .split(separator: Character(sep), omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func commit(message: String) async throws {
        try await run("commit", "-m", message)
    }

    func stageAll() async throws {
        try await run("add", "-A")
    }
}
