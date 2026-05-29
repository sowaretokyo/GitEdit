import SwiftUI

struct HistoryView: View {
    let repository: Repository

    var body: some View {
        VStack(spacing: DT.Space.md) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("履歴ビュー")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Phase 2 で実装予定")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
