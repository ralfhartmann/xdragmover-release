import XCTest
import CoreGraphics
@testable import XDragMover

@MainActor
final class MouseWindowWatcherTests: XCTestCase {

    private func makeWindow(number: Int, owner: String, title: String? = nil) -> WindowInfo {
        WindowInfo(
            windowNumber: number,
            ownerName: owner,
            title: title,
            bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            layer: 0
        )
    }

    func test_report_logsOnFirstCall_evenWhenWindowIsNil() {
        let logger = DebugLogger()
        let watcher = MouseWindowWatcher(logger: logger)

        watcher.report(nil)

        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries.first?.message, "Window under mouse: none")
    }

    func test_report_logsWindowDescription() {
        let logger = DebugLogger()
        let watcher = MouseWindowWatcher(logger: logger)
        let window = makeWindow(number: 7, owner: "Finder", title: "Downloads")

        watcher.report(window)

        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries.first?.message, "Window under mouse: \(window.debugDescription)")
    }

    func test_report_doesNotLogAgain_forSameWindow() {
        let logger = DebugLogger()
        let watcher = MouseWindowWatcher(logger: logger)
        let window = makeWindow(number: 7, owner: "Finder")

        watcher.report(window)
        watcher.report(window)
        watcher.report(window)

        XCTAssertEqual(logger.entries.count, 1)
    }

    func test_report_logsAgain_whenWindowChanges() {
        let logger = DebugLogger()
        let watcher = MouseWindowWatcher(logger: logger)
        let first = makeWindow(number: 1, owner: "Finder")
        let second = makeWindow(number: 2, owner: "Safari")

        watcher.report(first)
        watcher.report(second)

        XCTAssertEqual(logger.entries.count, 2)
    }

    func test_report_logsAgain_whenMovingFromWindowToNone() {
        let logger = DebugLogger()
        let watcher = MouseWindowWatcher(logger: logger)
        let window = makeWindow(number: 1, owner: "Finder")

        watcher.report(window)
        watcher.report(nil)

        XCTAssertEqual(logger.entries.count, 2)
        XCTAssertEqual(logger.entries.last?.message, "Window under mouse: none")
    }

    func test_report_doesNotLogAgain_whenStayingAtNone() {
        let logger = DebugLogger()
        let watcher = MouseWindowWatcher(logger: logger)

        watcher.report(nil)
        watcher.report(nil)

        XCTAssertEqual(logger.entries.count, 1)
    }
}
