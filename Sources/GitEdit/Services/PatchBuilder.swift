import Foundation

/// One physical line inside a hunk's body (the part below the `@@` header).
struct PatchLine: Hashable {
    enum Kind: Hashable {
        case context, added, removed
    }

    let kind: Kind
    /// Line content without the leading `+`/`-`/` ` marker. May retain a
    /// trailing `\r` when the source file uses CRLF line endings — that byte
    /// is part of the content, not something we strip.
    let content: String
    /// True when this line is immediately followed by a
    /// `\ No newline at end of file` marker in the source diff.
    let noNewlineAtEOF: Bool
}

/// A single `@@ -oldStart,oldCount +newStart,newCount @@` block and its lines.
struct DiffHunk: Hashable {
    /// Recomputed `@@ ... @@` text for display. Any trailing function-name
    /// annotation from the source diff is dropped — it's not needed here.
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [PatchLine]
}

/// A parsed `git diff` for one file: everything above the first `@@` (file
/// mode / rename / index lines) plus the hunks below it.
struct FileDiff: Hashable {
    let headerLines: [String]
    let hunks: [DiffHunk]
    let isBinary: Bool
}

/// Parses `git diff` output into a structured `FileDiff`, and builds minimal
/// patches from a subset of hunks/lines suitable for `git apply --cached`
/// (optionally `--reverse`). This is what powers hunk- and line-level staging.
///
/// The core rule for partial selection within a hunk: context lines always
/// pass through, a selected `+` stays `+`, an unselected `+` is dropped
/// entirely, a selected `-` stays `-`, and an unselected `-` is turned into a
/// context line (its content survives — we're just choosing not to remove it
/// yet). `oldStart`/`oldCount` never change since every original old-file
/// line is still represented (as context, or as `-`). Only the new-side
/// count shrinks when `+` lines are dropped, so `newStart` for hunks after
/// the first one must be corrected by the cumulative drift introduced by
/// earlier hunks *that are actually included in this patch*.
enum PatchBuilder {

    // MARK: - Parsing

    static func parse(_ diffText: String) -> FileDiff {
        var headerLines: [String] = []
        var hunks: [DiffHunk] = []
        var isBinary = false

        var currentLines: [PatchLine] = []
        var currentOldStart = 0, currentOldCount = 0, currentNewStart = 0, currentNewCount = 0
        var inHunk = false

        func flushHunk() {
            guard inHunk else { return }
            hunks.append(DiffHunk(
                header: hunkHeaderText(
                    oldStart: currentOldStart, oldCount: currentOldCount,
                    newStart: currentNewStart, newCount: currentNewCount
                ),
                oldStart: currentOldStart,
                oldCount: currentOldCount,
                newStart: currentNewStart,
                newCount: currentNewCount,
                lines: currentLines
            ))
            currentLines = []
            inHunk = false
        }

        for line in diffText.components(separatedBy: "\n") {
            if line.hasPrefix("@@"), let parsed = parseHunkHeader(line) {
                flushHunk()
                inHunk = true
                (currentOldStart, currentOldCount, currentNewStart, currentNewCount) = parsed
                continue
            }

            if !inHunk {
                guard !line.isEmpty else { continue } // trailing split artifact
                if line.hasPrefix("Binary files") { isBinary = true }
                headerLines.append(line)
                continue
            }

            if line.hasPrefix("\\") {
                // "\ No newline at end of file" — tag the line it follows.
                if let last = currentLines.popLast() {
                    currentLines.append(PatchLine(kind: last.kind, content: last.content, noNewlineAtEOF: true))
                }
                continue
            }

            if line.hasPrefix("+") {
                currentLines.append(PatchLine(kind: .added, content: String(line.dropFirst()), noNewlineAtEOF: false))
            } else if line.hasPrefix("-") {
                currentLines.append(PatchLine(kind: .removed, content: String(line.dropFirst()), noNewlineAtEOF: false))
            } else if line.hasPrefix(" ") {
                currentLines.append(PatchLine(kind: .context, content: String(line.dropFirst()), noNewlineAtEOF: false))
            } else if line.isEmpty {
                continue // trailing split artifact
            } else {
                // Unknown marker — treat as context to avoid losing content.
                currentLines.append(PatchLine(kind: .context, content: line, noNewlineAtEOF: false))
            }
        }
        flushHunk()

        return FileDiff(headerLines: headerLines, hunks: hunks, isBinary: isBinary)
    }

    private static let hunkHeaderRegex = try! NSRegularExpression(
        pattern: #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
    )

