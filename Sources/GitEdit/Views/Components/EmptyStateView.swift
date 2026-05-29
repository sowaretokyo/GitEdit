import SwiftUI

/// Centered "nothing to see here" view with an SF Symbol, a primary title,
/// and an optional secondary subtitle. Used by detail panes when no
/// selection is made or when a query yields no results.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var iconSize: CGFloat = 32
    var background: Color = Color(nsColor: .textBackgroundColor)

    var body: some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
    }
}
