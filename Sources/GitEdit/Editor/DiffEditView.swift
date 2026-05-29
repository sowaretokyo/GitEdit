import SwiftUI

/// Right pane of the Changes view: shows either an editable code view
/// (with diff-aware highlights) or the read-only DiffView, with a header
/// to toggle between them.
struct DiffEditView: View {
    @ObservedObject var viewModel: ChangesViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(viewModel.selectedChange?.displayPath ?? L("ファイル未選択"))
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(viewModel.selectedChange == nil ? .tertiary : .primary)

            if viewModel.hasEditorUnsavedChanges {
                Circle()
                    .fill(Color(nsColor: .systemBlue))
                    .frame(width: 7, height: 7)
                    .help(L("未保存の変更があります"))
            }

            Spacer()

            if let change = viewModel.selectedChange, viewModel.selectedFileIsEditable {
                modePicker

                if viewModel.editorViewMode == .edit {
                    saveButton(change: change)
                }
            }
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm + 2)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.editorViewMode },
            set: { newMode in
                Task { await viewModel.setEditorViewMode(newMode) }
            }
        )) {
            ForEach(ChangesViewModel.DiffEditorMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 140)
        .labelsHidden()
    }

    private func saveButton(change: FileChange) -> some View {
        Button {
            Task { await viewModel.saveEditorContent() }
        } label: {
            HStack(spacing: 4) {
                if viewModel.isSavingEditor {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(L("保存"))
                    .fontWeight(.medium)
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!viewModel.hasEditorUnsavedChanges || viewModel.isSavingEditor)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let change = viewModel.selectedChange {
            if viewModel.selectedFileIsEditable && viewModel.editorViewMode == .edit {
                editor(change: change)
            } else {
                DiffView(
                    diffText: viewModel.diffText,
                    isLoading: viewModel.isLoadingDiff,
                    selectedFile: change.displayPath,
                    showsHeader: false
                )
                if !viewModel.selectedFileIsEditable {
                    nonEditableHint(change: change)
                }
            }
        } else {
            placeholder
        }
    }

    private func editor(change: FileChange) -> some View {
        CodeEditor(
            text: Binding(
                get: { viewModel.editorFileContent },
                set: { viewModel.updateEditorContent($0) }
            ),
            highlightedLines: viewModel.editorAddedLines,
            isEditable: true,
            onSave: {
                Task { await viewModel.saveEditorContent() }
            }
        )
    }

    @ViewBuilder
    private func nonEditableHint(change: FileChange) -> some View {
        if change.indexStatus == "D" || change.workingStatus == "D" {
            EmptyView()
        } else {
            HStack(spacing: DT.Space.sm) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                Text(L("このファイルは編集できません（バイナリまたは削除済み）"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(DT.Space.sm)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        }
    }

    private var placeholder: some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("左のリストからファイルを選択"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L("差分がここに表示されます"))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
