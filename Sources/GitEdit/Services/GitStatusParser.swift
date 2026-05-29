import Foundation

enum GitStatusParser {
    /// Parses `git status --porcelain=v1 -z` output. One FileChange per path.
    static func parse(porcelainV1Z output: String) -> [FileChange] {
        var result: [FileChange] = []
        let entries = output.split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)

        var i = 0
        while i < entries.count {
            let entry = entries[i]
            guard entry.count >= 3 else { i += 1; continue }

            let chars = Array(entry)
            let indexCh = chars[0]
            let workCh = chars[1]
            let path = String(chars[3...])

            var renameFrom: String? = nil
            if indexCh == "R" || indexCh == "C" || workCh == "R" || workCh == "C" {
                if i + 1 < entries.count {
                    renameFrom = entries[i + 1]
                    i += 2
                } else {
                    i += 1
                }
            } else {
                i += 1
            }

            result.append(FileChange(
                path: path,
                indexStatus: indexCh,
                workingStatus: workCh,
                renameFrom: renameFrom
            ))
        }
        return result
    }
}
