import Foundation

struct Remote: Identifiable, Hashable {
    let name: String
    let fetchURL: String?
    let pushURL: String?

    var id: String { name }
}
