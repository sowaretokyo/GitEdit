import XCTest
@testable import GitEdit

@MainActor
final class ChangesViewModelTests: XCTestCase {
    func testPreserveDisplayOrderKeepsExistingRowsInPreviousOrder() {
        let latest = [
            makeChange(path: "b.swift", index: "M", working: " "),
            makeChange(path: "a.swift", index: " ", working: "M"),
            makeChange(path: "c.swift", index: "?", working: "?")
        ]

        let result = ChangesViewModel.preserveDisplayOrder(
            latest,
            previousOrder: ["a.swift", "b.swift", "c.swift"]
        )

        XCTAssertEqual(result.map(\.path), ["a.swift", "b.swift", "c.swift"])
        XCTAssertTrue(result[1].willBeCommitted)
    }

    func testPreserveDisplayOrderAppendsNewRowsInLatestOrder() {
        let latest = [
            makeChange(path: "new-a.swift", index: " ", working: "M"),
            makeChange(path: "existing.swift", index: "M", working: " "),
            makeChange(path: "new-b.swift", index: "?", working: "?")
        ]

        let result = ChangesViewModel.preserveDisplayOrder(
            latest,
            previousOrder: ["existing.swift"]
        )

        XCTAssertEqual(result.map(\.path), ["existing.swift", "new-a.swift", "new-b.swift"])
    }

    func testPreserveDisplayOrderDropsRowsNoLongerInStatus() {
        let latest = [
            makeChange(path: "still-here.swift", index: " ", working: "M")
        ]

        let result = ChangesViewModel.preserveDisplayOrder(
            latest,
            previousOrder: ["removed.swift", "still-here.swift"]
        )

        XCTAssertEqual(result.map(\.path), ["still-here.swift"])
    }

    private func makeChange(
        path: String,
        index: Character,
        working: Character
    ) -> FileChange {
        FileChange(path: path, indexStatus: index, workingStatus: working, renameFrom: nil)
    }
}
