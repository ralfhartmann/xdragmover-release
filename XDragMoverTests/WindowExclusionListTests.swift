import XCTest
@testable import XDragMover

final class WindowExclusionListTests: XCTestCase {

    func test_isExcluded_noPatterns_isFalse() {
        let list = WindowExclusionList(patterns: [])
        XCTAssertFalse(list.isExcluded(ownerName: "Finder"))
    }

    func test_isExcluded_matchingPattern_isTrue() {
        let list = WindowExclusionList(patterns: ["^Finder$"])
        XCTAssertTrue(list.isExcluded(ownerName: "Finder"))
    }

    func test_isExcluded_nonMatchingPattern_isFalse() {
        let list = WindowExclusionList(patterns: ["^Finder$"])
        XCTAssertFalse(list.isExcluded(ownerName: "Calculator"))
    }

    func test_isExcluded_substringPattern_matchesAnywhere() {
        let list = WindowExclusionList(patterns: ["Chrome"])
        XCTAssertTrue(list.isExcluded(ownerName: "Google Chrome"))
    }

    func test_isExcluded_anyPatternMatching_isTrue() {
        let list = WindowExclusionList(patterns: ["^Finder$", "^Calculator$"])
        XCTAssertTrue(list.isExcluded(ownerName: "Calculator"))
    }

    func test_isExcluded_invalidPatternAmongValidOnes_isSkippedNotThrown() {
        let list = WindowExclusionList(patterns: ["(unbalanced", "^Finder$"])
        XCTAssertTrue(list.isExcluded(ownerName: "Finder"))
        XCTAssertFalse(list.isExcluded(ownerName: "Calculator"))
    }

    func test_isExcluded_onlyInvalidPattern_neverExcludes() {
        let list = WindowExclusionList(patterns: ["(unbalanced"])
        XCTAssertFalse(list.isExcluded(ownerName: "Finder"))
    }

    func test_exactPattern_escapesRegexMetacharacters() {
        let pattern = WindowExclusionList.exactPattern(forOwnerName: "Finder (Preview)")
        let list = WindowExclusionList(patterns: [pattern])
        XCTAssertTrue(list.isExcluded(ownerName: "Finder (Preview)"))
    }

    func test_exactPattern_doesNotMatchDifferentName() {
        let pattern = WindowExclusionList.exactPattern(forOwnerName: "Finder")
        let list = WindowExclusionList(patterns: [pattern])
        XCTAssertFalse(list.isExcluded(ownerName: "Finder Helper"))
    }

    func test_exactPattern_doesNotMatchSubstringOfLongerName() {
        let pattern = WindowExclusionList.exactPattern(forOwnerName: "Chrome")
        let list = WindowExclusionList(patterns: [pattern])
        XCTAssertFalse(list.isExcluded(ownerName: "Google Chrome"))
    }
}
