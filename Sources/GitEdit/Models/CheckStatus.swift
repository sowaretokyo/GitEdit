import Foundation

/// Aggregated CI status for a single commit/PR head, independent of which
/// underlying API (Checks vs legacy Commit Statuses) reported it.
enum CIStatus: Equatable {
    case none
    case pending
    case success
    case failure
}

/// Rollup counts behind an `overall` `CIStatus`, used to render both the
/// compact list badge and the detail view's "成功 N・失敗 N・実行中 N" line.
struct CIStatusSummary: Equatable {
    let overall: CIStatus
    let success: Int
    let failure: Int
    let pending: Int
    let total: Int
}

// MARK: - GitHub Checks API (`/commits/{ref}/check-runs`)

struct CheckRunsResponse: Codable {
    let totalCount: Int
    let checkRuns: [CheckRun]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case checkRuns = "check_runs"
    }
}

struct CheckRun: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    /// "queued" | "in_progress" | "completed"
    let status: String
    /// "success" | "failure" | "neutral" | "cancelled" | "timed_out" |
    /// "action_required" | "stale" | nil (not completed yet)
    let conclusion: String?
    let detailsURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case conclusion
        case detailsURL = "details_url"
    }
}

// MARK: - Legacy Commit Status API (`/commits/{ref}/status`)

struct CombinedStatus: Codable {
    /// "success" | "failure" | "error" | "pending"
    let state: String
    let totalCount: Int
    let statuses: [CommitStatus]

    enum CodingKeys: String, CodingKey {
        case state
        case totalCount = "total_count"
        case statuses
    }
}

struct CommitStatus: Codable, Identifiable, Hashable {
    var id: String { context }
    let context: String
    let state: String
    let targetURL: String?

    enum CodingKeys: String, CodingKey {
        case context
        case state
        case targetURL = "target_url"
    }
}
