import XCTest
import CoreGraphics
@testable import XDragMover

/// A fake `AXWindowHandling` that records every `focus()` call instead of
/// touching any real window. Kept private to this file, mirroring the
/// equivalent fakes in `WindowMoveControllerTests`/`WindowResizeControllerTests`.
private final class FakeAXWindow: AXWindowHandling {
    var position: CGPoint?
    var size: CGSize?
    var ownerName: String?
    private(set) var focusCallCount = 0

    func setPosition(_ point: CGPoint) {}
    func setSize(_ size: CGSize) {}
    func raise() {}

    func focus() {
        focusCallCount += 1
    }
}

private final class FakeAXWindowLocator: AXWindowLocating {
    var windowToReturn: AXWindowHandling?
    private(set) var queriedPoints: [CGPoint] = []

    func window(at point: CGPoint) -> AXWindowHandling? {
        queriedPoints.append(point)
        return windowToReturn
    }
}

/// Returns each snapshot in `snapshots` in order, one per call, then keeps
/// returning the last one — lets tests simulate "the on-screen window list
/// changed between one poll and the next" (e.g. a window raised itself).
private final class FakeWindowListProviding: WindowListProviding {
    private let snapshots: [[WindowInfo]]
    private var callIndex = 0

    init(snapshots: [[WindowInfo]]) {
        self.snapshots = snapshots
    }

    func currentWindows() -> [WindowInfo] {
        defer { callIndex = min(callIndex + 1, snapshots.count - 1) }
        return snapshots[callIndex]
    }
}

private final class FakeWindowOrderRestoring: WindowOrderRestoring {
    private(set) var raisedWindowIDs: [CGWindowID] = []
    func raiseWithoutActivating(windowID: CGWindowID) {
        raisedWindowIDs.append(windowID)
    }
}

private func makeWindowInfo(number: Int, bounds: CGRect, layer: Int = 0, ownerName: String = "SomeApp") -> WindowInfo {
    WindowInfo(windowNumber: number, ownerName: ownerName, title: nil, bounds: bounds, layer: layer)
}

@MainActor
final class FocusFollowsMouseControllerTests: XCTestCase {

    private let dwellDelay: TimeInterval = 0.3
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    func test_checkDwell_withoutAnyMovement_doesNothing() {
        let locator = FakeAXWindowLocator()
        let controller = FocusFollowsMouseController(locator: locator, logger: DebugLogger(), dwellDelay: dwellDelay)

        controller.checkDwell(now: epoch)

        XCTAssertTrue(locator.queriedPoints.isEmpty)
    }

    func test_checkDwell_beforeDwellDelayElapsed_doesNotFocus() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow()
        locator.windowToReturn = window
        let controller = FocusFollowsMouseController(locator: locator, logger: DebugLogger(), dwellDelay: dwellDelay)

        controller.mouseMoved(to: CGPoint(x: 10, y: 10), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(0.1))

