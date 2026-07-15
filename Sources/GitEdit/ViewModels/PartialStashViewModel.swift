import Foundation

/// View model backing `PartialStashSheet`. Loads each eligible file's diff
/// against HEAD, tracks the user's hunk/line selections, and builds the
/// combined patch handed to `RepositoryViewModel.createPartialStash`.
@MainActor
final class PartialStashViewModel: ObservableObject {
    struct FileEntry: Identifiable {
        let change: FileChange
        let fileDiff: FileDiff
        var id: String { change.path }
    }

    /// Identifies one `+`/`-` line within a specific file's specific hunk.
    struct LineKey: Hashable {
        let hunkIndex: Int
        let lineIndex: Int
    }

    @Published private(set) var entries: [FileEntry] = []
    @Published private(set) var selection: [String: Set<LineKey>] = [:]
    @Published var isLoading: Bool = false

    private let git: GitClient

    init(git: GitClient) {
        self.git = git
    }

    var isEmpty: Bool { entries.isEmpty }
    var selectedCount: Int { selection.values.reduce(0) { $0 + $1.count } }
    var hasSelection: Bool { selectedCount > 0 }

    /// Reads current status and loads the HEAD-relative diff for every
    /// eligible file. Eligibility matches the criteria for hunk staging:
    /// tracked, not renamed, not conflicted, and — once parsed — not binary
    /// and non-empty.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        let changes = (try? await git.status()) ?? []
        let eligible = changes.filter { !$0.isUntracked && $0.renameFrom == nil && !$0.isConflicted }
        var result: [FileEntry] = []
        for change in eligible {
            guard let diffText = try? await git.diffAgainstHEAD(path: change.path) else { continue }
            let fileDiff = PatchBuilder.parse(diffText)
            guard !fileDiff.isBinary, !fileDiff.hunks.isEmpty else { continue }
            result.append(FileEntry(change: change, fileDiff: fileDiff))
        }
        entries = result
        selection = [:]
    }

    // MARK: - Line-level selection

    func isLineSelected(path: String, hunkIndex: Int, lineIndex: Int) -> Bool {
        selection[path]?.contains(LineKey(hunkIndex: hunkIndex, lineIndex: lineIndex)) ?? false
    }

    func toggleLine(path: String, hunkIndex: Int, lineIndex: Int) {
        var set = selection[path] ?? []
        let key = LineKey(hunkIndex: hunkIndex, lineIndex: lineIndex)
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        setSelection(set, for: path)
    }

    // MARK: - Hunk-level selection (select/deselect every changed line in the hunk)

    func isHunkFullySelected(path: String, hunkIndex: Int, hunk: DiffHunk) -> Bool {
        let changeable = changeableIndices(in: hunk)
        guard !changeable.isEmpty else { return false }
        let set = selection[path] ?? []
        return changeable.allSatisfy { set.contains(LineKey(hunkIndex: hunkIndex, lineIndex: $0)) }
    }

    func toggleHunk(path: String, hunkIndex: Int, hunk: DiffHunk) {
        var set = selection[path] ?? []
        let turnOn = !isHunkFullySelected(path: path, hunkIndex: hunkIndex, hunk: hunk)
        for index in changeableIndices(in: hunk) {
            let key = LineKey(hunkIndex: hunkIndex, lineIndex: index)
            if turnOn { set.insert(key) } else { set.remove(key) }
        }
        setSelection(set, for: path)
    }

    // MARK: - File-level selection (select/deselect every changed line in the file)

    func isFileFullySelected(_ entry: FileEntry) -> Bool {
        let set = selection[entry.change.path] ?? []
        for (hunkIndex, hunk) in entry.fileDiff.hunks.enumerated() {
            let changeable = changeableIndices(in: hunk)
            guard !changeable.isEmpty else { continue }
            if !changeable.allSatisfy({ set.contains(LineKey(hunkIndex: hunkIndex, lineIndex: $0)) }) {
                return false
            }
        }
        return true
    }

    func toggleFile(_ entry: FileEntry) {
        let turnOn = !isFileFullySelected(entry)
        var set: Set<LineKey> = []
        if turnOn {
            for (hunkIndex, hunk) in entry.fileDiff.hunks.enumerated() {
                for index in changeableIndices(in: hunk) {
                    set.insert(LineKey(hunkIndex: hunkIndex, lineIndex: index))
                }
            }
        }
        setSelection(set, for: entry.change.path)
    }

    private func changeableIndices(in hunk: DiffHunk) -> Set<Int> {
        Set(hunk.lines.indices.filter { hunk.lines[$0].kind != .context })
    }

    private func setSelection(_ set: Set<LineKey>, for path: String) {
        if set.isEmpty {
            selection.removeValue(forKey: path)
        } else {
            selection[path] = set
        }
    }

    // MARK: - Patch building

    /// Builds the combined multi-file patch from the current selection, in
    /// `entries` display order. `nil` when nothing is selected.
    func buildPatch() -> String? {
        var files: [(fileDiff: FileDiff, selections: [(hunk: DiffHunk, selectedLineIndices: Set<Int>)])] = []
        for entry in entries {
            guard let keys = selection[entry.change.path], !keys.isEmpty else { continue }
            var perHunk: [Int: Set<Int>] = [:]
            for key in keys {
                perHunk[key.hunkIndex, default: []].insert(key.lineIndex)
            }
            let selections = entry.fileDiff.hunks.indices.compactMap { hunkIndex -> (hunk: DiffHunk, selectedLineIndices: Set<Int>)? in
                guard let indices = perHunk[hunkIndex], !indices.isEmpty else { return nil }
                return (hunk: entry.fileDiff.hunks[hunkIndex], selectedLineIndices: indices)
            }
            guard !selections.isEmpty else { continue }
            files.append((fileDiff: entry.fileDiff, selections: selections))
        }
        guard !files.isEmpty else { return nil }
        return PatchBuilder.combinedPatch(files: files)
    }
}
