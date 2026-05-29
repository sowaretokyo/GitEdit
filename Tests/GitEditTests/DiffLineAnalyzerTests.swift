import XCTest
@testable import GitEdit

final class DiffLineAnalyzerTests: XCTestCase {
    func testUntrackedCountsAllLinesAsAdded() {
        let content = "a\nb\nc"
        let result = DiffLineAnalyzer.addedLines(
            from: "", isUntracked: true, content: content
        )
        XCTAssertEqual(result, [1, 2, 3])
    }

    func testUntrackedEmptyContentIsLine1() {
        let result = DiffLineAnalyzer.addedLines(
            from: "", isUntracked: true, content: ""
        )
        XCTAssertEqual(result, [1])
    }

    func testNoDiffYieldsEmptySet() {
        XCTAssertTrue(
            DiffLineAnalyzer.addedLines(from: "", isUntracked: false, content: "").isEmpty
        )
    }

    func testSingleHunkSingleAddition() {
        let diff = """
        @@ -1,3 +1,4 @@
         line1
        +new line
         line2
         line3
        """
        let result = DiffLineAnalyzer.addedLines(
            from: diff, isUntracked: false, content: ""
        )
        XCTAssertEqual(result, [2])
    }

    func testMultipleAdditions() {
        let diff = """
        @@ -1,2 +1,4 @@
         a
        +b
        +c
         d
        """
        let result = DiffLineAnalyzer.addedLines(
            from: diff, isUntracked: false, content: ""
        )
        XCTAssertEqual(result, [2, 3])
    }

    func testRemovalsDoNotCount() {
        let diff = """
        @@ -1,3 +1,2 @@
         a
        -b
         c
        """
        let result = DiffLineAnalyzer.addedLines(
            from: diff, isUntracked: false, content: ""
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testRemovedThenAddedAtSameLocation() {
        let diff = """
        @@ -1,2 +1,2 @@
         keep
        -old
        +new
        """
        let result = DiffLineAnalyzer.addedLines(
            from: diff, isUntracked: false, content: ""
        )
        XCTAssertEqual(result, [2])
    }

    func testMultipleHunks() {
        let diff = """
        @@ -1,2 +1,2 @@
         a
        +X
        @@ -10,2 +11,3 @@
         b
        +Y
         c
        """
        let result = DiffLineAnalyzer.addedLines(
            from: diff, isUntracked: false, content: ""
        )
        XCTAssertEqual(result, [2, 12])
    }

    func testNoNewlineMarkerIsSkipped() {
        let diff = """
        @@ -1,1 +1,1 @@
        -old
        +new
        \\ No newline at end of file
        """
        let result = DiffLineAnalyzer.addedLines(
            from: diff, isUntracked: false, content: ""
        )
        XCTAssertEqual(result, [1])
    }
}
