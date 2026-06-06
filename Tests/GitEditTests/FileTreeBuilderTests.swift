import XCTest
@testable import GitEdit

final class FileTreeBuilderTests: XCTestCase {
    private let repoURL = URL(fileURLWithPath: "/repo")

    func testEmptyInputProducesEmptyTree() {
        let result = FileTreeBuilder.build(from: [], repositoryURL: repoURL)
        XCTAssertTrue(result.isEmpty)
    }

    func testFlatFiles() {
        let result = FileTreeBuilder.build(
            from: ["a.swift", "b.swift", "c.swift"],
            repositoryURL: repoURL
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.name), ["a.swift", "b.swift", "c.swift"])
        XCTAssertTrue(result.allSatisfy { !$0.isDirectory })
    }

    func testNestedPathBuildsDirectory() {
        let result = FileTreeBuilder.build(
            from: ["src/a.swift", "src/b.swift", "README.md"],
            repositoryURL: repoURL
        )
        // Directories before files at the same level.
        XCTAssertEqual(result.map(\.name), ["src", "README.md"])
        let src = result[0]
        XCTAssertTrue(src.isDirectory)
        XCTAssertEqual(src.children?.map(\.name), ["a.swift", "b.swift"])
        XCTAssertFalse(result[1].isDirectory)
    }

    func testDirectoriesSortedBeforeFiles() {
        let result = FileTreeBuilder.build(
            from: ["z/inner.txt", "a.txt"],
            repositoryURL: repoURL
        )
        // "z" directory should come before "a.txt" file even though "a" < "z".
        XCTAssertEqual(result.map(\.name), ["z", "a.txt"])
    }

    func testCaseInsensitiveAlphabeticalOrder() {
        let result = FileTreeBuilder.build(
            from: ["b.txt", "A.txt", "c.txt"],
            repositoryURL: repoURL
        )
        XCTAssertEqual(result.map(\.name), ["A.txt", "b.txt", "c.txt"])
    }

    func testDeepNesting() {
        let result = FileTreeBuilder.build(
            from: ["a/b/c/d.txt"],
            repositoryURL: repoURL
        )
        XCTAssertEqual(result.count, 1)
        let a = result[0]
        XCTAssertEqual(a.name, "a")
        XCTAssertTrue(a.isDirectory)
        let b = a.children?.first
        XCTAssertEqual(b?.name, "b")
        let c = b?.children?.first
        XCTAssertEqual(c?.name, "c")
        let d = c?.children?.first
        XCTAssertEqual(d?.name, "d.txt")
        XCTAssertEqual(d?.isDirectory, false)
    }

    func testWhitespaceOnlyPathSkipped() {
        let result = FileTreeBuilder.build(
            from: ["  ", "a.txt"],
            repositoryURL: repoURL
        )
        XCTAssertEqual(result.map(\.name), ["a.txt"])
    }

    func testPathsResolveAgainstRepositoryURL() {
        let result = FileTreeBuilder.build(
            from: ["src/foo.swift"],
            repositoryURL: repoURL
        )
        XCTAssertEqual(result[0].url, repoURL.appendingPathComponent("src"))
        XCTAssertEqual(
            result[0].children?.first?.url,
            repoURL.appendingPathComponent("src/foo.swift")
        )
    }
}
