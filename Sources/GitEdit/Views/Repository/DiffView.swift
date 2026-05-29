import SwiftUI

struct DiffView: View {
    let diffText: String
    let isLoading: Bool
    let selectedFile: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(selectedFile ?? "ファイル未選択")
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
            placeholder(
                icon: "doc.text.magnifyingglass",
                title: "左のリストからファイルを選択",
                subtitle: "差分がここに表示されます"
            )
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        } else if diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            placeholder(
                icon: "equal.circle",
                title: "差分なし",
                subtitle: nil
            )
        } else {
            ScrollView([.vertical, .horizontal]) {
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

    private func placeholder(icon: String, title: String, subtitle: String?) -> some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

enum DiffLine: Hashable {
    case fileHeader(String)
    case hunkHeader(String)
    case added(String)
    case removed(String)
    case context(String)
}

enum DiffParser {
    static func parse(_ text: String) -> [DiffLine] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(parseLine)
    }

    private static func parseLine(_ line: Substring) -> DiffLine {
        let s = String(line)
        if s.hasPrefix("diff --git") || s.hasPrefix("index ")
            || s.hasPrefix("--- ") || s.hasPrefix("+++ ")
            || s.hasPrefix("new file") || s.hasPrefix("deleted file")
            || s.hasPrefix("old mode") || s.hasPrefix("new mode")
            || s.hasPrefix("similarity") || s.hasPrefix("rename ")
            || s.hasPrefix("copy ") || s.hasPrefix("Binary files") {
            return .fileHeader(s)
        }
        if s.hasPrefix("@@") {
            return .hunkHeader(s)
        }
        if s.hasPrefix("+") { return .added(String(s.dropFirst())) }
        if s.hasPrefix("-") { return .removed(String(s.dropFirst())) }
        if s.hasPrefix(" ") { return .context(String(s.dropFirst())) }
        return .context(s)
    }
}

struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        switch line {
        case .fileHeader(let s):
            Text(s)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DT.Space.md)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        case .hunkHeader(let s):
            Text(s)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.tint)
                .padding(.horizontal, DT.Space.md)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08))
        case .added(let s):
            HStack(spacing: 0) {
                Text("+")
                    .frame(width: 16)
                    .foregroundStyle(Color(nsColor: .systemGreen))
                Text(s)
                    .font(.system(.callout, design: .monospaced))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DT.Space.sm)
            .padding(.vertical, 0.5)
            .background(Color(nsColor: .systemGreen).opacity(0.13))
        case .removed(let s):
            HStack(spacing: 0) {
                Text("-")
                    .frame(width: 16)
                    .foregroundStyle(Color(nsColor: .systemRed))
                Text(s)
                    .font(.system(.callout, design: .monospaced))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DT.Space.sm)
            .padding(.vertical, 0.5)
            .background(Color(nsColor: .systemRed).opacity(0.13))
        case .context(let s):
            HStack(spacing: 0) {
                Text(" ")
                    .frame(width: 16)
                Text(s)
                    .font(.system(.callout, design: .monospaced))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DT.Space.sm)
            .padding(.vertical, 0.5)
        }
    }
}