    private static func parseHunkHeader(_ line: String) -> (Int, Int, Int, Int)? {
        let ns = line as NSString
        guard let match = hunkHeaderRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        func group(_ i: Int) -> String? {
            let r = match.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        let oldStart = Int(group(1) ?? "") ?? 0
        let oldCount = group(2).flatMap(Int.init) ?? 1
        let newStart = Int(group(3) ?? "") ?? 0
        let newCount = group(4).flatMap(Int.init) ?? 1
        return (oldStart, oldCount, newStart, newCount)
    }

    // MARK: - Patch construction

    /// Whole-hunk patch — every changed line is kept, so this reproduces the
    /// hunk exactly. Used for "stage/unstage this hunk".
    static func patch(for hunk: DiffHunk, in fileDiff: FileDiff) -> String {
        let allChangedIndices = Set(hunk.lines.indices.filter { hunk.lines[$0].kind != .context })
        return patch(for: hunk, selectedLineIndices: allChangedIndices, in: fileDiff)
    }

    /// Single-hunk patch keeping only `selectedLineIndices` (indices into
    /// `hunk.lines`) of the `+`/`-` lines. Used when the user checks
    /// individual lines within one hunk.
    static func patch(for hunk: DiffHunk, selectedLineIndices: Set<Int>, in fileDiff: FileDiff) -> String {
        patch(selections: [(hunk: hunk, selectedLineIndices: selectedLineIndices)], in: fileDiff)
    }

    /// Multi-hunk patch: each entry contributes only its own selected `+`/`-`
    /// lines. `selections` must be in file order (the order hunks appear in
    /// `fileDiff.hunks`) since `newStart` drift accumulates across entries.
    static func patch(
        selections: [(hunk: DiffHunk, selectedLineIndices: Set<Int>)],
        in fileDiff: FileDiff
    ) -> String {
        var lines = fileDiff.headerLines.filter { !isModeOnlyLine($0) }
        var drift = 0

        for (hunk, selected) in selections {
            let filtered = filterLines(hunk.lines, selected: selected)
            guard filtered.contains(where: { $0.kind != .context }) else { continue }

            let oldCount = filtered.filter { $0.kind != .added }.count
            let newCount = filtered.filter { $0.kind != .removed }.count

            let newStart: Int
            if oldCount == 0 {
                // Pure insertion: the old side has no line of its own, so the
                // new side starts one past the anchor (matches `git diff`'s
                // convention for brand-new files, e.g. "@@ -0,0 +1,N @@").
                newStart = hunk.oldStart + drift + 1
            } else if newCount == 0 {
                // Pure deletion: nothing survives on the new side, so the
                // anchor points one *before* the old start (matches
                // `git diff`'s convention for whole-file deletions).
                newStart = hunk.oldStart + drift - 1
            } else {
                newStart = hunk.oldStart + drift
            }

            lines.append(hunkHeaderText(oldStart: hunk.oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount))
            for line in filtered {
                lines.append(marker(line.kind) + line.content)
                if line.noNewlineAtEOF {
                    lines.append("\\ No newline at end of file")
                }
            }
            drift += newCount - oldCount
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func filterLines(_ lines: [PatchLine], selected: Set<Int>) -> [PatchLine] {
        var result: [PatchLine] = []
        for (index, line) in lines.enumerated() {
            switch line.kind {
            case .context:
                result.append(line)
            case .added:
                if selected.contains(index) { result.append(line) }
            case .removed:
                if selected.contains(index) {
                    result.append(line)
                } else {
                    result.append(PatchLine(kind: .context, content: line.content, noNewlineAtEOF: line.noNewlineAtEOF))
                }
            }
        }
        return suppressUnrepresentableEOFMarkers(result)
    }

    /// A `\ No newline at end of file` marker means "this side's content ends
    /// here" — which is only meaningful if nothing belonging to that side
    /// follows in the filtered hunk. Converting an unselected `-` to context
    /// can leave its marker attached to a line that no longer is the true
    /// end (e.g. a selected `+` now follows it): keeping it there would tell
    /// `git apply` to concatenate the next line without a newline, silently
    /// corrupting the result. We drop the marker in that case — `git apply`
    /// then either succeeds without it, or fails loudly (surfaced via the
    /// existing stderr banner), which beats corrupting file content.
    private static func suppressUnrepresentableEOFMarkers(_ lines: [PatchLine]) -> [PatchLine] {
        var result = lines
        for index in result.indices where result[index].noNewlineAtEOF {
            let after = result[(index + 1)...]
            let stillValid: Bool
            switch result[index].kind {
            case .removed: stillValid = after.allSatisfy { $0.kind == .added }
            case .added: stillValid = after.allSatisfy { $0.kind == .removed }
            case .context: stillValid = after.isEmpty
            }
            if !stillValid {
                result[index] = PatchLine(kind: result[index].kind, content: result[index].content, noNewlineAtEOF: false)
            }
        }
        return result
    }

    /// Formats a hunk header, omitting `,count` when it's 1 — matching
    /// `git diff`'s own convention so a whole-hunk patch is byte-identical
    /// to the source diff.
    private static func hunkHeaderText(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) -> String {
        func range(_ start: Int, _ count: Int) -> String {
            count == 1 ? "\(start)" : "\(start),\(count)"
        }
        return "@@ -\(range(oldStart, oldCount)) +\(range(newStart, newCount)) @@"
    }

    private static func marker(_ kind: PatchLine.Kind) -> String {
        switch kind {
        case .context: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    /// `old mode` / `new mode` lines only describe a permission change and
    /// have no place in a content-only patch. `new file mode` / `deleted
    /// file mode` are kept — they're required for `git apply` to create or
    /// remove the blob.
    private static func isModeOnlyLine(_ line: String) -> Bool {
        line.hasPrefix("old mode") || line.hasPrefix("new mode")
    }
}
