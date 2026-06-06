import SwiftUI
import AppKit

/// Left sidebar contents for the Changes tab.
/// Composes a filter, the changed-file list (with per-file checkboxes), and
/// the commit composer pinned to the bottom — matching GitHub Desktop's layout.
struct ChangesSidebar: View {
    @ObservedObject var viewModel: ChangesViewModel
    @State private var filter: String = ""
    @State private var pendingDiscard: FileChange?

    private var filteredChanges: [FileChange] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return viewModel.changes }
        return viewModel.changes.filter {
            $0.path.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            fileListHeader
            Divider()
            fileList
            Divider()
            CommitMessageEditor(viewModel: viewModel)
                .padding(DT.Space.md)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .confirmationDialog(
            discardTitle,
            isPresented: discardDialogPresented,
            presenting: pendingDiscard
        ) { change in
            Button(discardConfirmLabel(for: change), role: .destructive) {
                Task { await viewModel.discard(change) }
            }
            Button(L("キャンセル"), role: .cancel) {}
        } message: { change in
            Text(discardMessage(for: change))
        }
    }

    // MARK: - Discard dialog

    private var discardDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDiscard != nil },
            set: { if !$0 { pendingDiscard = nil } }
        )
    }

    private var discardTitle: String {
        L("変更を破棄しますか？")
    }

    private func discardConfirmLabel(for change: FileChange) -> String {
        change.isUntracked ? L("ゴミ箱に移動") : L("変更を破棄")
    }

    private func discardMessage(for change: FileChange) -> String {
        if change.isUntracked {
            return L("%@ をゴミ箱に移動します。Finder のゴミ箱から復元できます。", change.displayPath)
        }
        return L("%@ の変更を破棄して HEAD の状態に戻します。この操作は元に戻せません。", change.displayPath)
    }

    private var filterBar: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "line.3.horizontal.decrease")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            TextField(L("フィルター"), text: $filter)
                .textFieldStyle(.plain)
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
    }

    private var fileListHeader: some View {
        HStack(spacing: DT.Space.sm) {
            Toggle("", isOn: Binding(
                get: { viewModel.allStaged },
                set: { _ in Task { await viewModel.toggleAll() } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(viewModel.changes.isEmpty)

            Text(L("%d 件の変更", filteredChanges.count))
                .font(.callout.weight(.medium))

            Spacer()

            if !viewModel.changes.isEmpty {
                Text(L("%d / %d", viewModel.stagedCount, viewModel.changes.count))
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
    }

    @ViewBuilder
    private var fileList: some View {
        if filteredChanges.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredChanges) { change in
                        FileChangeRow(
                            change: change,
                            isSelected: viewModel.selectedPath == change.path,
                            onToggle: {
                                // Read the modifier state synchronously at click time;
                                // shift extends the range from the last-toggled anchor.
                                let extend = NSEvent.modifierFlags.contains(.shift)
                                let visible = filteredChanges
                                Task {
                                    await viewModel.toggleInclusion(
                                        of: change,
                                        extendingRange: extend,
                                        in: visible
                                    )
                                }
                            }
                        )
                        .onTapGesture {
                            Task { await viewModel.select(change) }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDiscard = change
                            } label: {
                                Label(L("変更を破棄…"), systemImage: "arrow.uturn.backward")
                            }
                        }
                    }
                }
                .padding(.horizontal, DT.Space.xs)
                .padding(.vertical, DT.Space.xs)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DT.Space.md) {
            Spacer()
            Image(systemName: viewModel.changes.isEmpty ? "checkmark.seal.fill" : "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(
                    viewModel.changes.isEmpty
                    ? AnyShapeStyle(LinearGradient(
                        colors: [.green, .green.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom))
                    : AnyShapeStyle(Color.tertiaryLabel)
                )
            Text(viewModel.changes.isEmpty ? L("変更はありません") : L("見つかりません"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            if viewModel.changes.isEmpty {
                Text(L("作業ツリーはクリーンです ✨"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private extension Color {
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
}
