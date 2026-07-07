import SwiftUI

/// Lets the user stash only a subset of hunks/lines, leaving the rest of the
/// working tree untouched. Presented from `StashSheet`'s composer when the
/// installed git supports `stash push --staged` (2.35+).
struct PartialStashSheet: View {
    @ObservedObject var repoVM: RepositoryViewModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: PartialStashViewModel
    @State private var message: String = ""
    @State private var isSubmitting: Bool = false

    init(repoVM: RepositoryViewModel) {
        self.repoVM = repoVM
        _viewModel = StateObject(wrappedValue: PartialStashViewModel(git: repoVM.git))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            messageField
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 640, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await viewModel.load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DT.Space.xs) {
            Text(L("変更を一部だけ退避"))
                .font(.title2.weight(.semibold))
            Text(L("退避する変更を選択してください。選択したかたまり・行だけが退避され、残りは作業ツリーに残ります。"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(DT.Space.lg)
    }

    private var messageField: some View {
        TextField(L("退避メッセージ（任意）"), text: $message)
            .textFieldStyle(.roundedBorder)
            .disabled(isSubmitting)
            .padding(.horizontal, DT.Space.lg)
            .padding(.vertical, DT.Space.sm)
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        } else if viewModel.isEmpty {
            EmptyStateView(icon: "archivebox", title: L("退避できる変更がありません"))
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: DT.Space.md) {
                    ForEach(viewModel.entries) { entry in
                        FileSection(entry: entry, viewModel: viewModel)
                    }
                }
                .padding(.vertical, DT.Space.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DT.Space.sm) {
            if viewModel.hasSelection {
                Text(L("選択中: %d 件", viewModel.selectedCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSubmitting {
                ProgressView().controlSize(.small)
            }
            Button(L("キャンセル")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isSubmitting)
            Button(L("選択を退避")) {
                Task { await submit() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.hasSelection || isSubmitting)
        }
        .padding(DT.Space.md)
    }

    private func submit() async {
        guard let patch = viewModel.buildPatch() else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if await repoVM.createPartialStash(patch: patch, message: trimmed) {
            dismiss()
        }
    }
}

// MARK: - File section (file checkbox + its hunks)

private struct FileSection: View {
    let entry: PartialStashViewModel.FileEntry
    @ObservedObject var viewModel: PartialStashViewModel

    private static let checkboxColumnWidth: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            fileHeader
            ForEach(Array(entry.fileDiff.hunks.enumerated()), id: \.offset) { hunkIndex, hunk in
                HunkSection(entry: entry, hunkIndex: hunkIndex, hunk: hunk, viewModel: viewModel)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .padding(.horizontal, DT.Space.md)
    }

    private var fileHeader: some View {
        HStack(spacing: DT.Space.sm) {
            Toggle("", isOn: Binding(
                get: { viewModel.isFileFullySelected(entry) },
                set: { _ in viewModel.toggleFile(entry) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(entry.change.displayPath)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.vertical, DT.Space.sm)
    }
}

// MARK: - Hunk section (hunk checkbox + its lines)

private struct HunkSection: View {
    let entry: PartialStashViewModel.FileEntry
    let hunkIndex: Int
    let hunk: DiffHunk
    @ObservedObject var viewModel: PartialStashViewModel

    private static let checkboxColumnWidth: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Toggle("", isOn: Binding(
                    get: { viewModel.isHunkFullySelected(path: entry.change.path, hunkIndex: hunkIndex, hunk: hunk) },
                    set: { _ in viewModel.toggleHunk(path: entry.change.path, hunkIndex: hunkIndex, hunk: hunk) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: Self.checkboxColumnWidth)

                Text(hunk.header)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DT.Space.sm)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.08))

            ForEach(Array(numberedLines().enumerated()), id: \.offset) { lineIndex, entryPair in
                lineRow(lineIndex: lineIndex, patchLine: entryPair.patchLine, diffLine: entryPair.diffLine)
            }
        }
    }

    private func lineRow(lineIndex: Int, patchLine: PatchLine, diffLine: DiffLine) -> some View {
        HStack(spacing: 0) {
            checkbox(for: patchLine, lineIndex: lineIndex)
                .frame(width: Self.checkboxColumnWidth)
            DiffLineRow(line: diffLine)
        }
    }

    @ViewBuilder
    private func checkbox(for line: PatchLine, lineIndex: Int) -> some View {
        if line.kind == .context {
            EmptyView()
        } else {
            Toggle("", isOn: Binding(
                get: { viewModel.isLineSelected(path: entry.change.path, hunkIndex: hunkIndex, lineIndex: lineIndex) },
                set: { _ in viewModel.toggleLine(path: entry.change.path, hunkIndex: hunkIndex, lineIndex: lineIndex) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
        }
    }

    /// Pairs each `PatchLine` with the `DiffLine` `DiffLineRow` expects,
    /// tracking running old/new line numbers the same way `DiffParser` does.
    private func numberedLines() -> [(patchLine: PatchLine, diffLine: DiffLine)] {
        var oldLine = hunk.oldStart - 1
        var newLine = hunk.newStart - 1
        return hunk.lines.map { line in
            switch line.kind {
            case .context:
                oldLine += 1; newLine += 1
                return (line, .context(content: line.content, oldLine: oldLine, newLine: newLine))
            case .removed:
                oldLine += 1
                return (line, .removed(content: line.content, oldLine: oldLine))
            case .added:
                newLine += 1
                return (line, .added(content: line.content, newLine: newLine))
            }
        }
    }
}
