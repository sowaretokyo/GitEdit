import SwiftUI

/// Presented when rewording a commit's message or combining it with the
/// previous commit (squash). Prefilled from `HistoryViewModel.PendingMessageEdit`
/// — the full original message for reword, or "parent message + blank line +
/// child message" for squash.
struct CommitMessageSheet: View {
    @ObservedObject var viewModel: HistoryViewModel
    let pending: HistoryViewModel.PendingMessageEdit
    @Environment(\.dismiss) private var dismiss

    @State private var message: String

    init(viewModel: HistoryViewModel, pending: HistoryViewModel.PendingMessageEdit) {
        self.viewModel = viewModel
        self.pending = pending
        _message = State(initialValue: pending.initialMessage)
    }

    private var title: String {
        pending.kind == .reword ? L("コミットメッセージを編集") : L("コミットを統合")
    }

    private var fieldLabel: String {
        pending.kind == .reword ? L("コミットメッセージ") : L("統合後のメッセージ")
    }

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isEditingHistory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            editor
            Divider()
            footer
        }
        .frame(width: 480, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        Text(title)
            .font(.title2.weight(.semibold))
            .padding(DT.Space.lg)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            Text(fieldLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            HistoryAwareTextEditor(text: $message, history: [], placeholder: "")
                .disabled(viewModel.isEditingHistory)
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
        .padding(DT.Space.lg)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if viewModel.isEditingHistory {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button(L("キャンセル")) {
                viewModel.cancelMessageEdit()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(viewModel.isEditingHistory)

            Button(L("保存")) {
                Task {
                    await viewModel.confirmMessageEdit(message)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
        .padding(DT.Space.md)
    }
}
