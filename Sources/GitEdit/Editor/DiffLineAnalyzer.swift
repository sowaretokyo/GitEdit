import Foundation

/// Extracts the set of 1-based line numbers in the *new* (current) file that
/// were added or changed, according to a unified diff against HEAD.
enum DiffLineAnalyzer {
    /// - Parameters:
    ///   - diff: Output of `git diff HEAD -- <path>` (no color).
    ///   - isUntracked: When true, treat every line of `content` as added.
    ///   - content: The current file content, used only for untracked files.
    static func addedLines(
        from diff: String,
        isUntracked: Bool,
        content: String
    ) -> Set<Int> {
        if isUntracked {
            return allLines(of: content)
        }

        var added: Set<Int> = []
        var newLine = 0
        var inHunk = false

        for raw in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("@@") {
                if let r = line.range(of: #"\+(\d+)"#, options: .regularExpression) {
                    let captured = line[r].dropFirst()
                    newLine = (Int(captured) ?? 1) - 1
                }
                inHunk = true
            } else if inHunk {
                if line.hasPrefix("+++") || line.hasPrefix("---") {
                    // file header, skip
                    continue
                }
                if line.hasPrefix("+") {
                    newLine += 1
                    added.insert(newLine)
                } else if line.hasPrefix("-") {
                    // removed line — does not advance new file counter
                } else if line.hasPrefix(" ") {
                    newLine += 1
                } else if line.hasPrefix("\\") {
                    // "\ No newline at end of file" marker — skip
                    continue
                }
            }
        }
        return added
    }

    private static func allLines(of content: String) -> Set<Int> {
        let count = content.components(separatedBy: "\n").count
        return Set(1...max(1, count))
    }
}
