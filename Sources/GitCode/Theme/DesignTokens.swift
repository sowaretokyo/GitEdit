import SwiftUI

enum DT {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
    }

    enum Status {
        static let modified = Color(nsColor: .systemOrange)
        static let added = Color(nsColor: .systemGreen)
        static let deleted = Color(nsColor: .systemRed)
        static let renamed = Color(nsColor: .systemBlue)
        static let untracked = Color(nsColor: .systemTeal)
        static let unmerged = Color(nsColor: .systemPurple)
        static let typeChanged = Color(nsColor: .systemOrange)
    }
}
