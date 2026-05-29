import SwiftUI

struct CommitMessageEditor: View {
    @ObservedObject var viewModel: ChangesViewModel

    private var canCommit: Bool {
        !viewModel.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && viewModel.stagedCount > 0
            && !viewModel.isCommitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HistoryAwareTextEditor(
                text: $viewModel.commitMessage,
                history: viewModel.commitHistory,
                placeholder: L("コミットメッセージ（↑↓ で過去のメッセージを呼び出し）")
            )
            .frame(minHeight: 72, maxHeight: 140)
            .padding(DT.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            HStack(spacing: DT.Space.md) {
                if let branch = viewModel.currentBranch {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .imageScale(.small)
                        Text(branch)
                            .font(.callout.monospaced())
                    }
                    .foregroundStyle(.secondary)
                }

                if !viewModel.commitHistory.isEmpty {
                    Text(L("↑↓ で履歴"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if viewModel.stagedCount > 0 {
                    Text(L("%d 件をコミット", viewModel.stagedCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await viewModel.commit() }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isCommitting {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(L("コミット"))
                            .fontWeight(.medium)
                    }
                    .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canCommit)
            }
        }
    }
}
