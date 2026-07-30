import SwiftUI

struct DiffView: View {
    let diffText: String
    let isLoading: Bool
    let selectedFile: String?
    /// When false the path-strip header is suppressed (e.g. when the parent
    /// already shows the same path, like in `DiffEditView`).
    var showsHeader: Bool = true

    @AppStorage(DiffDisplayStyle.storageKey) private var diffStyle: DiffDisplayStyle = .unified

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Divider()
            }
            content
        }
    }

    private var header: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(selectedFile ?? L("ファイル未選択"))
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(selectedFile == nil ? .tertiary : .primary)
            Spacer()
            DiffStylePicker(style: $diffStyle)
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm + 2)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if selectedFile == nil {
            EmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: L("左のリストからファイルを選択"),
                subtitle: L("差分がここに表示されます")
            )
        } else if isLoading {
            LoadingStateView(background: Color(nsColor: .textBackgroundColor))
        } else if diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyStateView(icon: "equal.circle", title: L("差分なし"))
        } else {
            let parsed = DiffParser.parse(diffText)
            switch diffStyle {
            case .unified:
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(parsed.indices, id: \.self) { idx in
                            DiffLineRow(line: parsed[idx])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
            case .split:
                SplitDiffView(rows: SplitDiffBuilder.rows(from: parsed))
            }
        }
    }
}

// MARK: - Style picker

/// Segmented toggle between unified and side-by-side diff rendering.
/// Persisted app-wide via `DiffDisplayStyle`'s `@AppStorage` key.
struct DiffStylePicker: View {
    @Binding var style: DiffDisplayStyle

    var body: some View {
        Picker("", selection: $style) {
            ForEach(DiffDisplayStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 130)
        .help(L("差分の表示形式"))
    }
}

// MARK: - Parser

enum DiffLine: Hashable {
    case fileHeader(String)
    case hunkHeader(String)
    case added(content: String, newLine: Int)
    case removed(content: String, oldLine: Int)
    case context(content: String, oldLine: Int, newLine: Int)
}

struct NumberedPatchLine: Hashable {
    let patchLine: PatchLine
    let diffLine: DiffLine
}

extension DiffHunk {
    /// Converts structured patch lines into the numbered rows consumed by
    /// `DiffLineRow`, keeping staging and partial-stash numbering identical.
    func numberedLines() -> [NumberedPatchLine] {
        var oldLine = oldStart - 1
        var newLine = newStart - 1

        return lines.map { line in
            let diffLine: DiffLine
            switch line.kind {
            case .context:
                oldLine += 1
                newLine += 1
                diffLine = .context(content: line.content, oldLine: oldLine, newLine: newLine)
            case .removed:
                oldLine += 1
                diffLine = .removed(content: line.content, oldLine: oldLine)
            case .added:
                newLine += 1
                diffLine = .added(content: line.content, newLine: newLine)
            }
            return NumberedPatchLine(patchLine: line, diffLine: diffLine)
        }
    }
}

enum DiffParser {
    static func parse(_ text: String) -> [DiffLine] {
        var result: [DiffLine] = []
        var oldLine = 0
        var newLine = 0
        var inHunk = false

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(raw)

            if s.hasPrefix("@@") {
                if let r = s.range(of: #"-(\d+)"#, options: .regularExpression) {
                    oldLine = (Int(s[r].dropFirst()) ?? 1) - 1
                }
                if let r = s.range(of: #"\+(\d+)"#, options: .regularExpression) {
                    newLine = (Int(s[r].dropFirst()) ?? 1) - 1
                }
                inHunk = true
                result.append(.hunkHeader(s))
                continue
            }

            // File-level headers (before / between hunks)
            if !inHunk || s.hasPrefix("diff --git") || s.hasPrefix("index ")
                || s.hasPrefix("---") || s.hasPrefix("+++")
                || s.hasPrefix("new file") || s.hasPrefix("deleted file")
                || s.hasPrefix("old mode") || s.hasPrefix("new mode")
                || s.hasPrefix("similarity") || s.hasPrefix("rename ")
                || s.hasPrefix("copy ") || s.hasPrefix("Binary files") {
                if !s.isEmpty {
                    result.append(.fileHeader(s))
                }
                // A new "diff --git" starts a new file; reset hunk state.
                if s.hasPrefix("diff --git") {
                    inHunk = false
                    oldLine = 0
                    newLine = 0
                }
                continue
            }

            if s.hasPrefix("+") {
                newLine += 1
                result.append(.added(content: String(s.dropFirst()), newLine: newLine))
            } else if s.hasPrefix("-") {
                oldLine += 1
                result.append(.removed(content: String(s.dropFirst()), oldLine: oldLine))
            } else if s.hasPrefix(" ") {
                oldLine += 1
                newLine += 1
                result.append(.context(content: String(s.dropFirst()), oldLine: oldLine, newLine: newLine))
            } else if s.hasPrefix("\\") {
                // "\ No newline at end of file" — skip
                continue
            } else if !s.isEmpty {
                // unknown — treat as context to avoid losing content
                result.append(.context(content: s, oldLine: oldLine, newLine: newLine))
            }
        }

