import Foundation

/// Builds a hierarchical `FileNode` tree from a flat list of git-known paths.
enum FileTreeBuilder {
    static func build(from paths: [String], repositoryURL: URL) -> [FileNode] {
        // Internal mutable representation used while we walk the input paths.
        final class Builder {
            var name: String
            var path: String
            var isDirectory: Bool
            var children: [String: Builder] = [:]

            init(name: String, path: String, isDirectory: Bool) {
                self.name = name
                self.path = path
                self.isDirectory = isDirectory
            }
        }

        let root = Builder(name: "", path: "", isDirectory: true)

        for raw in paths {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let components = trimmed.split(separator: "/").map(String.init)
            var current = root
            for (i, component) in components.enumerated() {
                let isLast = (i == components.count - 1)
                if let existing = current.children[component] {
                    current = existing
                } else {
                    let path = current.path.isEmpty ? component : "\(current.path)/\(component)"
                    let node = Builder(
                        name: component,
                        path: path,
                        isDirectory: !isLast
                    )
                    current.children[component] = node
                    current = node
                }
                if !isLast {
                    current.isDirectory = true
                }
            }
        }

        func convert(_ b: Builder) -> FileNode {
            let url = b.path.isEmpty ? repositoryURL : repositoryURL.appendingPathComponent(b.path)
            let kids: [FileNode]? = b.isDirectory
                ? b.children.values.map(convert).sorted(by: nodeOrdering)
                : nil
            return FileNode(
                path: b.path,
                name: b.name,
                url: url,
                isDirectory: b.isDirectory,
                children: kids
            )
        }

        return root.children.values.map(convert).sorted(by: nodeOrdering)
    }

    /// Directories first, both groups alphabetical (case-insensitive).
    static func nodeOrdering(_ a: FileNode, _ b: FileNode) -> Bool {
        if a.isDirectory != b.isDirectory {
            return a.isDirectory
        }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}
