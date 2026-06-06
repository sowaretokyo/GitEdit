import XCTest
@testable import GitEdit

final class DiffParserTests: XCTestCase {

    func testEmptyInputYieldsNoLines() {
        XCTAssertTrue(DiffParser.parse("").isEmpty)
    }

    func testHunkHeaderIsEmitted() {
        let diff = "@@ -1,2 +1,2 @@\n a\n b\n"
        let lines = DiffParser.parse(diff)
        guard case .hunkHeader = lines.first else {
            return XCTFail("Expected first line to be a hunk header, got \(String(describing: lines.first))")
        }
    }

    func testAddedRemovedContextClassification() {
        let diff = """
        @@ -1,2 +1,2 @@
         keep
        -old
        +new
        """
        var sawKept = false
        var sawRemoved = false
        var sawAdded = false
        for line in DiffParser.parse(diff) {
            switch line {
            case .context(let s, _, _) where s == "keep": sawKept = true
            case .removed(let s, _) where s == "old":     sawRemoved = true
            case .added(let s, _) where s == "new":       sawAdded = true
            default: break
            }
        }
        XCTAssertTrue(sawKept, "context line missing")
        XCTAssertTrue(sawRemoved, "removed line missing")
        XCTAssertTrue(sawAdded, "added line missing")
    }

    func testHunkHeaderResetsNewLineCounter() {
        let diff = """
        @@ -10,2 +10,3 @@
         a
        +b
         c
        """
        var addedLineNo: Int?
        for line in DiffParser.parse(diff) {
            if case .added(_, let n) = line { addedLineNo = n }
        }
        XCTAssertEqual(addedLineNo, 11)
    }

    func testFileHeaderResetsHunkState() {
        let diff = """
        diff --git a/x b/x
        @@ -1,1 +1,1 @@
        +X
        diff --git a/y b/y
        @@ -1,1 +1,1 @@
        +Y
        """
        let lines = DiffParser.parse(diff)
        // Both additions should be at newLine 1 since each file resets the counter.
        let addedLineNumbers = lines.compactMap { line -> Int? in
            if case .added(_, let n) = line { return n }
            return nil
        }
        XCTAssertEqual(addedLineNumbers, [1, 1])
    }

    func testNoNewlineMarkerIsSkipped() {
        let diff = """
        @@ -1,1 +1,1 @@
        -old
        +new
        \\ No newline at end of file
        """
        let hasMarker = DiffParser.parse(diff).contains { line in
            if case .context(let s, _, _) = line, s.contains("No newline") { return true }
            return false
        }
        XCTAssertFalse(hasMarker)
    }
}
