import XCTest
@testable import GitEdit

final class PatchBuilderTests: XCTestCase {

    // MARK: - Parsing

    func testParseSplitsHeaderLinesFromHunks() {
        let diff = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,2 +1,2 @@",
            " keep",
            "-old",
            "+new"
        ].joined(separator: "\n")

        let parsed = PatchBuilder.parse(diff)

        XCTAssertEqual(parsed.headerLines, [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt"
        ])
        XCTAssertEqual(parsed.hunks.count, 1)
        XCTAssertFalse(parsed.isBinary)
    }

    func testParseExtractsHunkHeaderNumbersDefaultingOmittedCountsToOne() {
        let diff = "@@ -5 +5,2 @@\n-old\n+new1\n+new2"
        let hunk = PatchBuilder.parse(diff).hunks[0]
        XCTAssertEqual(hunk.oldStart, 5)
        XCTAssertEqual(hunk.oldCount, 1) // omitted -> defaults to 1
        XCTAssertEqual(hunk.newStart, 5)
        XCTAssertEqual(hunk.newCount, 2)
    }

    func testParseFoldsNoNewlineMarkerIntoPrecedingLine() {
        let diff = "@@ -1,1 +1,1 @@\n-old\n\\ No newline at end of file\n+new\n\\ No newline at end of file"
        let hunk = PatchBuilder.parse(diff).hunks[0]
        XCTAssertEqual(hunk.lines.count, 2)
        XCTAssertTrue(hunk.lines[0].noNewlineAtEOF)
        XCTAssertTrue(hunk.lines[1].noNewlineAtEOF)
    }

    func testParseDetectsBinaryFiles() {
        let diff = [
            "diff --git a/img.png b/img.png",
            "index aaaaaaa..bbbbbbb 100644",
            "Binary files a/img.png and b/img.png differ"
        ].joined(separator: "\n")

        let parsed = PatchBuilder.parse(diff)
        XCTAssertTrue(parsed.isBinary)
        XCTAssertTrue(parsed.hunks.isEmpty)
    }

    // MARK: - Whole hunk ("stage/unstage this hunk")

    /// The `@@ -1,4 +1,4 @@` worked example used by several tests below:
    /// two lines of context, a `-`/`+` replacement pair, one more context line.
    private func makeWorkedExampleFileDiff() -> (FileDiff, DiffHunk) {
        let diff = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,4 +1,4 @@",
            " c1",
            " c2",
            "-old",
            "+new",
            " c3"
        ].joined(separator: "\n")
        let fileDiff = PatchBuilder.parse(diff)
        return (fileDiff, fileDiff.hunks[0])
    }

    func testWholeHunkPatchReproducesOriginalExactly() {
        let (fileDiff, hunk) = makeWorkedExampleFileDiff()

        let patch = PatchBuilder.patch(for: hunk, in: fileDiff)

        let expected = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,4 +1,4 @@",
            " c1",
            " c2",
            "-old",
            "+new",
            " c3",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
    }

    // MARK: - Partial line selection within one hunk

    func testPartialSelectionDropsUnselectedAddedLine() {
        // Select only the `-old` line; the unselected `+new` must vanish
        // entirely (not just its marker — the whole line).
        let (fileDiff, hunk) = makeWorkedExampleFileDiff()
        let removedIndex = hunk.lines.firstIndex { $0.kind == .removed }!

        let patch = PatchBuilder.patch(for: hunk, selectedLineIndices: [removedIndex], in: fileDiff)

        let expected = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,4 +1,3 @@",
            " c1",
            " c2",
            "-old",
            " c3",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
        XCTAssertFalse(patch.contains("new"))
    }

    func testPartialSelectionConvertsUnselectedRemovedLineToContext() {
        // Select only the `+new` line; the unselected `-old` must survive as
        // an unchanged context line rather than being removed.
        let (fileDiff, hunk) = makeWorkedExampleFileDiff()
        let addedIndex = hunk.lines.firstIndex { $0.kind == .added }!

        let patch = PatchBuilder.patch(for: hunk, selectedLineIndices: [addedIndex], in: fileDiff)

        let expected = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,4 +1,5 @@",
            " c1",
            " c2",
            " old",
            "+new",
            " c3",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
    }

    // MARK: - Multi-hunk cumulative newStart correction

    func testMultiHunkSelectionCorrectsNewStartDrift() {
        // Hunk 1 inserts two lines (INS_A, INS_B); hunk 2 removes one line
        // ("15"). Selecting only INS_A from hunk 1 and the removal from
        // hunk 2 must shift hunk 2's newStart by the +1 drift hunk 1
        // introduces — this exact patch was verified against real `git
        // apply` while designing the algorithm.
        let diff = [
            "diff --git a/g.txt b/g.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/g.txt",
            "+++ b/g.txt",
            "@@ -1,5 +1,7 @@",
            " 1",
            " 2",
            "+INS_A",
            "+INS_B",
            " 3",
            " 4",
            " 5",
            "@@ -12,7 +14,6 @@",
            " 12",
            " 13",
            " 14",
            "-15",
            " 16",
            " 17",
            " 18"
        ].joined(separator: "\n")
        let fileDiff = PatchBuilder.parse(diff)
        XCTAssertEqual(fileDiff.hunks.count, 2)
        let hunk1 = fileDiff.hunks[0]
        let hunk2 = fileDiff.hunks[1]
        let insAIndex = hunk1.lines.firstIndex { $0.content == "INS_A" }!
        let removedIndex = hunk2.lines.firstIndex { $0.kind == .removed }!

        let patch = PatchBuilder.patch(
            selections: [
                (hunk: hunk1, selectedLineIndices: [insAIndex]),
                (hunk: hunk2, selectedLineIndices: [removedIndex])
            ],
            in: fileDiff
        )

        let expected = [
            "diff --git a/g.txt b/g.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/g.txt",
            "+++ b/g.txt",
            "@@ -1,5 +1,6 @@",
            " 1",
            " 2",
            "+INS_A",
            " 3",
            " 4",
            " 5",
            "@@ -12,7 +13,6 @@",
            " 12",
            " 13",
            " 14",
            "-15",
            " 16",
            " 17",
            " 18",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
    }

    // MARK: - New file / deleted file

    func testNewFilePatchUsesZeroOldStartConvention() {
        let diff = [
            "diff --git a/new.txt b/new.txt",
            "new file mode 100644",
            "index 0000000..aaaaaaa",
            "--- /dev/null",
            "+++ b/new.txt",
            "@@ -0,0 +1,2 @@",
            "+hello",
            "+world"
        ].joined(separator: "\n")
        let fileDiff = PatchBuilder.parse(diff)
        let hunk = fileDiff.hunks[0]
        XCTAssertEqual(hunk.oldStart, 0)
        XCTAssertEqual(hunk.oldCount, 0)

        let patch = PatchBuilder.patch(for: hunk, in: fileDiff)

        let expected = [
            "diff --git a/new.txt b/new.txt",
            "new file mode 100644",
            "index 0000000..aaaaaaa",
            "--- /dev/null",
            "+++ b/new.txt",
            "@@ -0,0 +1,2 @@",
            "+hello",
            "+world",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
    }

    func testDeletedFilePatchUsesZeroNewStartConvention() {
        let diff = [
            "diff --git a/gone.txt b/gone.txt",
            "deleted file mode 100644",
            "index aaaaaaa..0000000",
            "--- a/gone.txt",
            "+++ /dev/null",
            "@@ -1,2 +0,0 @@",
            "-hello",
            "-world"
        ].joined(separator: "\n")
        let fileDiff = PatchBuilder.parse(diff)
        let hunk = fileDiff.hunks[0]

        let patch = PatchBuilder.patch(for: hunk, in: fileDiff)

        let expected = [
            "diff --git a/gone.txt b/gone.txt",
            "deleted file mode 100644",
            "index aaaaaaa..0000000",
            "--- a/gone.txt",
            "+++ /dev/null",
            "@@ -1,2 +0,0 @@",
            "-hello",
            "-world",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
    }

    // MARK: - Mode-only lines

    func testModeOnlyLinesAreExcludedFromPatch() {
        let diff = [
            "diff --git a/m.txt b/m.txt",
            "old mode 100644",
            "new mode 100755",
            "index aaaaaaa..bbbbbbb",
            "--- a/m.txt",
            "+++ b/m.txt",
            "@@ -1,2 +1,2 @@",
            " x",
            "-y",
            "+z"
        ].joined(separator: "\n")
        let fileDiff = PatchBuilder.parse(diff)
        XCTAssertTrue(fileDiff.headerLines.contains("old mode 100644"))

        let patch = PatchBuilder.patch(for: fileDiff.hunks[0], in: fileDiff)

        XCTAssertFalse(patch.contains("old mode"))
        XCTAssertFalse(patch.contains("new mode"))
        let expected = [
            "diff --git a/m.txt b/m.txt",
            "index aaaaaaa..bbbbbbb",
            "--- a/m.txt",
            "+++ b/m.txt",
            "@@ -1,2 +1,2 @@",
            " x",
            "-y",
            "+z",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
    }

    // MARK: - CRLF

    func testCRLFContentIsPreservedByteForByte() {
        let diff = [
            "diff --git a/crlf.txt b/crlf.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/crlf.txt",
            "+++ b/crlf.txt",
            "@@ -1,2 +1,2 @@",
            " keep\r",
            "-old\r",
            "+new\r"
        ].joined(separator: "\n")
        let fileDiff = PatchBuilder.parse(diff)
        let hunk = fileDiff.hunks[0]

        XCTAssertEqual(hunk.lines.map(\.content), ["keep\r", "old\r", "new\r"])

        let patch = PatchBuilder.patch(for: hunk, in: fileDiff)
        let expected = [
            "diff --git a/crlf.txt b/crlf.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/crlf.txt",
            "+++ b/crlf.txt",
            "@@ -1,2 +1,2 @@",
            " keep\r",
            "-old\r",
            "+new\r",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
    }

    // MARK: - "No newline at end of file" markers

    func testNoNewlineMarkerKeptWhenLineRemainsLastOnItsSide() {
        // Both the old and new last lines lack a trailing newline; selecting
        // the whole hunk must reproduce both markers unchanged.
        let diff = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,2 +1,2 @@",
            " keep",
            "-old",
            "\\ No newline at end of file",
            "+new",
            "\\ No newline at end of file"
        ].joined(separator: "\n")
        let fileDiff = PatchBuilder.parse(diff)
        let hunk = fileDiff.hunks[0]

        let patch = PatchBuilder.patch(for: hunk, in: fileDiff)

        let expected = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,2 +1,2 @@",
            " keep",
            "-old",
            "\\ No newline at end of file",
            "+new",
            "\\ No newline at end of file",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
    }

    func testNoNewlineMarkerPreservedWhenConvertedLineIsStillLast() {
        // Two removals at EOF; only "-old" (the last line, no trailing
        // newline) is left unselected. It converts to context but, since
        // nothing follows it, its marker is still valid and must be kept.
        // ("-mid" stays selected so the hunk isn't a no-op.)
        let diff = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,3 +1,1 @@",
            " keep",
            "-mid",
            "-old",
            "\\ No newline at end of file"
        ].joined(separator: "\n")
        let fileDiff = PatchBuilder.parse(diff)
        let hunk = fileDiff.hunks[0]
        let midIndex = hunk.lines.firstIndex { $0.content == "mid" }!

        let patch = PatchBuilder.patch(for: hunk, selectedLineIndices: [midIndex], in: fileDiff)

        let expected = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,3 +1,2 @@",
            " keep",
            "-mid",
            " old",
            "\\ No newline at end of file",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
    }

    func testNoNewlineMarkerAndLineDroppedWithUnselectedAddedLine() {
        // Both "-old" and "+new" lack a trailing newline. Keeping only
        // "-old" (dropping "+new") must drop "+new"'s line and marker
        // entirely, while "-old"'s own marker is still valid (nothing
        // old-side follows it) and must be kept.
        let diff = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,2 +1,2 @@",
            " keep",
            "-old",
            "\\ No newline at end of file",
            "+new",
            "\\ No newline at end of file"
        ].joined(separator: "\n")
        let fileDiff = PatchBuilder.parse(diff)
        let hunk = fileDiff.hunks[0]
        let removedIndex = hunk.lines.firstIndex { $0.kind == .removed }!

        let patch = PatchBuilder.patch(for: hunk, selectedLineIndices: [removedIndex], in: fileDiff)

        let expected = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,2 +1 @@",
            " keep",
            "-old",
            "\\ No newline at end of file",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
        XCTAssertFalse(patch.contains("+new"))
    }

    func testNoNewlineMarkerSuppressedWhenConvertedLineNoLongerLast() {
        // Regression test for a corruption bug found while implementing this:
        // "-old" lacks a trailing newline, but is left unselected (converted
        // to context) while "+new" (selected) follows it. Naively keeping
        // "-old"'s marker would tell `git apply` to concatenate "new" right
        // after "old" with no separator, corrupting the file. The marker
        // must be suppressed once something follows the converted line.
        let diff = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,2 +1,2 @@",
            " keep",
            "-old",
            "\\ No newline at end of file",
            "+new"
        ].joined(separator: "\n")
        let fileDiff = PatchBuilder.parse(diff)
        let hunk = fileDiff.hunks[0]
        let addedIndex = hunk.lines.firstIndex { $0.kind == .added }!

        let patch = PatchBuilder.patch(for: hunk, selectedLineIndices: [addedIndex], in: fileDiff)

        XCTAssertFalse(patch.contains("\\ No newline"))
        let expected = [
            "diff --git a/f.txt b/f.txt",
            "index aaaaaaa..bbbbbbb 100644",
            "--- a/f.txt",
            "+++ b/f.txt",
            "@@ -1,2 +1,3 @@",
            " keep",
            " old",
            "+new",
            ""
        ].joined(separator: "\n")
        XCTAssertEqual(patch, expected)
    }
}

