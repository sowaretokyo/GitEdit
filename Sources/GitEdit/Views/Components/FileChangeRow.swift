import SwiftUI

struct FileChangeRow: View {
    let change: FileChange
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            if change.isConflicted {
                // Conflicted files can't be staged via checkbox — they need
                // explicit resolution first.
                Color.clear.frame(width: 14, height: 14)
            } else {
                Toggle("", isOn: Binding(
                    get: { change.willBeCommitted },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }

            StatusBadge(change: change)

            Text(change.displayPath)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if change.isConflicted {
                Text(L("競合"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(nsColor: .systemOrange).opacity(0.18), in: Capsule())
                    .foregroundStyle(Color(nsColor: .systemOrange))
            } else if change.hasStagedChange && change.hasUnstagedChange {
                Text(L("一部のみ ステージ"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.vertical, DT.RowDensity.regular)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.18)
                      : (isHovering ? Color.accentColor.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .animation(.easeOut(duration: 0.1), value: isSelected)
    }
}
