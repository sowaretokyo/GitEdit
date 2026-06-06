import SwiftUI

struct FileChangeRow: View {
    let change: FileChange
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            Toggle("", isOn: Binding(
                get: { change.willBeCommitted },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            StatusBadge(change: change)

            Text(change.displayPath)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if change.hasStagedChange && change.hasUnstagedChange {
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
