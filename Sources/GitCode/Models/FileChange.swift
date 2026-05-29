import Foundation

struct FileChange: Identifiable, Hashable {
    var id: String { "\(isStaged ? "S" : "W"):\(statusSymbol):\(path)" }

    let path: String
    let status: Status
    let isStaged: Bool

    enum Status: Hashable {
        case modified
        case added
        case deleted
        case renamed(from: String)
        case copied(from: String)
        case untracked
        case typeChanged
        case unmerged
    }

    var statusSymbol: String {
        switch status {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        case .untracked: return "?"
        case .typeChanged: return "T"
        case .unmerged: return "U"
        }
    }
}
