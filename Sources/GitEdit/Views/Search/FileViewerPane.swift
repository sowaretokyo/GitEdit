import SwiftUI

/// Read-only file viewer used as the right-hand detail pane for search
/// results. Shows the full file with line numbers, highlights and
/// auto-scrolls to a target line.
struct FileViewerPane: View {
    let repositoryURL: URL
    let path: String
    /// 1-based line to highlight + scroll to.
    let highlightLine: Int?

    @State private var content: String = ""
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            body_
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: "\(path)#\(highlightLine ?? 0)") {
            await load()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DT.Space.sm) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text(path)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
            if let line = highlightLine {
                Text("L\(line)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm + 2)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Body

    @ViewBuilder
    private var body_: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            errorState(error)
        } else if content.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let lines = content.components(separatedBy: "\n")
                        ForEach(lines.indices, id: \.self) { idx in
                            FileViewerRow(
                                lineNumber: idx + 1,
                                text: lines[idx],
                                isHighlighted: highlightLine == idx + 1
                            )
                            .id(idx + 1)
                        }
                    }
                    .padding(.vertical, DT.Space.xs)
                }
                .onAppear {
                    scrollToHighlight(proxy: proxy)
                }
                .onChange(of: highlightLine) { _, _ in
                    scrollToHighlight(proxy: proxy)
                }
            }
        }
    }

    private func scrollToHighlight(proxy: ScrollViewProxy) {
        guard let line = highlightLine else { return }
        // Delay slightly so the LazyVStack has rendered.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(line, anchor: .center)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DT.Space.sm) {
            Image(systemName: "doc")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("ファイルが空です"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: DT.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemRed))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Space.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        loadError = nil
        let url = repositoryURL.appendingPathComponent(path)
        let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                return .success(text)
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let text):
            content = text
            loadError = nil
        case .failure(let error):
            content = ""
            loadError = L("ファイルの読み込みに失敗: %@", error.localizedDescription)
        }
        isLoading = false
    }
}

private struct FileViewerRow: View {
    let lineNumber: Int
    let text: String
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(lineNumber)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(isHighlighted
                                 ? Color(nsColor: .systemYellow)
                                 : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 50, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.vertical, 1)
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 0.5)
        .background(
            isHighlighted
            ? Color(nsColor: .systemYellow).opacity(0.18)
            : Color.clear
        )
    }
}
