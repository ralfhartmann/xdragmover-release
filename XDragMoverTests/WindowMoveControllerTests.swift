import XCTest
import CoreGraphics
@testable import XDragMover

/// A fake `AXWindowHandling` that records every `setPosition`/`raise` call
/// instead of touching any real window, so drag math can be verified
/// exactly.
private final class FakeAXWindow: AXWindowHandling {
    var position: CGPoint?
    var size: CGSize?
    var ownerName: String?
    private(set) var setPositionCalls: [CGPoint] = []
    private(set) var raiseCallCount = 0

    init(position: CGPoint?, size: CGSize? = nil, ownerName: String? = nil) {
        self.position = position
        self.size = size
        self.ownerName = ownerName
    }

    func setPosition(_ point: CGPoint) {
        setPositionCalls.append(point)
        position = point
    }

    func setSize(_ size: CGSize) {
        self.size = size
    }

    func raise() {
        raiseCallCount += 1
    }

    func focus() {}
}

/// A fake `AXWindowLocating` returning a fixed, injectable window (or none)
/// for every lookup, and recording the point it was last asked about.
private final class FakeAXWindowLocator: AXWindowLocating {
    var windowToReturn: AXWindowHandling?
    private(set) var queriedPoints: [CGPoint] = []

    func window(at point: CGPoint) -> AXWindowHandling? {
        queriedPoints.append(point)
        return windowToReturn
    }
}

@MainActor
final class WindowMoveControllerTests: XCTestCase {

    func test_mouseDown_withoutCommandKey_doesNothing() {
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = FakeAXWindow(position: .zero)
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())

        let consumed = controller.mouseDown(at: CGPoint(x: 10, y: 10), modifierPressed: false)

