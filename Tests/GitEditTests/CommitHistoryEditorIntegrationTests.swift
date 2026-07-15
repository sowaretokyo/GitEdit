import XCTest
@testable import GitEdit

/// Integration smoke tests that run `CommitHistoryEditor.Runner` against a
/// real, disposable git repository (created fresh per test in
/// `FileManager.temporaryDirectory`, removed in `tearDown`).
final class CommitHistoryEditorIntegrationTests: XCTestCase {
    private var repoURL: URL!
    private var git: GitClient!

    override func setUp() async throws {
        try await super.setUp()
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommitHistoryEditorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        git = GitClient(repository: repoURL)
        try await git.run("init", "-q", "-b", "main")
        try await git.run("config", "user.name", "Test")
        try await git.run("config", "user.email", "test@example.com")
    }

    override func tearDown() async throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        repoURL = nil
        git = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeCommit(_ fileName: String, content: String, message: String) async throws -> String {
        try content.write(to: repoURL.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        try await git.run("add", "-A")
        try await git.run("commit", "-q", "-m", message)
        return try await git.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shasNewestFirst() async throws -> [String] {
        try await git.recentCommits(limit: 200).map(\.id)
    }

    private func subjectsNewestFirst() async throws -> [String] {
        try await git.recentCommits(limit: 200).map(\.summary)
    }

    private func refExists(_ ref: String) async -> Bool {
        (try? await git.run("rev-parse", "--verify", "--quiet", ref)) != nil
    }

    private func headSHA() async throws -> String {
        try await git.run("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Reword

    func testRewordNonHeadCommitRewritesOnlyThatMessage() async throws {
        try await makeCommit("a.txt", content: "a", message: "commit A")
        try await makeCommit("b.txt", content: "b", message: "commit B")
        try await makeCommit("c.txt", content: "c", message: "commit C")

        let shas = try await shasNewestFirst() // [C, B, A] — shas[0] is the pre-edit HEAD (C).
        let runner = CommitHistoryEditor.Runner(git: git)
        let result = try await runner.performEdit(
            commitsNewestFirst: shas, targetIndex: 1, operation: .reword,
            message: "commit B renamed", isFullHistoryLoaded: true
        )

        let subjects = try await subjectsNewestFirst()
        XCTAssertEqual(subjects, ["commit C", "commit B renamed", "commit A"])
        XCTAssertEqual(result.backupSHA, shas[0])
        let backupSHA = try await git.run("rev-parse", CommitHistoryEditor.Runner.backupRef)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(backupSHA, shas[0])
    }

    func testRewordHeadTakesFastPathAndSkipsRebase() async throws {
        try await makeCommit("a.txt", content: "a", message: "commit A")
        try await makeCommit("b.txt", content: "b", message: "commit B")

        let shas = try await shasNewestFirst() // [B, A]
        let runner = CommitHistoryEditor.Runner(git: git)
        _ = try await runner.performEdit(
            commitsNewestFirst: shas, targetIndex: 0, operation: .reword,
            message: "commit B amended", isFullHistoryLoaded: true
        )

        let subjects = try await subjectsNewestFirst()
        let mergeHeadExists = await refExists("MERGE_HEAD")
        let rebaseInProgress = await git.isRebaseInProgress()
        XCTAssertEqual(subjects, ["commit B amended", "commit A"])
        XCTAssertFalse(mergeHeadExists)
        XCTAssertFalse(rebaseInProgress)
    }

    // MARK: - Squash

    func testSquashCombinesMessageAndReducesCommitCount() async throws {
        try await makeCommit("a.txt", content: "a", message: "commit A")
        try await makeCommit("b.txt", content: "b", message: "commit B")
        try await makeCommit("c.txt", content: "c", message: "commit C")

        let shas = try await shasNewestFirst() // [C, B, A]
        let runner = CommitHistoryEditor.Runner(git: git)
        _ = try await runner.performEdit(
            commitsNewestFirst: shas, targetIndex: 1, operation: .squashIntoPrevious,
            message: "commit A\n\ncommit B", isFullHistoryLoaded: true
        )

        let subjects = try await subjectsNewestFirst()
        XCTAssertEqual(subjects, ["commit C", "commit A"])
        // Both files from the combined commits should still be present.
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("a.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("b.txt").path))
    }

    // MARK: - Drop

    func testDropRemovesCommitAndItsFile() async throws {
        try await makeCommit("a.txt", content: "a", message: "commit A")
        try await makeCommit("b.txt", content: "b", message: "commit B")
        try await makeCommit("c.txt", content: "c", message: "commit C")

        let shas = try await shasNewestFirst() // [C, B, A]
        let runner = CommitHistoryEditor.Runner(git: git)
        _ = try await runner.performEdit(
            commitsNewestFirst: shas, targetIndex: 1, operation: .drop,
            message: nil, isFullHistoryLoaded: true
        )

        let subjects = try await subjectsNewestFirst()
        XCTAssertEqual(subjects, ["commit C", "commit A"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("b.txt").path))
    }

    // MARK: - Reorder

    func testMoveUpAndMoveDownProduceTheSameSwap() async throws {
        try await makeCommit("a.txt", content: "a", message: "commit A")
        try await makeCommit("b.txt", content: "b", message: "commit B")
        try await makeCommit("c.txt", content: "c", message: "commit C")

        let shas = try await shasNewestFirst() // [C, B, A]
        let runner = CommitHistoryEditor.Runner(git: git)
        _ = try await runner.performEdit(
            commitsNewestFirst: shas, targetIndex: 1, operation: .moveUp,
            message: nil, isFullHistoryLoaded: true
        )

        // Moving B up swaps it with C: newest-first order becomes [B, C, A].
        let subjects = try await subjectsNewestFirst()
        XCTAssertEqual(subjects, ["commit B", "commit C", "commit A"])
    }

    func testMoveDownSwapsWithOlderNeighbor() async throws {
        try await makeCommit("a.txt", content: "a", message: "commit A")
        try await makeCommit("b.txt", content: "b", message: "commit B")
        try await makeCommit("c.txt", content: "c", message: "commit C")

        let shas = try await shasNewestFirst() // [C, B, A]
        let runner = CommitHistoryEditor.Runner(git: git)
        _ = try await runner.performEdit(
            commitsNewestFirst: shas, targetIndex: 0, operation: .moveDown,
            message: nil, isFullHistoryLoaded: true
        )

        // Moving C down swaps it with B: newest-first order becomes [B, C, A].
        let subjects = try await subjectsNewestFirst()
        XCTAssertEqual(subjects, ["commit B", "commit C", "commit A"])
    }

    // MARK: - Root reword

    func testRewordAtRootRewritesTheFirstCommit() async throws {
        try await makeCommit("a.txt", content: "a", message: "commit A")
        try await makeCommit("b.txt", content: "b", message: "commit B")

        let shas = try await shasNewestFirst() // [B, A]
        let runner = CommitHistoryEditor.Runner(git: git)
        _ = try await runner.performEdit(
            commitsNewestFirst: shas, targetIndex: 1, operation: .reword,
            message: "commit A renamed", isFullHistoryLoaded: true
        )

        let subjects = try await subjectsNewestFirst()
        XCTAssertEqual(subjects, ["commit B", "commit A renamed"])
    }

    // MARK: - Undo via backup ref

    func testBackupRefAllowsResetHardToFullyRestorePriorState() async throws {
        try await makeCommit("a.txt", content: "a", message: "commit A")
        try await makeCommit("b.txt", content: "b", message: "commit B")
        try await makeCommit("c.txt", content: "c", message: "commit C")
        let originalSubjects = try await subjectsNewestFirst()

        let shas = try await shasNewestFirst()
        let runner = CommitHistoryEditor.Runner(git: git)
        let result = try await runner.performEdit(
            commitsNewestFirst: shas, targetIndex: 1, operation: .drop,
            message: nil, isFullHistoryLoaded: true
        )
        let afterEditSubjects = try await subjectsNewestFirst()
        XCTAssertNotEqual(afterEditSubjects, originalSubjects)

        try await git.run("reset", "--hard", result.backupSHA)

        let restoredSubjects = try await subjectsNewestFirst()
        XCTAssertEqual(restoredSubjects, originalSubjects)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("b.txt").path))
    }

    // MARK: - Conflict handling

    func testConflictingDropAbortsAndFullyRestoresState() async throws {
        try await makeCommit("f.txt", content: "line1\n", message: "base")
        try await makeCommit("f.txt", content: "line2\n", message: "change to line2")
        try await makeCommit("f.txt", content: "line3\n", message: "change to line3")
        let originalSubjects = try await subjectsNewestFirst()
        let originalHead = try await headSHA()

        // Dropping "change to line2" leaves "change to line3"'s patch (which
        // expects to remove "line2") unable to apply against "line1".
        let shas = try await shasNewestFirst() // [line3, line2, base]
        let runner = CommitHistoryEditor.Runner(git: git)

        do {
            _ = try await runner.performEdit(
                commitsNewestFirst: shas, targetIndex: 1, operation: .drop,
                message: nil, isFullHistoryLoaded: true
            )
            XCTFail("expected a conflict")
        } catch CommitHistoryEditor.ExecutionError.conflict {
            // expected
        }

        let rebaseInProgress = await git.isRebaseInProgress()
        let backupRefExists = await refExists(CommitHistoryEditor.Runner.backupRef)
        let subjectsAfter = try await subjectsNewestFirst()
        let headAfter = try await headSHA()
        XCTAssertFalse(rebaseInProgress)
        XCTAssertFalse(backupRefExists)
        XCTAssertEqual(subjectsAfter, originalSubjects)
        XCTAssertEqual(headAfter, originalHead)
    }

    // MARK: - Pre-execution validation

    func testDirtyWorkingTreeIsRejectedBeforeAnyGitStateChanges() async throws {
        try await makeCommit("a.txt", content: "a", message: "commit A")
        try await makeCommit("b.txt", content: "b", message: "commit B")
        try "dirty".write(to: repoURL.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let shas = try await shasNewestFirst()
        let runner = CommitHistoryEditor.Runner(git: git)

        do {
            _ = try await runner.performEdit(
                commitsNewestFirst: shas, targetIndex: 0, operation: .reword,
                message: "renamed", isFullHistoryLoaded: true
            )
            XCTFail("expected dirtyWorkingTree")
        } catch CommitHistoryEditor.ExecutionError.dirtyWorkingTree {
            // expected
        }

        let backupRefExists = await refExists(CommitHistoryEditor.Runner.backupRef)
        let subjects = try await subjectsNewestFirst()
        XCTAssertFalse(backupRefExists)
        XCTAssertEqual(subjects, ["commit B", "commit A"])
    }

    func testPushedCommitInRangeIsRejected() async throws {
        let bareURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommitHistoryEditorTests-bare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: bareURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bareURL) }
        try await GitClient.runGit(["init", "--bare", "-q"], cwd: bareURL)

        try await makeCommit("a.txt", content: "a", message: "commit A")
        try await git.run("remote", "add", "origin", bareURL.path)
        try await git.run("push", "-u", "origin", "main")
        try await makeCommit("b.txt", content: "b", message: "commit B") // unpushed

        // Reword commit A: its range (index 0...1) includes the pushed commit A.
        let shas = try await shasNewestFirst() // [B, A]
        let runner = CommitHistoryEditor.Runner(git: git)

        do {
            _ = try await runner.performEdit(
                commitsNewestFirst: shas, targetIndex: 1, operation: .reword,
                message: "renamed", isFullHistoryLoaded: true
            )
            XCTFail("expected pushedCommitInRange")
        } catch CommitHistoryEditor.ExecutionError.pushedCommitInRange {
            // expected
        }

        let backupRefExists = await refExists(CommitHistoryEditor.Runner.backupRef)
        XCTAssertFalse(backupRefExists)
    }

    func testMergeCommitInRangeIsRejected() async throws {
        try await makeCommit("base.txt", content: "base", message: "base commit")
        try await git.run("checkout", "-b", "feature")
        try await makeCommit("feature.txt", content: "feature", message: "feature commit")
        try await git.run("checkout", "main")
        try await makeCommit("main2.txt", content: "main2", message: "main commit 2")
        try await git.run("-c", "core.editor=true", "merge", "--no-ff", "-m", "Merge branch 'feature'", "feature")

        let commits = try await git.recentCommits(limit: 200)
        XCTAssertTrue(commits.contains { $0.isMerge })
        let shas = commits.map(\.id)
        let oldestIndex = shas.count - 1 // "base commit" — its range crosses the merge above it.

        let runner = CommitHistoryEditor.Runner(git: git)
        do {
            _ = try await runner.performEdit(
                commitsNewestFirst: shas, targetIndex: oldestIndex, operation: .reword,
                message: "renamed", isFullHistoryLoaded: true
            )
            XCTFail("expected mergeCommitInRange")
        } catch CommitHistoryEditor.ExecutionError.mergeCommitInRange {
            // expected
        }
    }
}
