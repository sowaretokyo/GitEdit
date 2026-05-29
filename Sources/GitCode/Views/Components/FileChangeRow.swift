import SwiftUI

struct FileChangeRow: View {
    let change: FileChange
    @State private var isHovering = false

    private var statusColor: Color {
        switch change.status {
        case .modified: return DT.Status.modified
        case .added: return DT.Status.added
        case .deleted: return DT.Status.deleted
        case .renamed: return DT.Status.renamed
        case .copied: return DT.Status.renamed
        case .untracked: return DT.Status.untracked
        case .typeChanged: return DT.Status.typeChanged
        case .unmerged: return DT.Status.unmerged
        }
    }

    private var displayPath: String {
        switch change.status {
        case .renamed(let from), .copied(let from):
            return "\(from) → \(change.path)"
        default:
            return change.path
        }
    }

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            Text(change.statusSymbol)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(statusColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(displayPath)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if !change.isStaged && change.status != .untracked {
                Text("未ステージ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.tint.opacity(isHovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
