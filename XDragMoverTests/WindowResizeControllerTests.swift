import XCTest
import CoreGraphics
@testable import XDragMover

/// A fake `AXWindowHandling` that records every `setPosition`/`setSize`/
/// `raise` call instead of touching any real window, so resize math can be
/// verified exactly. Kept private to this file, mirroring the equivalent
/// fake in `WindowMoveControllerTests`.
private final class FakeAXWindow: AXWindowHandling {
    var position: CGPoint?
    var size: CGSize?
    var ownerName: String?
    private(set) var setPositionCalls: [CGPoint] = []
    private(set) var setSizeCalls: [CGSize] = []
    private(set) var raiseCallCount = 0

    init(position: CGPoint?, size: CGSize?, ownerName: String? = nil) {
        self.position = position
        self.size = size
        self.ownerName = ownerName
    }

    func setPosition(_ point: CGPoint) {
        setPositionCalls.append(point)
        position = point
    }

    func setSize(_ size: CGSize) {
        setSizeCalls.append(size)
        self.size = size
    }

    func raise() {
        raiseCallCount += 1
    }

    func focus() {}
}

private final class FakeAXWindowLocator: AXWindowLocating {
    var windowToReturn: AXWindowHandling?
    private(set) var queriedPoints: [CGPoint] = []

    func window(at point: CGPoint) -> AXWindowHandling? {
        queriedPoints.append(point)
        return windowToReturn
    }
}

@MainActor
final class WindowResizeControllerTests: XCTestCase {

    /// A 200x100 window at (100, 100), i.e. spanning x:[100,300], y:[100,200]
    /// in the top-left-origin coordinate space `AXWindowHandling` uses.
    private func makeWindow() -> FakeAXWindow {
        FakeAXWindow(position: CGPoint(x: 100, y: 100), size: CGSize(width: 200, height: 100))
    }

    func test_mouseDown_withoutCommandKey_doesNothing() {
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = makeWindow()
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        let consumed = controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: false)

