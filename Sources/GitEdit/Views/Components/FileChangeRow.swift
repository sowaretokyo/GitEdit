import SwiftUI

struct FileChangeRow: View {
    let change: FileChange
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    private var statusColor: Color {
        switch change.category {
        case .modified, .typeChanged: return DT.Status.modified
        case .added: return DT.Status.added
        case .deleted: return DT.Status.deleted
        case .renamed, .copied: return DT.Status.renamed
        case .untracked: return DT.Status.untracked
        case .ignored: return Color.secondary
        case .unmerged: return DT.Status.unmerged
        }
    }

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            Toggle("", isOn: Binding(
                get: { change.willBeCommitted },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Text(change.primaryStatusSymbol)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(statusColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(change.displayPath)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if change.hasStagedChange && change.hasUnstagedChange {
                Text("一部のみ ステージ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
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
