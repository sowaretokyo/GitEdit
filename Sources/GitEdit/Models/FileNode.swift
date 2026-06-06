import Foundation

/// One node in a file-tree view (a directory or a file).
struct FileNode: Identifiable, Hashable {
    /// Repository-relative path. Empty for the synthetic root.
    let path: String
    /// Last path component.
    let name: String
    /// Absolute URL on disk.
    let url: URL
    let isDirectory: Bool
    /// `nil` for files; for directories, the sorted children
    /// (directories first, then files, both alphabetical).
    var children: [FileNode]?

    var id: String { path }
}