        XCTAssertFalse(consumed)
        XCTAssertFalse(controller.isResizing)
        XCTAssertTrue(locator.queriedPoints.isEmpty)
    }

    func test_mouseDown_withCommandKey_butNoWindowAtPoint_doesNothing() {
        let locator = FakeAXWindowLocator()
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        let consumed = controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: true)

        XCTAssertFalse(consumed)
        XCTAssertFalse(controller.isResizing)
    }

    func test_mouseDown_nearBottomRightCorner_startsResizeAndRaises() {
        let locator = FakeAXWindowLocator()
        let window = makeWindow()
        locator.windowToReturn = window
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        // Well inside the bottom-right quadrant of the 200x100 window at (100,100).
        let consumed = controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: true)

        XCTAssertTrue(consumed)
        XCTAssertTrue(controller.isResizing)
        XCTAssertEqual(window.raiseCallCount, 1)
    }

    func test_mouseDown_windowOwnerExcluded_doesNothing() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow(position: CGPoint(x: 100, y: 100), size: CGSize(width: 200, height: 100), ownerName: "Calculator")
        locator.windowToReturn = window
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())
        controller.exclusionMatcher = WindowExclusionList(patterns: ["^Calculator$"])

        let consumed = controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: true)

        XCTAssertFalse(consumed)
        XCTAssertFalse(controller.isResizing)
        XCTAssertEqual(window.raiseCallCount, 0)
    }

    func test_mouseDown_windowOwnerNotExcluded_stillStartsResize() {
        let locator = FakeAXWindowLocator()
        let window = FakeAXWindow(position: CGPoint(x: 100, y: 100), size: CGSize(width: 200, height: 100), ownerName: "Finder")
        locator.windowToReturn = window
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())
        controller.exclusionMatcher = WindowExclusionList(patterns: ["^Calculator$"])

        let consumed = controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: true)

        XCTAssertTrue(consumed)
        XCTAssertTrue(controller.isResizing)
    }

    func test_mouseDragged_fromBottomRightCorner_keepsTopLeftFixed() {
        let locator = FakeAXWindowLocator()
        let window = makeWindow()
        locator.windowToReturn = window
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: true)
        let consumed = controller.mouseDragged(to: CGPoint(x: 310, y: 220)) // +20, +30

        XCTAssertTrue(consumed)
        // Top-left (100,100) stays put; bottom-right grows by the mouse delta.
        XCTAssertEqual(window.position, CGPoint(x: 100, y: 100))
        XCTAssertEqual(window.size, CGSize(width: 220, height: 130))
        // The origin never actually changes for a bottom-right-corner grab,
        // so the dirty-check in mouseDragged should never re-apply it.
        XCTAssertTrue(window.setPositionCalls.isEmpty)
    }

    func test_mouseDragged_fromTopLeftCorner_keepsBottomRightFixed() {
        let locator = FakeAXWindowLocator()
        let window = makeWindow()
        locator.windowToReturn = window
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        // Well inside the top-left quadrant.
        controller.mouseDown(at: CGPoint(x: 110, y: 110), modifierPressed: true)
        let consumed = controller.mouseDragged(to: CGPoint(x: 90, y: 80)) // -20, -30

        XCTAssertTrue(consumed)
        // Bottom-right (300, 200) stays put; top-left moves by the delta and
        // the window grows to compensate.
        XCTAssertEqual(window.setPositionCalls.last, CGPoint(x: 80, y: 70))
        XCTAssertEqual(window.setSizeCalls.last, CGSize(width: 220, height: 130))
    }

    func test_mouseDragged_fromTopRightCorner_keepsBottomLeftFixed() {
        let locator = FakeAXWindowLocator()
        let window = makeWindow()
        locator.windowToReturn = window
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        // Top-right quadrant.
        controller.mouseDown(at: CGPoint(x: 290, y: 110), modifierPressed: true)
        let consumed = controller.mouseDragged(to: CGPoint(x: 320, y: 90)) // +30, -20

        XCTAssertTrue(consumed)
        // Bottom-left (100, 200) stays put: origin.x unchanged, but origin.y
        // must move up as the window grows taller upward.
        XCTAssertEqual(window.setPositionCalls.last, CGPoint(x: 100, y: 80))
        XCTAssertEqual(window.setSizeCalls.last, CGSize(width: 230, height: 120))
    }

    func test_mouseDragged_repeatedly_computesFromOriginalMouseDownEachTime() {
        let locator = FakeAXWindowLocator()
        let window = makeWindow()
        locator.windowToReturn = window
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: true)
        controller.mouseDragged(to: CGPoint(x: 300, y: 190))
        controller.mouseDragged(to: CGPoint(x: 350, y: 190))

        XCTAssertEqual(window.setSizeCalls, [
            CGSize(width: 210, height: 100),
            CGSize(width: 260, height: 100),
        ])
    }

    func test_mouseDragged_pastOppositeCorner_clampsToMinimumSize() {
        let locator = FakeAXWindowLocator()
        let window = makeWindow()
        locator.windowToReturn = window
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: true)
        // Drag the bottom-right corner far past the fixed top-left corner.
        controller.mouseDragged(to: CGPoint(x: -500, y: -500))

        XCTAssertEqual(window.size, WindowResizeController.minimumSize)
        // Grabbing the bottom-right corner never moves the top-left origin —
        // only the size shrinks, down to the floor, however far the mouse
        // is dragged past the fixed corner — and the dirty-check means that
        // unchanged origin is never redundantly re-applied.
        XCTAssertEqual(window.position, CGPoint(x: 100, y: 100))
        XCTAssertTrue(window.setPositionCalls.isEmpty)
    }

    func test_mouseDragged_repeatedlyClampedToSameSize_onlyAppliesOnce() {
        let locator = FakeAXWindowLocator()
        let window = makeWindow()
        locator.windowToReturn = window
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: true)
        // Two different points that both clamp to the same minimum size —
        // the second tick's identical result must not be re-applied.
        controller.mouseDragged(to: CGPoint(x: -500, y: -500))
        controller.mouseDragged(to: CGPoint(x: -600, y: -600))

        XCTAssertEqual(window.setSizeCalls, [WindowResizeController.minimumSize])
    }

    func test_mouseDragged_withoutPriorMouseDown_doesNothing() {
        let locator = FakeAXWindowLocator()
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        XCTAssertFalse(controller.mouseDragged(to: CGPoint(x: 50, y: 50)))
    }

    func test_mouseUp_endsResize() {
        let locator = FakeAXWindowLocator()
        let window = makeWindow()
        locator.windowToReturn = window
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: true)
        controller.mouseUp()

        XCTAssertFalse(controller.isResizing)
        XCTAssertFalse(controller.mouseDragged(to: CGPoint(x: 999, y: 999)))
    }

    func test_mouseUp_withoutActiveResize_isSafe() {
        let locator = FakeAXWindowLocator()
        let controller = WindowResizeController(locator: locator, logger: DebugLogger())

        controller.mouseUp()

        XCTAssertFalse(controller.isResizing)
    }

    func test_startAndEnd_logStartAndEndMessagesWithCorner() {
        let locator = FakeAXWindowLocator()
        locator.windowToReturn = makeWindow()
        let logger = DebugLogger()
        let controller = WindowResizeController(locator: locator, logger: logger)

        controller.mouseDown(at: CGPoint(x: 290, y: 190), modifierPressed: true) // bottom-right
        controller.mouseUp()

        XCTAssertEqual(logger.entries.map(\.message), [
            "Window resize started (corner: bottom-right).",
            "Window resize ended.",
        ])
    }

    func test_mouseUp_withoutActiveResize_doesNotLogAnything() {
        let locator = FakeAXWindowLocator()
        let logger = DebugLogger()
        let controller = WindowResizeController(locator: locator, logger: logger)

        controller.mouseUp()

        XCTAssertTrue(logger.entries.isEmpty)
    }
}
