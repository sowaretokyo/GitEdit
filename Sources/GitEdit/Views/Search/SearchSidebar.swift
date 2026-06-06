import SwiftUI

/// Left sidebar tab for global text search (`⇧⌘F`).
/// Uses `git grep` and groups results by file path.
struct SearchSidebar: View {
    @ObservedObject var viewModel: SearchViewModel
    /// `id` of the result currently shown in the right pane (`GrepResult.id`).
    /// Used to render a persistent highlight on the active row.
    let currentResultId: String?
    let onSelect: (GrepResult) -> Void

    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            queryField
            Divider()
            summaryRow
            Divider()
            content
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .onAppear { queryFocused = true }
    }

    private var queryField: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L("文字列を検索"), text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($queryFocused)
                .onSubmit { viewModel.run() }
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
    }

    private var summaryRow: some View {
        HStack(spacing: DT.Space.sm) {
            if viewModel.results.isEmpty {
                Text(L("結果なし"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(L("%d 件 / %d ファイル", viewModel.totalMatches, viewModel.totalFiles))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.lastError {
            errorState(message: error)
        } else if viewModel.results.isEmpty {
            placeholder
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DT.Space.xs) {
                    ForEach(viewModel.groupedResults, id: \.path) { group in
                        Section {
                            ForEach(group.matches) { match in
                                MatchRow(
                                    match: match,
                                    query: viewModel.query,
                                    isCurrent: match.id == currentResultId
                                )
                                .onTapGesture { onSelect(match) }
                            }
                        } header: {
                            FileGroupHeader(
                                path: group.path,
                                count: group.matches.count,
                                hasCurrent: group.matches.contains { $0.id == currentResultId }
                            )
                        }
                    }
                }
                .padding(.horizontal, DT.Space.xs)
                .padding(.vertical, DT.Space.xs)
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(viewModel.query.isEmpty
                 ? L("検索したい文字列を入力してください")
                 : L("一致する結果がありません"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Space.md)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemRed))
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Space.md)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FileGroupHeader: View {
    let path: String
    let count: Int
    /// True when the currently-viewed grep result belongs to this file.
    let hasCurrent: Bool

    var body: some View {
        HStack(spacing: DT.Space.xs) {
            Image(systemName: "doc.text")
                .imageScale(.medium)
                .foregroundStyle(.tint)
            Text(path)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(hasCurrent ? .primary : .primary)
                .fontWeight(hasCurrent ? .semibold : .regular)
            Text("\(count)")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.18), in: Capsule())
                .foregroundStyle(.tint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.top, DT.Space.sm + 2)
        .padding(.bottom, DT.Space.xs)
    }
}

private struct MatchRow: View {
    let match: GrepResult
    let query: String
    /// True when this row is the result shown in the right pane.
    let isCurrent: Bool

    @State private var isHovering = false

    private var backgroundFill: Color {
        if isCurrent { return Color.accentColor.opacity(0.22) }
        if isHovering { return Color.accentColor.opacity(0.1) }
        return .clear
    }

    var body: some View {
        HStack(alignment: .top, spacing: DT.Space.sm) {
            Text("\(match.lineNumber)")
                .font(.callout.monospaced())
                .foregroundStyle(isCurrent
                                 ? Color.accentColor
                                 : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 40, alignment: .trailing)
                .padding(.top, 1)
            highlightedSnippet
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(alignment: .leading) {
            if isCurrent {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2.5)
                    .padding(.vertical, 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .animation(.easeOut(duration: 0.15), value: isCurrent)
    }

    private var highlightedSnippet: Text {
        let trimmed = match.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let range = trimmed.range(of: q, options: .caseInsensitive) else {
            return Text(trimmed)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
        }
        var attr = AttributedString(trimmed)
        if let r = Range(range, in: attr) {
            attr[r].foregroundColor = Color(nsColor: .systemYellow)
            attr[r].font = .system(.callout, design: .monospaced).weight(.semibold)
        }
        return Text(attr)
            .font(.system(.callout, design: .monospaced))
    }
}
