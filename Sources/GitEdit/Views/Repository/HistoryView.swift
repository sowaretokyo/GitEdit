import SwiftUI

struct HistoryView: View {
    let repository: Repository
    @StateObject private var viewModel: HistoryViewModel

    init(repository: Repository) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: HistoryViewModel(repository: repository))
    }

    var body: some View {
        HSplitView {
            commitList
                .frame(minWidth: 340, idealWidth: 400)
            commitDetail
        }
        .task { await viewModel.load() }
    }

    private var commitList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("コミット履歴")
                    .font(.headline)
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

            Divider()

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
                    Text("コミットがありません")
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

    @ViewBuilder
    private var commitDetail: some View {
        if let commit = viewModel.selectedCommit {
            CommitDetailView(commit: commit)
        } else {
            VStack(spacing: DT.Space.sm) {
                Spacer()
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("左のリストからコミットを選択")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
