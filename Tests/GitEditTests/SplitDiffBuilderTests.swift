import XCTest
@testable import GitEdit

final class SplitDiffBuilderTests: XCTestCase {

    func testEmptyInputYieldsNoRows() {
        XCTAssertTrue(SplitDiffBuilder.rows(from: []).isEmpty)
    }

    func testContextOnlyPairsSameContentBothSides() {
        let lines: [DiffLine] = [
            .context(content: "a", oldLine: 1, newLine: 1),
            .context(content: "b", oldLine: 2, newLine: 2)
        ]
        let rows = SplitDiffBuilder.rows(from: lines)
        XCTAssertEqual(rows, [
            .pair(
                left: SplitCell(number: 1, text: "a", kind: .context),
                right: SplitCell(number: 1, text: "a", kind: .context)
            ),
            .pair(
                left: SplitCell(number: 2, text: "b", kind: .context),
                right: SplitCell(number: 2, text: "b", kind: .context)
            )
        ])
    }

    func testAddedOnlyLeavesLeftEmpty() {
        let lines: [DiffLine] = [
            .added(content: "new1", newLine: 1),
            .added(content: "new2", newLine: 2)
        ]
        let rows = SplitDiffBuilder.rows(from: lines)
        XCTAssertEqual(rows, [
            .pair(left: nil, right: SplitCell(number: 1, text: "new1", kind: .added)),
            .pair(left: nil, right: SplitCell(number: 2, text: "new2", kind: .added))
        ])
    }

    func testRemovedOnlyLeavesRightEmpty() {
        let lines: [DiffLine] = [
            .removed(content: "old1", oldLine: 1),
            .removed(content: "old2", oldLine: 2)
        ]
        let rows = SplitDiffBuilder.rows(from: lines)
        XCTAssertEqual(rows, [
            .pair(left: SplitCell(number: 1, text: "old1", kind: .removed), right: nil),
            .pair(left: SplitCell(number: 2, text: "old2", kind: .removed), right: nil)
        ])
    }

    func testMoreRemovedThanAddedZipsWithTrailingNilOnRight() {
        let lines: [DiffLine] = [
            .removed(content: "r1", oldLine: 1),
            .removed(content: "r2", oldLine: 2),
            .removed(content: "r3", oldLine: 3),
            .added(content: "a1", newLine: 1)
        ]
        let rows = SplitDiffBuilder.rows(from: lines)
        XCTAssertEqual(rows, [
            .pair(left: SplitCell(number: 1, text: "r1", kind: .removed), right: SplitCell(number: 1, text: "a1", kind: .added)),
            .pair(left: SplitCell(number: 2, text: "r2", kind: .removed), right: nil),
            .pair(left: SplitCell(number: 3, text: "r3", kind: .removed), right: nil)
        ])
    }

    func testMoreAddedThanRemovedZipsWithTrailingNilOnLeft() {
        let lines: [DiffLine] = [
            .removed(content: "r1", oldLine: 1),
            .added(content: "a1", newLine: 1),
            .added(content: "a2", newLine: 2),
            .added(content: "a3", newLine: 3)
        ]
        let rows = SplitDiffBuilder.rows(from: lines)
        XCTAssertEqual(rows, [
            .pair(left: SplitCell(number: 1, text: "r1", kind: .removed), right: SplitCell(number: 1, text: "a1", kind: .added)),
            .pair(left: nil, right: SplitCell(number: 2, text: "a2", kind: .added)),
            .pair(left: nil, right: SplitCell(number: 3, text: "a3", kind: .added))
        ])
    }

    func testContextBetweenChangesFlushesInOrder() {
        let lines: [DiffLine] = [
            .removed(content: "old", oldLine: 1),
            .added(content: "new", newLine: 1),
            .context(content: "keep", oldLine: 2, newLine: 2),
            .removed(content: "old2", oldLine: 3),
            .added(content: "new2", newLine: 3)
        ]
        let rows = SplitDiffBuilder.rows(from: lines)
        XCTAssertEqual(rows, [
            .pair(left: SplitCell(number: 1, text: "old", kind: .removed), right: SplitCell(number: 1, text: "new", kind: .added)),
            .pair(
                left: SplitCell(number: 2, text: "keep", kind: .context),
                right: SplitCell(number: 2, text: "keep", kind: .context)
            ),
            .pair(left: SplitCell(number: 3, text: "old2", kind: .removed), right: SplitCell(number: 3, text: "new2", kind: .added))
        ])
    }

    func testFileHeaderFlushesPendingBufferBeforeEmittingFullWidthRow() {
        let lines: [DiffLine] = [
            .removed(content: "old", oldLine: 1),
            .added(content: "new", newLine: 1),
            .fileHeader("diff --git a/y b/y")
        ]
        let rows = SplitDiffBuilder.rows(from: lines)
        XCTAssertEqual(rows, [
            .pair(left: SplitCell(number: 1, text: "old", kind: .removed), right: SplitCell(number: 1, text: "new", kind: .added)),
            .fileHeader("diff --git a/y b/y")
        ])
    }

    func testHunkHeaderFlushesPendingBufferBeforeEmittingFullWidthRow() {
        let lines: [DiffLine] = [
            .removed(content: "old", oldLine: 1),
            .hunkHeader("@@ -1,1 +1,0 @@")
        ]
        let rows = SplitDiffBuilder.rows(from: lines)
        XCTAssertEqual(rows, [
            .pair(left: SplitCell(number: 1, text: "old", kind: .removed), right: nil),
            .hunkHeader("@@ -1,1 +1,0 @@")
        ])
    }

    func testLineNumbersRemainContinuousAcrossPairs() {
        let lines: [DiffLine] = [
            .context(content: "a", oldLine: 1, newLine: 1),
            .removed(content: "b", oldLine: 2),
            .removed(content: "c", oldLine: 3),
            .added(content: "d", newLine: 2),
            .context(content: "e", oldLine: 4, newLine: 3)
        ]
        let rows = SplitDiffBuilder.rows(from: lines)
        XCTAssertEqual(rows, [
            .pair(
                left: SplitCell(number: 1, text: "a", kind: .context),
                right: SplitCell(number: 1, text: "a", kind: .context)
            ),
            .pair(left: SplitCell(number: 2, text: "b", kind: .removed), right: SplitCell(number: 2, text: "d", kind: .added)),
            .pair(left: SplitCell(number: 3, text: "c", kind: .removed), right: nil),
            .pair(
                left: SplitCell(number: 4, text: "e", kind: .context),
                right: SplitCell(number: 3, text: "e", kind: .context)
            )
        ])
    }
}
