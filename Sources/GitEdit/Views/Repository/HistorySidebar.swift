import SwiftUI

/// Left sidebar contents for the History tab — the scrollable commit list.
struct HistorySidebar: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        SidebarContainer {
            header
        } content: {
            content
        }
        .overlay {
            // Covers the whole sidebar (not just the list) so a menu-triggered
            // move/drop can't be re-triggered mid-flight via the header either.
            if viewModel.isEditingHistory {
                ZStack {
                    Color(nsColor: .controlBackgroundColor).opacity(0.5)
                    ProgressView()
                }
                .allowsHitTesting(true)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L("コミット履歴"))
                .font(.callout.weight(.medium))
            Spacer()
            if !viewModel.commits.isEmpty {
                CountBadge(count: viewModel.commits.count)
            }
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm + 2)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.commits.isEmpty {
            LoadingStateView()
        } else if viewModel.commits.isEmpty {
            EmptyStateView(
                icon: "tray",
                title: L("コミットがありません"),
                background: .clear
            )
        } else {
            List(selection: $viewModel.selectedCommitID) {
                ForEach(Array(viewModel.commits.enumerated()), id: \.element.id) { index, commit in
                    CommitRow(
                        commit: commit,
                        isUnpushed: viewModel.unpushedSHAs.contains(commit.id),
                        viewModel: viewModel,
                        index: index
                    )
                    .tag(commit.id)
                }
            }
            .listStyle(.inset)
        }
    }
}
