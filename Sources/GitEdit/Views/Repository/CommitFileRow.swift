import SwiftUI

struct CommitFileRow: View {
    let file: FileChange
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            StatusBadge(change: file)

            Text(file.displayPath)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
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
