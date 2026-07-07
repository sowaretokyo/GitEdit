import XCTest
@testable import GitEdit

final class ImageDiffTests: XCTestCase {

    func testKnownExtensionsAreRecognizedAsImages() {
        for ext in ImageDiff.imageExtensions {
            XCTAssertTrue(ImageDiff.isImagePath("assets/icon.\(ext)"), "expected \(ext) to be recognized")
            XCTAssertTrue(ImageDiff.isImagePath("assets/icon.\(ext.uppercased())"), "expected uppercased \(ext) to be recognized")
        }
    }

    func testNonImageExtensionsAreRejected() {
        XCTAssertFalse(ImageDiff.isImagePath("Sources/GitEdit/App.swift"))
        XCTAssertFalse(ImageDiff.isImagePath("README.txt"))
        XCTAssertFalse(ImageDiff.isImagePath("Makefile"))
        XCTAssertFalse(ImageDiff.isImagePath("a/pngdir/x"))
    }

    func testMixedCaseExtensionOnNestedPathIsRecognized() {
        XCTAssertTrue(ImageDiff.isImagePath("a/b/c.PNG"))
    }
}
