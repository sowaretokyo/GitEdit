import Foundation

struct GrepResult: Identifiable, Hashable {
    var id: String { "\(path):\(lineNumber)" }
    let path: String
    let lineNumber: Int
    let content: String
}
