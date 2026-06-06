import Foundation

/// Lightweight index of every tracked or untracked file in a Git repository.
/// Uses `git ls-files` so `.gitignore`d paths are excluded automatically.
final class RepositoryFileIndex: @unchecked Sendable {
    let repository: URL
    private let git: GitClient

    init(repository: URL) {
        self.repository = repository
        self.git = GitClient(repository: repository)
    }

    /// Returns all paths git knows about (cached + others, excluding ignored).
    /// Paths are repository-relative.
    func allPaths() async throws -> [String] {
        // -z gives NUL-separated paths, safe for paths containing newlines/spaces.
        // --cached: tracked files
        // --others: untracked files
        // --exclude-standard: honor .gitignore / .git/info/exclude / global excludes
        let output = try await git.run("ls-files", "-z", "--cached", "--others", "--exclude-standard")
        let paths = output
            .split(separator: "\u{0}", omittingEmptySubsequences: true)
            .map(String.init)
        // De-dup: --cached and --others can overlap for files that are
        // both tracked and have new versions.
        var seen = Set<String>()
        var result: [String] = []
        for path in paths where seen.insert(path).inserted {
            result.append(path)
        }
        return result
    }
}