        XCTAssertFalse(consumed)
        XCTAssertFalse(controller.isDragging)
        XCTAssertTrue(locator.queriedPoints.isEmpty, "should not even look up a window without Command held")
    }

    func test_mouseDown_withCommandKey_butNoWindowAtPoint_doesNothing() {
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = nil
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())

        let consumed = controller.mouseDown(at: CGPoint(x: 10, y: 10), modifierPressed: true)

        XCTAssertFalse(consumed)
        XCTAssertFalse(controller.isDragging)
    }

    func test_mouseDown_withCommandKey_butWindowHasNoReadablePosition_doesNothing() {
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = FakeAXWindow(position: nil)
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())

        let consumed = controller.mouseDown(at: CGPoint(x: 10, y: 10), modifierPressed: true)

        XCTAssertFalse(consumed)
        XCTAssertFalse(controller.isDragging)
    }

    func test_mouseDown_withCommandKeyAndWindow_startsDragAndRaisesWindow() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow(position: CGPoint(x: 100, y: 100))
        locator.windowToReturn = window
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())

        let consumed = controller.mouseDown(at: CGPoint(x: 110, y: 120), modifierPressed: true)

        XCTAssertTrue(consumed)
        XCTAssertTrue(controller.isDragging)
        XCTAssertEqual(window.raiseCallCount, 1)
    }

    func test_mouseDown_windowOwnerExcluded_doesNothing() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow(position: CGPoint(x: 100, y: 100), ownerName: "Calculator")
        locator.windowToReturn = window
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())
        controller.exclusionMatcher = WindowExclusionList(patterns: ["^Calculator$"])

        let consumed = controller.mouseDown(at: CGPoint(x: 110, y: 120), modifierPressed: true)

        XCTAssertFalse(consumed)
        XCTAssertFalse(controller.isDragging)
        XCTAssertEqual(window.raiseCallCount, 0)
    }

    func test_mouseDown_windowOwnerNotExcluded_stillStartsDrag() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow(position: CGPoint(x: 100, y: 100), ownerName: "Finder")
        locator.windowToReturn = window
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())
        controller.exclusionMatcher = WindowExclusionList(patterns: ["^Calculator$"])

        let consumed = controller.mouseDown(at: CGPoint(x: 110, y: 120), modifierPressed: true)

        XCTAssertTrue(consumed)
        XCTAssertTrue(controller.isDragging)
    }

    func test_mouseDragged_withoutPriorMouseDown_doesNothing() {
        let locator = FakeAXWindowLocator()
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())

        let consumed = controller.mouseDragged(to: CGPoint(x: 50, y: 50))

        XCTAssertFalse(consumed)
    }

    func test_mouseDragged_movesWindowByMouseDelta() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow(position: CGPoint(x: 100, y: 100))
        locator.windowToReturn = window
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())

        controller.mouseDown(at: CGPoint(x: 110, y: 120), modifierPressed: true)
        let consumed = controller.mouseDragged(to: CGPoint(x: 130, y: 150))

        XCTAssertTrue(consumed)
        // mouse moved by (+20, +30) since mouse-down, so the window's
        // original (100, 100) origin should move by the same delta.
        XCTAssertEqual(window.setPositionCalls, [CGPoint(x: 120, y: 130)])
    }

    func test_mouseDragged_repeatedly_computesFromOriginalMouseDownEachTime() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow(position: CGPoint(x: 100, y: 100))
        locator.windowToReturn = window
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())

        controller.mouseDown(at: CGPoint(x: 0, y: 0), modifierPressed: true)
        controller.mouseDragged(to: CGPoint(x: 10, y: 0))
        controller.mouseDragged(to: CGPoint(x: 10, y: 10))
        controller.mouseDragged(to: CGPoint(x: 5, y: 5))

        // Each call's delta is measured from the original mouse-down point,
        // not from the previous drag tick, so rounding never accumulates.
        XCTAssertEqual(window.setPositionCalls, [
            CGPoint(x: 110, y: 100),
            CGPoint(x: 110, y: 110),
            CGPoint(x: 105, y: 105),
        ])
    }

    func test_mouseUp_endsDrag() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow(position: CGPoint(x: 100, y: 100))
        locator.windowToReturn = window
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())

        controller.mouseDown(at: CGPoint(x: 0, y: 0), modifierPressed: true)
        controller.mouseUp()

        XCTAssertFalse(controller.isDragging)
        XCTAssertFalse(controller.mouseDragged(to: CGPoint(x: 999, y: 999)))
        XCTAssertEqual(window.setPositionCalls, [], "no further moves once the drag has ended")
    }

    func test_mouseUp_withoutActiveDrag_isSafe() {
        let locator = FakeAXWindowLocator()
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())

        controller.mouseUp()

        XCTAssertFalse(controller.isDragging)
    }

    func test_startAndEnd_logStartAndEndMessages() {
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = FakeAXWindow(position: CGPoint(x: 100, y: 100))
        let logger = DebugLogger()
        let controller = WindowMoveController(locator: locator, logger: logger)

        controller.mouseDown(at: CGPoint(x: 110, y: 120), modifierPressed: true)
        controller.mouseUp()

        XCTAssertEqual(logger.entries.map(\.message), [
            "Window move started.",
            "Window move ended.",
        ])
    }

    func test_mouseUp_withoutActiveDrag_doesNotLogAnything() {
        let locator = FakeAXWindowLocator()
        let logger = DebugLogger()
        let controller = WindowMoveController(locator: locator, logger: logger)

        controller.mouseUp()

        XCTAssertTrue(logger.entries.isEmpty)
    }

    func test_newDragAfterMouseUp_startsFreshFromNewOrigin() {
        let locator = FakeAXWindowLocator()
        let firstWindow = FakeAXWindow(position: CGPoint(x: 100, y: 100))
        locator.windowToReturn = firstWindow
        let controller = WindowMoveController(locator: locator, logger: DebugLogger())

        controller.mouseDown(at: CGPoint(x: 0, y: 0), modifierPressed: true)
        controller.mouseDragged(to: CGPoint(x: 10, y: 10))
        controller.mouseUp()

        let secondWindow = FakeAXWindow(position: CGPoint(x: 300, y: 300))
        locator.windowToReturn = secondWindow
        controller.mouseDown(at: CGPoint(x: 50, y: 50), modifierPressed: true)
        controller.mouseDragged(to: CGPoint(x: 60, y: 50))

        XCTAssertEqual(secondWindow.setPositionCalls, [CGPoint(x: 310, y: 300)])
        XCTAssertEqual(firstWindow.setPositionCalls, [CGPoint(x: 110, y: 110)])
    }
}