// MARK: - Real git round-trip integration test

final class PatchBuilderGitIntegrationTests: XCTestCase {
    private var repoURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitEditPatchBuilderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        repoURL = dir
        _ = try await GitClient.runGit(["init", "-q", "-b", "main"], cwd: dir)
        _ = try await GitClient.runGit(["config", "user.email", "test@example.com"], cwd: dir)
        _ = try await GitClient.runGit(["config", "user.name", "Test"], cwd: dir)
    }

    override func tearDown() async throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        repoURL = nil
        try await super.tearDown()
    }

    func testStageAndUnstagePartialHunkRoundTripsThroughRealGit() async throws {
        let fileURL = repoURL.appendingPathComponent("f.txt")
        let original = "line1\nline2\nline3\nline4\nline5\n"
        try original.write(to: fileURL, atomically: true, encoding: .utf8)
        _ = try await GitClient.runGit(["add", "f.txt"], cwd: repoURL)
        _ = try await GitClient.runGit(["commit", "-q", "-m", "init"], cwd: repoURL)

        // Two independent edits in one hunk: replace line2, and insert a new
        // line after line4. We'll stage only the replacement.
        let edited = "line1\nCHANGED2\nline3\nline4\nNEW5\nline5\n"
        try edited.write(to: fileURL, atomically: true, encoding: .utf8)

        let unstagedDiffText = try await GitClient.runGit(["diff", "--no-color", "--", "f.txt"], cwd: repoURL)
        let fileDiff = PatchBuilder.parse(unstagedDiffText)
        XCTAssertEqual(fileDiff.hunks.count, 1)
        let hunk = fileDiff.hunks[0]

        let removedIndex = hunk.lines.firstIndex { $0.kind == .removed && $0.content == "line2" }!
        let addedIndex = hunk.lines.firstIndex { $0.kind == .added && $0.content == "CHANGED2" }!

        let patch = PatchBuilder.patch(for: hunk, selectedLineIndices: [removedIndex, addedIndex], in: fileDiff)

        // --- Apply forward (stage) ---
        _ = try await GitClient.runGit(
            ["apply", "--cached", "--whitespace=nowarn"], cwd: repoURL, stdin: Data(patch.utf8)
        )

        let stagedDiff = try await GitClient.runGit(["diff", "--cached", "--no-color", "--", "f.txt"], cwd: repoURL)
        XCTAssertTrue(stagedDiff.contains("-line2"))
        XCTAssertTrue(stagedDiff.contains("+CHANGED2"))
        XCTAssertFalse(stagedDiff.contains("NEW5"), "the NEW5 insertion must still be unstaged")

        let remainingUnstagedDiff = try await GitClient.runGit(["diff", "--no-color", "--", "f.txt"], cwd: repoURL)
        XCTAssertTrue(remainingUnstagedDiff.contains("+NEW5"))
        // "CHANGED2" now shows only as unchanged context around the NEW5
        // hunk, not as a pending +/- change — the staged edit is done.
        XCTAssertFalse(remainingUnstagedDiff.contains("+CHANGED2"), "the staged change must no longer show as unstaged")
        XCTAssertFalse(remainingUnstagedDiff.contains("-line2"), "the staged change must no longer show as unstaged")

        // The index blob itself must contain exactly the staged content.
        let indexContent = try await GitClient.runGit(["show", ":f.txt"], cwd: repoURL)
        XCTAssertEqual(indexContent, "line1\nCHANGED2\nline3\nline4\nline5\n")

        // --- Apply reverse (unstage) using the same patch ---
        _ = try await GitClient.runGit(
            ["apply", "--cached", "--reverse", "--whitespace=nowarn"], cwd: repoURL, stdin: Data(patch.utf8)
        )

        let stagedAfterUnstage = try await GitClient.runGit(["diff", "--cached", "--no-color", "--", "f.txt"], cwd: repoURL)
        XCTAssertTrue(stagedAfterUnstage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let unstagedAfterUnstage = try await GitClient.runGit(["diff", "--no-color", "--", "f.txt"], cwd: repoURL)
        XCTAssertTrue(unstagedAfterUnstage.contains("-line2"))
        XCTAssertTrue(unstagedAfterUnstage.contains("+CHANGED2"))
        XCTAssertTrue(unstagedAfterUnstage.contains("+NEW5"))
    }
}