        XCTAssertEqual(window.focusCallCount, 0)
        XCTAssertTrue(locator.queriedPoints.isEmpty)
    }

    func test_checkDwell_atOrAfterDwellDelay_focusesWindowAtLastPoint() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow()
        locator.windowToReturn = window
        let controller = FocusFollowsMouseController(locator: locator, logger: DebugLogger(), dwellDelay: dwellDelay)

        controller.mouseMoved(to: CGPoint(x: 10, y: 20), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))

        XCTAssertEqual(window.focusCallCount, 1)
        XCTAssertEqual(locator.queriedPoints, [CGPoint(x: 10, y: 20)])
    }

    func test_checkDwell_repeatedlyAfterFiring_doesNotRefocus() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow()
        locator.windowToReturn = window
        let controller = FocusFollowsMouseController(locator: locator, logger: DebugLogger(), dwellDelay: dwellDelay)

        controller.mouseMoved(to: CGPoint(x: 10, y: 20), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay + 1))
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay + 2))

        XCTAssertEqual(window.focusCallCount, 1)
        XCTAssertEqual(locator.queriedPoints.count, 1)
    }

    func test_movementAfterDwellFired_resetsAndFiresAgain() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow()
        locator.windowToReturn = window
        let controller = FocusFollowsMouseController(locator: locator, logger: DebugLogger(), dwellDelay: dwellDelay)

        controller.mouseMoved(to: CGPoint(x: 10, y: 20), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))
        XCTAssertEqual(window.focusCallCount, 1)

        let secondMoveTime = epoch.addingTimeInterval(dwellDelay + 1)
        controller.mouseMoved(to: CGPoint(x: 30, y: 40), at: secondMoveTime)
        controller.checkDwell(now: secondMoveTime.addingTimeInterval(0.1))
        XCTAssertEqual(window.focusCallCount, 1, "still within the new dwell window")

        controller.checkDwell(now: secondMoveTime.addingTimeInterval(dwellDelay))
        XCTAssertEqual(window.focusCallCount, 2)
        XCTAssertEqual(locator.queriedPoints, [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)])
    }

    func test_movementToSamePoint_doesNotResetAnAlreadyElapsedDwell() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow()
        locator.windowToReturn = window
        let controller = FocusFollowsMouseController(locator: locator, logger: DebugLogger(), dwellDelay: dwellDelay)

        controller.mouseMoved(to: CGPoint(x: 10, y: 20), at: epoch)
        // Redundant report of the same point shortly before the dwell delay
        // would otherwise have elapsed — must not push the deadline out.
        controller.mouseMoved(to: CGPoint(x: 10, y: 20), at: epoch.addingTimeInterval(0.2))
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))

        XCTAssertEqual(window.focusCallCount, 1)
    }

    func test_checkDwell_withNoWindowAtPoint_doesNotCrashOrFocus() {
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = nil
        let controller = FocusFollowsMouseController(locator: locator, logger: DebugLogger(), dwellDelay: dwellDelay)

        controller.mouseMoved(to: CGPoint(x: 10, y: 20), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))

        XCTAssertEqual(locator.queriedPoints, [CGPoint(x: 10, y: 20)])
    }

    func test_successfulFocus_logsOneLine() {
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = FakeAXWindow()
        let logger = DebugLogger()
        let controller = FocusFollowsMouseController(locator: locator, logger: logger, dwellDelay: dwellDelay)

        controller.mouseMoved(to: CGPoint(x: 10, y: 20), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))

        XCTAssertEqual(logger.entries.map(\.message), ["Focus-follows-mouse: focused window under mouse."])
    }

    // MARK: - Raise guard (undoing an app's unwanted self-raise)

    func test_checkForUnwantedRaise_withoutAnyPriorFocus_doesNothing() {
        let orderRestoring = FakeWindowOrderRestoring()
        let controller = FocusFollowsMouseController(
            locator: FakeAXWindowLocator(),
            logger: DebugLogger(),
            dwellDelay: dwellDelay,
            windowListProviding: FakeWindowListProviding(snapshots: [[]]),
            windowOrderRestoring: orderRestoring
        )

        controller.checkForUnwantedRaise(now: epoch)

        XCTAssertTrue(orderRestoring.raisedWindowIDs.isEmpty)
    }

    func test_focus_whenTargetAlreadyFrontmost_neverCorrects() {
        let window = FakeAXWindow()
        window.position = CGPoint(x: 0, y: 0)
        window.size = CGSize(width: 100, height: 100)
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = window

        let targetInfo = makeWindowInfo(number: 1, bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        let listProviding = FakeWindowListProviding(snapshots: [[targetInfo]])
        let orderRestoring = FakeWindowOrderRestoring()
        let controller = FocusFollowsMouseController(
            locator: locator,
            logger: DebugLogger(),
            dwellDelay: dwellDelay,
            windowListProviding: listProviding,
            windowOrderRestoring: orderRestoring
        )

        controller.mouseMoved(to: CGPoint(x: 10, y: 20), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))
        controller.checkForUnwantedRaise(now: epoch.addingTimeInterval(dwellDelay + 1))

        XCTAssertTrue(orderRestoring.raisedWindowIDs.isEmpty, "already frontmost — nothing to protect")
    }

    func test_checkForUnwantedRaise_whenTargetBecomesFrontmost_restoresPreviousFrontWindow() {
        let window = FakeAXWindow()
        window.position = CGPoint(x: 100, y: 100)
        window.size = CGSize(width: 200, height: 200)
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = window

        let previousFront = makeWindowInfo(number: 1, bounds: CGRect(x: 0, y: 0, width: 50, height: 50), ownerName: "iTerm2")
        let targetInfo = makeWindowInfo(number: 2, bounds: CGRect(x: 100, y: 100, width: 200, height: 200), ownerName: "Firefox")
        // Before focus: previousFront is frontmost (index 0). After the app
        // self-raises, target becomes frontmost instead.
        let listProviding = FakeWindowListProviding(snapshots: [
            [previousFront, targetInfo],
            [targetInfo, previousFront],
        ])
        let orderRestoring = FakeWindowOrderRestoring()
        let controller = FocusFollowsMouseController(
            locator: locator,
            logger: DebugLogger(),
            dwellDelay: dwellDelay,
            windowListProviding: listProviding,
            windowOrderRestoring: orderRestoring
        )

        controller.mouseMoved(to: CGPoint(x: 150, y: 150), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))
        controller.checkForUnwantedRaise(now: epoch.addingTimeInterval(dwellDelay + 1))

        XCTAssertEqual(orderRestoring.raisedWindowIDs, [CGWindowID(previousFront.windowNumber)])
    }

    func test_checkForUnwantedRaise_correctsOnlyOnce() {
        let window = FakeAXWindow()
        window.position = CGPoint(x: 100, y: 100)
        window.size = CGSize(width: 200, height: 200)
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = window

        let previousFront = makeWindowInfo(number: 1, bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let targetInfo = makeWindowInfo(number: 2, bounds: CGRect(x: 100, y: 100, width: 200, height: 200))
        let listProviding = FakeWindowListProviding(snapshots: [
            [previousFront, targetInfo],
            [targetInfo, previousFront],
        ])
        let orderRestoring = FakeWindowOrderRestoring()
        let controller = FocusFollowsMouseController(
            locator: locator,
            logger: DebugLogger(),
            dwellDelay: dwellDelay,
            windowListProviding: listProviding,
            windowOrderRestoring: orderRestoring
        )

        controller.mouseMoved(to: CGPoint(x: 150, y: 150), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))
        controller.checkForUnwantedRaise(now: epoch.addingTimeInterval(dwellDelay + 1))
        controller.checkForUnwantedRaise(now: epoch.addingTimeInterval(dwellDelay + 2))
        controller.checkForUnwantedRaise(now: epoch.addingTimeInterval(dwellDelay + 3))

        XCTAssertEqual(orderRestoring.raisedWindowIDs.count, 1)
    }

    func test_checkForUnwantedRaise_afterGuardDeadlineExpires_stopsCorrecting() {
        let window = FakeAXWindow()
        window.position = CGPoint(x: 100, y: 100)
        window.size = CGSize(width: 200, height: 200)
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = window

        let previousFront = makeWindowInfo(number: 1, bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let targetInfo = makeWindowInfo(number: 2, bounds: CGRect(x: 100, y: 100, width: 200, height: 200))
        // Target only becomes frontmost after the guard's deadline has
        // already passed.
        let listProviding = FakeWindowListProviding(snapshots: [
            [previousFront, targetInfo],
            [targetInfo, previousFront],
        ])
        let orderRestoring = FakeWindowOrderRestoring()
        let controller = FocusFollowsMouseController(
            locator: locator,
            logger: DebugLogger(),
            dwellDelay: dwellDelay,
            windowListProviding: listProviding,
            windowOrderRestoring: orderRestoring
        )

        controller.mouseMoved(to: CGPoint(x: 150, y: 150), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))
        let afterDeadline = epoch.addingTimeInterval(dwellDelay + FocusFollowsMouseController.raiseGuardDuration + 1)
        controller.checkForUnwantedRaise(now: afterDeadline)

        XCTAssertTrue(orderRestoring.raisedWindowIDs.isEmpty)
    }

    func test_checkForUnwantedRaise_ignoresNonNormalLayerWindows() {
        let window = FakeAXWindow()
        window.position = CGPoint(x: 100, y: 100)
        window.size = CGSize(width: 200, height: 200)
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = window

        // A menu-bar-layer window sits at index 0 both times; it must be
        // skipped so the real (layer 0) frontmost window is what's tracked
        // and restored.
        let menuBar = makeWindowInfo(number: 99, bounds: CGRect(x: 0, y: 0, width: 1000, height: 24), layer: 25)
        let previousFront = makeWindowInfo(number: 1, bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let targetInfo = makeWindowInfo(number: 2, bounds: CGRect(x: 100, y: 100, width: 200, height: 200))
        let listProviding = FakeWindowListProviding(snapshots: [
            [menuBar, previousFront, targetInfo],
            [menuBar, targetInfo, previousFront],
        ])
        let orderRestoring = FakeWindowOrderRestoring()
        let controller = FocusFollowsMouseController(
            locator: locator,
            logger: DebugLogger(),
            dwellDelay: dwellDelay,
            windowListProviding: listProviding,
            windowOrderRestoring: orderRestoring
        )

        controller.mouseMoved(to: CGPoint(x: 150, y: 150), at: epoch)
        controller.checkDwell(now: epoch.addingTimeInterval(dwellDelay))
        controller.checkForUnwantedRaise(now: epoch.addingTimeInterval(dwellDelay + 1))

        XCTAssertEqual(orderRestoring.raisedWindowIDs, [CGWindowID(previousFront.windowNumber)])
    }
}