        return result
    }
}

// MARK: - Rendering

struct DiffLineRow: View {
    let line: DiffLine

    static let gutterWidth: CGFloat = 44
    private static let markerWidth: CGFloat = 16

    /// Shared with `SplitDiffRowView` so unified and split rendering stay
    /// visually consistent.
    static let addedBackground = Color(nsColor: .systemGreen).opacity(0.12)
    static let removedBackground = Color(nsColor: .systemRed).opacity(0.12)
    static let addedGutterTint = Color(nsColor: .systemGreen)
    static let removedGutterTint = Color(nsColor: .systemRed)

    var body: some View {
        switch line {
        case .fileHeader(let s):
            Text(s)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DT.Space.md)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))

        case .hunkHeader(let s):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: Self.gutterWidth * 2 + Self.markerWidth)
                Text(s)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, DT.Space.sm)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.08))

        case .added(let content, let newLine):
            HStack(spacing: 0) {
                gutterCell(text: "", tint: Self.addedGutterTint)
                gutterCell(text: "\(newLine)", tint: Self.addedGutterTint)
                marker(symbol: "+", color: Self.addedGutterTint)
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.leading, DT.Space.xs)
                Spacer(minLength: 0)
            }
            .background(Self.addedBackground)

        case .removed(let content, let oldLine):
            HStack(spacing: 0) {
                gutterCell(text: "\(oldLine)", tint: Self.removedGutterTint)
                gutterCell(text: "", tint: Self.removedGutterTint)
                marker(symbol: "−", color: Self.removedGutterTint)
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.leading, DT.Space.xs)
                Spacer(minLength: 0)
            }
            .background(Self.removedBackground)

        case .context(let content, let oldLine, let newLine):
            HStack(spacing: 0) {
                gutterCell(text: "\(oldLine)", tint: .tertiary)
                gutterCell(text: "\(newLine)", tint: .tertiary)
                marker(symbol: " ", color: .clear)
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.leading, DT.Space.xs)
                Spacer(minLength: 0)
            }
        }
    }

    private func gutterCell<S: ShapeStyle>(text: String, tint: S) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(tint)
            .frame(width: Self.gutterWidth, alignment: .trailing)
            .padding(.trailing, 8)
            .padding(.vertical, 1)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func marker(symbol: String, color: Color) -> some View {
        Text(symbol)
            .font(.system(.caption, design: .monospaced).weight(.bold))
            .foregroundStyle(color)
            .frame(width: Self.markerWidth, alignment: .center)
    }
}

// MARK: - Split (side-by-side) rendering

/// Renders `SplitRow`s (built by `SplitDiffBuilder`) as two columns divided
/// by a vertical rule. Long lines wrap rather than scroll horizontally —
/// keeping the two sides' scroll positions in sync for a wrapped, variable-
/// height layout isn't worth the complexity this early on.
struct SplitDiffView: View {
    let rows: [SplitRow]

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { idx in
                    SplitDiffRowView(row: rows[idx])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct SplitDiffRowView: View {
    let row: SplitRow

    var body: some View {
        switch row {
        case .fileHeader(let s):
            fullWidthRow(text: s, background: Color(nsColor: .controlBackgroundColor).opacity(0.6), foreground: .secondary, weight: .regular)

        case .hunkHeader(let s):
            fullWidthRow(text: s, background: Color.accentColor.opacity(0.08), foreground: .tint, weight: .medium)

        case .pair(let left, let right):
            HStack(alignment: .top, spacing: 0) {
                cell(left)
                Divider()
                cell(right)
            }
        }
    }

    private func fullWidthRow<S: ShapeStyle>(text: String, background: Color, foreground: S, weight: Font.Weight) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(weight))
            .foregroundStyle(foreground)
            .padding(.horizontal, DT.Space.md)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
    }

    @ViewBuilder
    private func cell(_ cell: SplitCell?) -> some View {
        HStack(spacing: 0) {
            Text(cell.map { "\($0.number)" } ?? "")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(gutterTint(for: cell))
                .frame(width: DiffLineRow.gutterWidth, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.vertical, 1)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            Text(cell?.text ?? "")
                .font(.system(.callout, design: .monospaced))
                .padding(.leading, DT.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Stretches each cell to the row's full height (the taller of the two
        // sides) so a wrapped line's background doesn't stop short partway
        // down the row.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background(for: cell))
    }

    private func gutterTint(for cell: SplitCell?) -> Color {
        switch cell?.kind {
        case .added: return DiffLineRow.addedGutterTint
        case .removed: return DiffLineRow.removedGutterTint
        case .context: return .secondary
        case nil: return .clear
        }
    }

    private func background(for cell: SplitCell?) -> Color {
        switch cell?.kind {
        case .added: return DiffLineRow.addedBackground
        case .removed: return DiffLineRow.removedBackground
        case .context, nil: return .clear
        }
    }
}
