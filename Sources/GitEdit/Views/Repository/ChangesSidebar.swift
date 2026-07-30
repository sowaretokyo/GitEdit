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
        SidebarContainer {
            VStack(spacing: 0) {
                filterBar
                Divider()
                fileListHeader
            }
        } content: {
            VStack(spacing: 0) {
                fileList
                Divider()
                CommitMessageEditor(viewModel: viewModel)
                    .padding(DT.Space.md)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
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
        FilterField(
            text: $filter,
            prompt: L("フィルター"),
            systemImage: "line.3.horizontal.decrease",
            font: .body,
            imageScale: .small
        )
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
                CountBadge(
                    count: viewModel.stagedCount,
                    total: viewModel.changes.count
                )
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
                            mode: .workingTree(onToggle: {
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
                            })
                        )
                        .onTapGesture {
                            Task { await viewModel.select(change) }
                        }
                        .contextMenu {
                            if change.isConflicted {
                                Button {
                                    Task { await viewModel.resolveUsingOurs(change) }
                                } label: {
                                    Label(L("自分の変更を採用"), systemImage: "arrow.left.circle")
                                }
                                Button {
                                    Task { await viewModel.resolveUsingTheirs(change) }
                                } label: {
                                    Label(L("相手の変更を採用"), systemImage: "arrow.right.circle")
                                }
                                Button {
                                    Task { await viewModel.markResolved(change) }
                                } label: {
                                    Label(L("解決済みにする"), systemImage: "checkmark.circle")
                                }
                            } else {
                                Button(role: .destructive) {
                                    pendingDiscard = change
                                } label: {
                                    Label(L("変更を破棄…"), systemImage: "arrow.uturn.backward")
                                }
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
