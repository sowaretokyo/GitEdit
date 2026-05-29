import SwiftUI

/// 18pt monospaced badge showing the primary status letter of a `FileChange`
/// (`M`, `A`, `D`, `R`, `?` …) on the matching status color.
struct StatusBadge: View {
    let change: FileChange

    var body: some View {
        Text(change.primaryStatusSymbol)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(
                change.statusColor,
                in: RoundedRectangle(cornerRadius: DT.Radius.xs, style: .continuous)
            )
    }
}
