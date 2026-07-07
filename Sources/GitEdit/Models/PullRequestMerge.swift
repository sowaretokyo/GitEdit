import Foundation

/// The merge strategy sent as `merge_method` to `PUT .../pulls/{number}/merge`.
enum MergeMethod: String, CaseIterable, Equatable {
    case merge
    case squash
    case rebase
}

/// The response body from a successful merge request.
struct MergeResult: Codable, Equatable {
    let sha: String?
    let merged: Bool
    let message: String?
}
