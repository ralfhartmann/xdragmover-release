import XCTest
@testable import XDragMover

final class SemanticVersionTests: XCTestCase {

    func test_isNewer_higherPatch_isTrue() {
        XCTAssertTrue(SemanticVersion.isNewer("3.1.2", than: "3.1.1"))
    }

    func test_isNewer_higherMinor_isTrue() {
        XCTAssertTrue(SemanticVersion.isNewer("3.2.0", than: "3.1.9"))
    }

    func test_isNewer_higherMajor_isTrue() {
        XCTAssertTrue(SemanticVersion.isNewer("4.0.0", than: "3.9.9"))
    }

    func test_isNewer_equalVersions_isFalse() {
        XCTAssertFalse(SemanticVersion.isNewer("3.1.2", than: "3.1.2"))
    }

    func test_isNewer_olderVersion_isFalse() {
        XCTAssertFalse(SemanticVersion.isNewer("3.1.1", than: "3.1.2"))
    }

    func test_isNewer_comparesNumerically_notLexicographically() {
        XCTAssertTrue(SemanticVersion.isNewer("3.1.10", than: "3.1.9"), "10 > 9 numerically, even though \"10\" < \"9\" as strings")
    }

    func test_isNewer_leadingVPrefix_isStripped() {
        XCTAssertTrue(SemanticVersion.isNewer("v3.1.2", than: "3.1.1"))
        XCTAssertTrue(SemanticVersion.isNewer("3.1.2", than: "v3.1.1"))
        XCTAssertFalse(SemanticVersion.isNewer("v3.1.1", than: "3.1.1"))
    }

    func test_isNewer_missingTrailingComponent_defaultsToZero() {
        XCTAssertFalse(SemanticVersion.isNewer("3.1", than: "3.1.0"))
        XCTAssertTrue(SemanticVersion.isNewer("3.1.1", than: "3.1"))
    }
}

final class GitHubReleaseUpdateCheckerTests: XCTestCase {

    func test_parseTagName_extractsTagFromRealisticResponse() throws {
        let json = """
        {
            "tag_name": "v3.1.2",
            "name": "XDragMover v3.1.2",
            "html_url": "https://github.com/ralfhartmann/xdragmover-release/releases/tag/v3.1.2"
        }
        """
        let data = Data(json.utf8)

        let tagName = try GitHubReleaseUpdateChecker.parseTagName(from: data)

        XCTAssertEqual(tagName, "v3.1.2")
    }

    func test_parseTagName_malformedJSON_throws() {
        let data = Data("not json".utf8)

        XCTAssertThrowsError(try GitHubReleaseUpdateChecker.parseTagName(from: data))
    }

    func test_parseTagName_missingTagName_throws() {
        let data = Data("{\"name\": \"XDragMover v3.1.2\"}".utf8)

        XCTAssertThrowsError(try GitHubReleaseUpdateChecker.parseTagName(from: data))
    }
}
