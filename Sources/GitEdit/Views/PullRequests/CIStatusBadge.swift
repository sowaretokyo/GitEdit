import SwiftUI

/// Compact icon (optionally with a label) summarizing a `CIStatusSummary`.
/// `nil` (no data loaded yet / no checks at all) renders as a dashed circle.
struct CIStatusBadge: View {
    let summary: CIStatusSummary?
    var showsLabel: Bool = false

    private var status: CIStatus { summary?.overall ?? .none }

    var body: some View {
        HStack(spacing: 4) {
            icon
            if showsLabel {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help(label)
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(nsColor: .systemGreen))
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color(nsColor: .systemRed))
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundStyle(Color(nsColor: .systemYellow))
        case .none:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.tertiary)
        }
    }

    private var label: String {
        switch status {
        case .success: return L("すべてのチェックが成功")
        case .failure: return L("チェックが失敗しています")
        case .pending: return L("チェックを実行中")
        case .none: return L("チェックはありません")
        }
    }
}
