import SwiftUI

/// Compact inline presentation of a classified `GitOperationError` for use
/// inside modal sheets (Clone, Init, etc.) where the floating banner is not
/// available. Shows the friendly title and summary; the raw stderr is hidden
/// behind a disclosure so the panel doesn't blow up vertically.
struct InlineErrorView: View {
    let error: GitOperationError

    @State private var detailsExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack(alignment: .top, spacing: DT.Space.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .imageScale(.medium)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(error.title)
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(error.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !error.rawStderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup(isExpanded: $detailsExpanded) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(error.rawStderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                } label: {
                    Text(L("git からのメッセージを表示"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DT.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .systemRed).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                .strokeBorder(Color(nsColor: .systemRed).opacity(0.3), lineWidth: 0.5)
        )
    }
}
