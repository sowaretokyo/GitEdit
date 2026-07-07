import Foundation

/// Merges GitHub's two independent CI signals — the Checks API
/// (`check-runs`, used by GitHub Actions and most modern CI apps) and the
/// legacy Commit Status API (`status`, used by older integrations like
/// classic Travis/CircleCI webhooks) — into one summary.
enum CIStatusAggregator {
    static func aggregate(checkRuns: [CheckRun], combined: CombinedStatus?) -> CIStatusSummary {
        var success = 0
        var failure = 0
        var pending = 0

        for run in checkRuns {
            switch classify(run) {
            case .success: success += 1
            case .failure: failure += 1
            case .pending: pending += 1
            case .none: break
            }
        }

        // A GitHub Actions-only repository has no legacy commit statuses, and
        // the combined-status endpoint reports that as state "pending" with
        // total_count 0 — not "no data". Folding that in unconditionally
        // would make every such PR look permanently pending even once all its
        // check-runs have passed, so only count it when it carries real data.
        if let combined, combined.totalCount > 0 {
            switch normalize(combined.state) {
            case .success: success += 1
            case .failure: failure += 1
            case .pending: pending += 1
            case .none: break
            }
        }

        let total = success + failure + pending
        let overall: CIStatus
        if failure > 0 {
            overall = .failure
        } else if pending > 0 {
            overall = .pending
        } else if total > 0 {
            overall = .success
        } else {
            overall = .none
        }

        return CIStatusSummary(overall: overall, success: success, failure: failure, pending: pending, total: total)
    }

    /// Not `private` so detail-view rows can render the same per-check icon
    /// the aggregate counts are derived from.
    static func classify(_ run: CheckRun) -> CIStatus {
        guard run.status == "completed" else { return .pending }
        switch run.conclusion {
        case "success", "neutral", "skipped":
            return .success
        case "failure", "timed_out", "cancelled", "action_required", "stale":
            return .failure
        default:
            return .pending
        }
    }

    private static func normalize(_ state: String) -> CIStatus {
        switch state {
        case "success": return .success
        case "failure", "error": return .failure
        case "pending": return .pending
        default: return .none
        }
    }
}
