import SwiftUI

/// VSCode / Cursor–style file tree sidebar. Click a file to view its content
/// in the right pane via `FileViewerPane`.
struct ExplorerSidebar: View {
    @ObservedObject var viewModel: ExplorerViewModel
    let onSelect: (FileNode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .task {
            if viewModel.rootNodes.isEmpty {
                await viewModel.load()
            }
        }
    }

    private var header: some View {
        HStack(spacing: DT.Space.sm) {
            Text(L("エクスプローラ"))
                .font(.body.weight(.semibold))
            Spacer()
            Button {
                Task { await viewModel.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .help(L("更新"))
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm + 2)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.rootNodes.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = viewModel.lastError {
            errorState(error)
        } else if viewModel.rootNodes.isEmpty {
            VStack(spacing: DT.Space.sm) {
                Spacer()
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(L("ファイルがありません"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.rootNodes) { node in
                        FileTreeNodeRow(node: node, depth: 0, onSelect: onSelect)
                    }
                }
                .padding(.vertical, DT.Space.xs)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: DT.Space.sm) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemRed))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Space.md)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FileTreeNodeRow: View {
    let node: FileNode
    let depth: Int
    let onSelect: (FileNode) -> Void

    @State private var isExpanded: Bool = false
    @State private var isHovering: Bool = false

    private var iconSystemName: String {
        if node.isDirectory {
            return isExpanded ? "folder.fill" : "folder.fill"
        }
        return iconForFile(node.name)
    }

    private var iconColor: Color {
        node.isDirectory ? Color(nsColor: .systemBlue).opacity(0.85) : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
                .background(
                    Rectangle()
                        .fill(isHovering
                              ? Color.accentColor.opacity(0.08)
                              : Color.clear)
                )
                .onHover { isHovering = $0 }
                .contentShape(Rectangle())
                .onTapGesture {
                    if node.isDirectory {
                        withAnimation(.easeOut(duration: 0.12)) {
                            isExpanded.toggle()
                        }
                    } else {
                        onSelect(node)
                    }
                }
            if isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileTreeNodeRow(node: child, depth: depth + 1, onSelect: onSelect)
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            // Indentation
            Color.clear.frame(width: CGFloat(depth) * 14)

            // Disclosure chevron (directories only)
            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }

            // Icon
            Image(systemName: iconSystemName)
                .imageScale(.medium)
                .foregroundStyle(iconColor)
                .frame(width: 18)

            // Name
            Text(node.name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DT.Space.sm)
        .padding(.vertical, 4)
    }
}

/// Tiny extension-based icon picker. Good enough for the explorer without
/// pulling in a full icon set.
private func iconForFile(_ name: String) -> String {
    let lower = name.lowercased()
    if lower.hasSuffix(".swift") { return "swift" }
    if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") { return "doc.richtext" }
    if lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") || lower.hasSuffix(".toml") { return "curlybraces" }
    if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".gif") || lower.hasSuffix(".svg") || lower.hasSuffix(".webp") { return "photo" }
    if lower.hasSuffix(".sh") || lower.hasSuffix(".bash") || lower.hasSuffix(".zsh") { return "terminal" }
    if lower.hasSuffix(".strings") || lower.hasSuffix(".plist") || lower.hasSuffix(".xcconfig") { return "doc.text" }
    if lower == ".gitignore" || lower == ".gitattributes" { return "doc.append" }
    if lower.hasSuffix(".lock") { return "lock" }
    return "doc.text"
}
