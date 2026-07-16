import XCTest
@testable import XDragMover

@MainActor
final class DebugLoggerTests: XCTestCase {

    func test_startsEmpty() {
        let logger = DebugLogger()
        XCTAssertTrue(logger.entries.isEmpty)
    }

    func test_log_appendsEntryWithMessage() {
        let logger = DebugLogger()
        logger.log("hello")
        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries.first?.message, "hello")
    }

    func test_log_preservesInsertionOrder() {
        let logger = DebugLogger()
        logger.log("first")
        logger.log("second")
        logger.log("third")
        XCTAssertEqual(logger.entries.map(\.message), ["first", "second", "third"])
    }

    func test_log_trimsOldestEntriesBeyondMaxEntries() {
        let logger = DebugLogger(maxEntries: 3)
        logger.log("1")
        logger.log("2")
        logger.log("3")
        logger.log("4")
        XCTAssertEqual(logger.entries.map(\.message), ["2", "3", "4"])
    }

    func test_clear_removesAllEntries() {
        let logger = DebugLogger()
        logger.log("hello")
        logger.clear()
        XCTAssertTrue(logger.entries.isEmpty)
    }

    func test_formattedEntry_containsMessage() {
        let logger = DebugLogger()
        logger.log("Window under mouse: Finder (#1)")
        let formatted = logger.entries.first?.formatted ?? ""
        XCTAssertTrue(formatted.contains("Window under mouse: Finder (#1)"))
    }
}
