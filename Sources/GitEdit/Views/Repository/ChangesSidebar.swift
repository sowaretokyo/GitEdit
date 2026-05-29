import SwiftUI

/// Left sidebar contents for the Changes tab.
/// Composes a filter, the changed-file list (with per-file checkboxes), and
/// the commit composer pinned to the bottom — matching GitHub Desktop's layout.
struct ChangesSidebar: View {
    @ObservedObject var viewModel: ChangesViewModel
    @State private var filter: String = ""

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
                                Task { await viewModel.toggleInclusion(of: change) }
                            }
                        )
                        .onTapGesture {
                            Task { await viewModel.select(change) }
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
