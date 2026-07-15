import SwiftUI

@MainActor
struct CommitRow: View {
    let commit: Commit
    var isUnpushed: Bool = false
    /// When both are provided, the row offers a context menu for
    /// history-editing actions (reword/squash/move/drop), gated per-action
    /// by `HistoryViewModel.editability(at:)`. `nil` in contexts that only
    /// need to display a commit (e.g. future reuse outside the history tab).
    var viewModel: HistoryViewModel?
    var index: Int?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: DT.Space.md) {
            AvatarStack(authors: commit.allAuthors, size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(commit.allAuthorDisplayNames)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("•").foregroundStyle(.tertiary)
                    Text(Self.relativeFormatter.localizedString(for: commit.date, relativeTo: Date()))
                    Text("•").foregroundStyle(.tertiary)
                    Text(commit.shortSHA)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isUnpushed {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                    .help(L("未pushのコミット"))
            }
        }
        .padding(.vertical, DT.RowDensity.tight)
        .contextMenu { contextMenuContent }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        if let viewModel, let index {
            let editability = viewModel.editability(at: index)

            Button(L("メッセージを編集…")) {
                viewModel.requestReword(at: index)
            }
            .disabled(!editability.canReword)

            Button(L("ひとつ前のコミットに統合…")) {
                viewModel.requestSquashIntoPrevious(at: index)
            }
            .disabled(!editability.canSquashIntoPrevious)

            Divider()

            Button(L("1つ上へ移動")) {
                Task { await viewModel.moveUp(at: index) }
            }
            .disabled(!editability.canMoveUp)

            Button(L("1つ下へ移動")) {
                Task { await viewModel.moveDown(at: index) }
            }
            .disabled(!editability.canMoveDown)

            Divider()

            Button(L("このコミットを削除"), role: .destructive) {
                viewModel.requestDrop(at: index)
            }
            .disabled(!editability.canDrop)
        }
    }
}
