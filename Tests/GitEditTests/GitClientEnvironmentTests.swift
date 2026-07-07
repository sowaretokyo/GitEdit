import XCTest
@testable import GitEdit

final class GitClientEnvironmentTests: XCTestCase {

    func testGitEnvironmentAddsCommonDeveloperToolPaths() {
        let env = GitClient.gitEnvironment(base: [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": "/Users/alice"
        ])

        let path = pathComponents(env["PATH"])
        XCTAssertEqual(path.prefix(6), [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/local/bin",
            "/opt/local/sbin"
        ])
        XCTAssertTrue(path.contains("/Users/alice/.volta/bin"))
        XCTAssertTrue(path.contains("/Users/alice/Library/pnpm"))
        XCTAssertTrue(path.contains("/Users/alice/.asdf/shims"))
        XCTAssertTrue(path.contains("/Users/alice/.nodenv/shims"))
        XCTAssertTrue(path.contains("/usr/bin"))
        XCTAssertEqual(env["LC_ALL"], "C.UTF-8")
        XCTAssertEqual(env["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertEqual(env["GIT_OPTIONAL_LOCKS"], "0")
    }

    func testNormalizedPATHFallsBackWhenPATHIsMissing() {
        let path = pathComponents(GitClient.normalizedPATH(current: nil, home: nil))

        XCTAssertTrue(path.contains("/usr/bin"))
        XCTAssertTrue(path.contains("/bin"))
        XCTAssertTrue(path.contains("/usr/sbin"))
        XCTAssertTrue(path.contains("/sbin"))
    }

    func testNormalizedPATHDeduplicatesExistingEntries() {
        let path = pathComponents(GitClient.normalizedPATH(
            current: "/opt/homebrew/bin:/custom/bin:/usr/local/bin:/custom/bin",
            home: "/Users/alice"
        ))

        XCTAssertEqual(path.filter { $0 == "/opt/homebrew/bin" }.count, 1)
        XCTAssertEqual(path.filter { $0 == "/usr/local/bin" }.count, 1)
        XCTAssertEqual(path.filter { $0 == "/custom/bin" }.count, 1)
    }

    private func pathComponents(_ path: String?) -> [String] {
        path?.split(separator: ":").map(String.init) ?? []
    }
}
