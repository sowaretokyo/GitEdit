import Foundation

enum GitStatusParser {
    /// Parses `git status --porcelain=v1 -z` output.
    /// Each entry: `XY<space>path<NUL>`. Renames/copies append origpath as a second NUL-separated entry.
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

            // Untracked / Ignored
            if indexCh == "?" && workCh == "?" {
                result.append(FileChange(path: path, status: .untracked, isStaged: false))
                i += 1
                continue
            }

            // Renames / Copies — staged form: "R  newpath<NUL>origpath<NUL>"
            if indexCh == "R" || indexCh == "C" {
                var orig = ""
                if i + 1 < entries.count {
                    orig = entries[i + 1]
                    i += 2
                } else {
                    i += 1
                }
                let s: FileChange.Status = (indexCh == "R") ? .renamed(from: orig) : .copied(from: orig)
                result.append(FileChange(path: path, status: s, isStaged: true))
                continue
            }

            if indexCh != " " {
                result.append(FileChange(path: path, status: status(from: indexCh), isStaged: true))
            }
            if workCh != " " {
                result.append(FileChange(path: path, status: status(from: workCh), isStaged: false))
            }
            i += 1
        }

        return result
    }

    private static func status(from ch: Character) -> FileChange.Status {
        switch ch {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "T": return .typeChanged
        case "U": return .unmerged
        default: return .modified
        }
    }
}
