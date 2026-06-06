import SwiftUI

/// GitHub Desktop–style commit composer:
///   • avatar + Summary (single-line) in a row at the top
///   • Description (multi-line, optional) below
///   • full-width Commit button at the bottom
struct CommitMessageEditor: View {
    @ObservedObject var viewModel: ChangesViewModel
    @StateObject private var accountStore = AccountStore.shared

    private var canCommit: Bool {
        let trimmedMessage = viewModel.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedMessage.isEmpty
            && viewModel.selectedChange != nil
            && viewModel.stagedCount > 0
            && !viewModel.isCommitting
    }

    private var branchLabel: String {
        viewModel.currentBranch ?? "main"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            summaryRow
            descriptionField
            commitButton
        }
    }

    // MARK: - Summary row (avatar + single-line field)

    private var summaryRow: some View {
        HStack(alignment: .center, spacing: DT.Space.sm) {
            avatar
            summaryField
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let account = accountStore.currentAccount {
            AvatarImageView(
                url: account.avatarURL.flatMap { URL(string: $0) },
                initials: String(account.login.prefix(1)).uppercased(),
                tintColor: .accentColor,
                size: 36
            )
        } else {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15))
                Image(systemName: "person.fill")
                    .imageScale(.medium)
                    .foregroundStyle(.tint)
            }
            .frame(width: 36, height: 36)
            .overlay(
                Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
    }

    private var summaryField: some View {
        HistoryAwareTextField(
            text: $viewModel.commitMessage,
            history: viewModel.commitHistory,
            placeholder: L("Summary（必須）")
        )
        .padding(.horizontal, DT.Space.sm)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Description

    private var descriptionField: some View {
        HistoryAwareTextEditor(
            text: $viewModel.commitDescription,
            history: [],
            placeholder: L("Description")
        )
        .frame(minHeight: 88, maxHeight: 160)
        .padding(DT.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Full-width commit button

    private var commitButton: some View {
        Button {
            Task { await viewModel.commit() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isCommitting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.medium)
                }
                Text(commitLabel)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!canCommit)
        // Strong visual cue that the button is not actionable until all
        // commit conditions are satisfied.
        .opacity(canCommit ? 1.0 : 0.35)
        .saturation(canCommit ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.15), value: canCommit)
    }

    private var commitLabel: String {
        let n = max(viewModel.stagedCount, 0)
        return L("%d 件を %@ にコミット", n, branchLabel)
    }
}
