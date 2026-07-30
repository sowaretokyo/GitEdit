import SwiftUI

/// Hunk/line-level staging UI for a tracked, non-binary, non-renamed file.
/// Shows two sections — unstaged changes (stage them) and staged changes
/// (unstage them) — each rendered with `DiffLineRow` so it matches the look
/// of the read-only `DiffView`, with a checkbox column added for `+`/`-` lines.
struct HunkStagingDiffView: View {
    @ObservedObject var viewModel: ChangesViewModel
    let path: String

    @State private var unstagedSelection: Set<LineKey> = []
    @State private var stagedSelection: Set<LineKey> = []

    struct LineKey: Hashable {
        let hunkIndex: Int
        let lineIndex: Int
    }

    enum Direction {
        case stage, unstage

        var hunkActionLabel: String {
            switch self {
            case .stage: return L("このかたまりをステージ")
            case .unstage: return L("このかたまりをアンステージ")
            }
        }

        func selectedLinesLabel(_ count: Int) -> String {
            switch self {
            case .stage: return L("選択した %d 行をステージ", count)
            case .unstage: return L("選択した %d 行をアンステージ", count)
            }
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let unstaged = viewModel.unstagedDiff, !unstaged.hunks.isEmpty {
                    DiffSectionView(
                        title: L("未ステージの変更"),
                        diff: unstaged,
                        direction: .stage,
                        selection: $unstagedSelection,
                        onHunkAction: { hunk in
                            Task { await viewModel.stageHunk(hunk, in: unstaged, path: path) }
                        },
                        onSelectedLinesAction: { selections in
                            unstagedSelection = []
                            Task { await viewModel.stageSelectedLines(selections, in: unstaged, path: path) }
                        }
                    )
                }
                if let staged = viewModel.stagedDiff, !staged.hunks.isEmpty {
                    DiffSectionView(
                        title: L("ステージ済みの変更"),
                        diff: staged,
                        direction: .unstage,
                        selection: $stagedSelection,
                        onHunkAction: { hunk in
                            Task { await viewModel.unstageHunk(hunk, in: staged, path: path) }
                        },
                        onSelectedLinesAction: { selections in
                            stagedSelection = []
                            Task { await viewModel.unstageSelectedLines(selections, in: staged, path: path) }
                        }
                    )
                }
                if (viewModel.unstagedDiff?.hunks.isEmpty ?? true), (viewModel.stagedDiff?.hunks.isEmpty ?? true) {
                    EmptyStateView(icon: "equal.circle", title: L("差分なし"))
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Section

private struct DiffSectionView: View {
    let title: String
    let diff: FileDiff
    let direction: HunkStagingDiffView.Direction
    @Binding var selection: Set<HunkStagingDiffView.LineKey>
    let onHunkAction: (DiffHunk) -> Void
    let onSelectedLinesAction: ([(hunk: DiffHunk, selectedLineIndices: Set<Int>)]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            ForEach(Array(diff.hunks.enumerated()), id: \.offset) { hunkIndex, hunk in
                HunkView(
                    hunkIndex: hunkIndex,
                    hunk: hunk,
                    direction: direction,
                    selection: $selection,
                    onHunkAction: onHunkAction
                )
            }

            if !selection.isEmpty {
                actionBar
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: DT.Space.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text("\(diff.hunks.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var actionBar: some View {
        HStack(spacing: DT.Space.sm) {
            Spacer()
            Button(L("選択をクリア")) {
                selection = []
            }
            .buttonStyle(.borderless)

            Button(direction.selectedLinesLabel(selection.count)) {
                onSelectedLinesAction(groupedSelections())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func groupedSelections() -> [(hunk: DiffHunk, selectedLineIndices: Set<Int>)] {
        var result: [(hunk: DiffHunk, selectedLineIndices: Set<Int>)] = []
        for (hunkIndex, hunk) in diff.hunks.enumerated() {
            let indices = Set(selection.filter { $0.hunkIndex == hunkIndex }.map(\.lineIndex))
            if !indices.isEmpty {
                result.append((hunk: hunk, selectedLineIndices: indices))
            }
        }
        return result
    }
}

// MARK: - Hunk

private struct HunkView: View {
    let hunkIndex: Int
    let hunk: DiffHunk
    let direction: HunkStagingDiffView.Direction
    @Binding var selection: Set<HunkStagingDiffView.LineKey>
    let onHunkAction: (DiffHunk) -> Void

    private static let checkboxColumnWidth: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.checkboxColumnWidth)
                Text(hunk.header)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, DT.Space.sm)
                Spacer(minLength: DT.Space.sm)
                Button(direction.hunkActionLabel) {
                    onHunkAction(hunk)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .padding(.trailing, DT.Space.sm)
            }
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.08))

            ForEach(Array(hunk.numberedLines().enumerated()), id: \.offset) { lineIndex, entry in
                lineRow(lineIndex: lineIndex, patchLine: entry.patchLine, diffLine: entry.diffLine)
            }
        }
    }

    private func lineRow(lineIndex: Int, patchLine: PatchLine, diffLine: DiffLine) -> some View {
        let key = HunkStagingDiffView.LineKey(hunkIndex: hunkIndex, lineIndex: lineIndex)
        return HStack(spacing: 0) {
            checkbox(for: patchLine, key: key)
                .frame(width: Self.checkboxColumnWidth)
            DiffLineRow(line: diffLine)
        }
    }

    @ViewBuilder
    private func checkbox(for line: PatchLine, key: HunkStagingDiffView.LineKey) -> some View {
        if line.kind == .context {
            EmptyView()
        } else {
            Toggle("", isOn: Binding(
                get: { selection.contains(key) },
                set: { isOn in
                    if isOn { selection.insert(key) } else { selection.remove(key) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
        }
    }

}
