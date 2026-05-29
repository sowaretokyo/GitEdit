import Foundation

struct Branch: Identifiable, Hashable {
    enum Kind: Hashable {
        case local
        case remote(name: String)  // remote name, e.g. "origin"
    }

    let name: String           // short name: "main" or "origin/main"
    let kind: Kind
    let isCurrent: Bool
    let upstream: String?      // tracked upstream ref, e.g. "origin/main"
    let upstreamGone: Bool
    let ahead: Int
    let behind: Int
    let sha: String            // short SHA of tip
    let subject: String        // tip commit message
    let authorName: String
    let lastCommitDate: Date?

    var id: String {
        switch kind {
        case .local: return "local:\(name)"
        case .remote: return "remote:\(name)"
        }
    }

    var isLocal: Bool {
        if case .local = kind { return true }
        return false
    }

    var isRemote: Bool { !isLocal }

    /// For local branches with an upstream, true when local has commits not on upstream.
    var hasOutgoing: Bool { ahead > 0 }
    var hasIncoming: Bool { behind > 0 }
}
