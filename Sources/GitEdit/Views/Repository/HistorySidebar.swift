import SwiftUI

/// Left sidebar contents for the History tab — the scrollable commit list.
struct HistorySidebar: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private var header: some View {
        HStack {
            Text(L("コミット履歴"))
                .font(.callout.weight(.medium))
            Spacer()
            if !viewModel.commits.isEmpty {
                Text("\(viewModel.commits.count)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm + 2)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.commits.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if viewModel.commits.isEmpty {
            VStack(spacing: DT.Space.sm) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(L("コミットがありません"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(selection: $viewModel.selectedCommitID) {
                ForEach(viewModel.commits) { commit in
                    CommitRow(commit: commit)
                        .tag(commit.id)
                }
            }
            .listStyle(.inset)
        }
    }
}
