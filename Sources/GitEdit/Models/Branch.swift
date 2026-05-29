import Foundation

struct Branch: Identifiable, Hashable {
    let id: String
    let name: String
    let isCurrent: Bool
    let upstream: String?
    let ahead: Int
    let behind: Int
}
