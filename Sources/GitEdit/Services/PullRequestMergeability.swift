import Foundation

/// Why a pull request currently can't be merged from this app.
enum MergeBlockReason: Equatable {
    case draft
    case conflicts
    case computing
    case blocked
    case alreadyMerged
    case closed
}

/// Whether a PR can be merged right now, and why not if it can't. CI failure
/// never blocks a merge on its own (GitHub allows merging over failing
/// checks unless a branch-protection rule says otherwise, which shows up as
/// `mergeableState == "blocked"` instead) — it only sets `ciWarning` so the
/// UI can ask for confirmation.
struct MergeReadiness: Equatable {
    let canMerge: Bool
    let reason: MergeBlockReason?
    let ciWarning: Bool
}

/// Pure decision logic for the merge button's enabled/disabled state,
/// derived from a `PullRequest`'s own fields plus its aggregated CI status.
/// Kept independent of the view layer so it can be unit-tested directly.
enum PullRequestMergeability {
    static func evaluate(pr: PullRequest, ci: CIStatus) -> MergeReadiness {
        if pr.merged == true {
            return MergeReadiness(canMerge: false, reason: .alreadyMerged, ciWarning: false)
        }
        if pr.state != "open" {
            return MergeReadiness(canMerge: false, reason: .closed, ciWarning: false)
        }
        if pr.isDraft {
            return MergeReadiness(canMerge: false, reason: .draft, ciWarning: false)
        }
        if pr.mergeable == false {
            return MergeReadiness(canMerge: false, reason: .conflicts, ciWarning: false)
        }
        if pr.mergeable == nil {
            return MergeReadiness(canMerge: false, reason: .computing, ciWarning: false)
        }
        if pr.mergeableState == "blocked" {
            return MergeReadiness(canMerge: false, reason: .blocked, ciWarning: false)
        }
        return MergeReadiness(canMerge: true, reason: nil, ciWarning: ci == .failure)
    }
}
