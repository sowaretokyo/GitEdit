import SwiftUI

struct DiffView: View {
    let diffText: String
    let isLoading: Bool
    let selectedFile: String?
    /// When false the path-strip header is suppressed (e.g. when the parent
    /// already shows the same path, like in `DiffEditView`).
    var showsHeader: Bool = true

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
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        } else if diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyStateView(icon: "equal.circle", title: L("差分なし"))
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let parsed = DiffParser.parse(diffText)
                    ForEach(parsed.indices, id: \.self) { idx in
                        DiffLineRow(line: parsed[idx])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
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

    private static let gutterWidth: CGFloat = 44
    private static let markerWidth: CGFloat = 16

    private var addedBackground: Color { Color(nsColor: .systemGreen).opacity(0.12) }
    private var removedBackground: Color { Color(nsColor: .systemRed).opacity(0.12) }
    private var addedGutterTint: Color { Color(nsColor: .systemGreen) }
    private var removedGutterTint: Color { Color(nsColor: .systemRed) }

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
                gutterCell(text: "", tint: addedGutterTint)
                gutterCell(text: "\(newLine)", tint: addedGutterTint)
                marker(symbol: "+", color: addedGutterTint)
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.leading, DT.Space.xs)
                Spacer(minLength: 0)
            }
            .background(addedBackground)

        case .removed(let content, let oldLine):
            HStack(spacing: 0) {
                gutterCell(text: "\(oldLine)", tint: removedGutterTint)
                gutterCell(text: "", tint: removedGutterTint)
                marker(symbol: "−", color: removedGutterTint)
                Text(content)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.leading, DT.Space.xs)
                Spacer(minLength: 0)
            }
            .background(removedBackground)

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
