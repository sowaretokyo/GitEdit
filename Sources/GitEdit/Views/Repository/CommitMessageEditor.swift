import SwiftUI

struct CommitMessageEditor: View {
    @ObservedObject var viewModel: ChangesViewModel

    private var canCommit: Bool {
        let trimmedMessage = viewModel.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strict guard against accidental commits:
        //   1. A file must be selected (= a diff is visible)
        //   2. At least one file is checked to be committed
        //   3. The summary has non-whitespace content
        //   4. Not already mid-commit
        return !trimmedMessage.isEmpty
            && viewModel.selectedChange != nil
            && viewModel.stagedCount > 0
            && !viewModel.isCommitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            // Summary (required, supports ↑↓ history)
            HistoryAwareTextEditor(
                text: $viewModel.commitMessage,
                history: viewModel.commitHistory,
                placeholder: L("コミットメッセージ（↑↓ で過去のメッセージを呼び出し）")
            )
            .frame(minHeight: 44, maxHeight: 70)
            .padding(DT.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )

            // Description (optional)
            HistoryAwareTextEditor(
                text: $viewModel.commitDescription,
                history: [],
                placeholder: L("Description（任意）")
            )
            .frame(minHeight: 60, maxHeight: 120)
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

                commitButton
            }
        }
    }

    private var commitButton: some View {
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
        // Strong visual cue that the button is not actionable until all
        // commit conditions are satisfied.
        .opacity(canCommit ? 1.0 : 0.4)
        .saturation(canCommit ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.15), value: canCommit)
    }
}
