import SwiftUI

/// Compact capsule used for numeric counts in headers and toolbar overlays.
struct CountBadge: View {
    enum Style {
        case accent
        case compactAccent
        case secondary
        case compactSecondary
        case toolbar(Color)
    }

    let count: Int
    var total: Int? = nil
    var style: Style = .accent

    var body: some View {
        Text(displayText)
            .font(font)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor, in: Capsule())
    }

    private var displayText: String {
        guard let total else { return "\(count)" }
        return "\(count) / \(total)"
    }

    private var font: Font {
        switch style {
        case .accent, .compactAccent:
            return .caption.weight(.medium)
        case .secondary, .compactSecondary:
            return .caption2.weight(.medium)
        case .toolbar:
            return .system(size: 9, weight: .bold)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .accent, .compactAccent:
            return .accentColor
        case .secondary, .compactSecondary:
            return Color(nsColor: .secondaryLabelColor)
        case .toolbar:
            return .white
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .accent, .compactAccent:
            return Color.accentColor.opacity(0.18)
        case .secondary, .compactSecondary:
            return Color(nsColor: .secondaryLabelColor).opacity(0.15)
        case .toolbar(let color):
            return color
        }
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .accent:
            return 7
        case .compactAccent, .secondary:
            return 6
        case .compactSecondary:
            return 5
        case .toolbar:
            return 4
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .accent:
            return 2
        case .compactAccent, .secondary, .compactSecondary, .toolbar:
            return 1
        }
    }
}
