import XCTest
import CoreGraphics
@testable import XDragMover

/// A fake `WindowListProviding` returning a fixed, front-to-back ordered
/// list of windows, so tests never depend on real screen/window state.
private struct FakeWindowListProvider: WindowListProviding {
    let windows: [WindowInfo]
    func currentWindows() -> [WindowInfo] { windows }
}

final class WindowUnderMouseFinderTests: XCTestCase {

    private func makeWindow(
        number: Int,
        owner: String,
        title: String? = nil,
        bounds: CGRect,
        layer: Int = 0
    ) -> WindowInfo {
        WindowInfo(windowNumber: number, ownerName: owner, title: title, bounds: bounds, layer: layer)
    }

    func test_returnsNil_whenNoWindowsExist() {
        let finder = WindowUnderMouseFinder(provider: FakeWindowListProvider(windows: []))
        XCTAssertNil(finder.window(at: CGPoint(x: 10, y: 10)))
    }

    func test_returnsNil_whenPointIsOutsideAllWindows() {
        let window = makeWindow(number: 1, owner: "Finder", bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        let finder = WindowUnderMouseFinder(provider: FakeWindowListProvider(windows: [window]))
        XCTAssertNil(finder.window(at: CGPoint(x: 500, y: 500)))
    }

    func test_returnsWindow_whenPointIsInsideItsBounds() {
        let window = makeWindow(number: 1, owner: "Finder", bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        let finder = WindowUnderMouseFinder(provider: FakeWindowListProvider(windows: [window]))
        XCTAssertEqual(finder.window(at: CGPoint(x: 50, y: 50)), window)
    }

    func test_returnsFrontmostWindow_whenBoundsOverlap() {
        // `currentWindows()` is documented as front-to-back ordered; the
        // finder must return the first (frontmost) match, not the last.
        let front = makeWindow(number: 1, owner: "Terminal", bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        let back = makeWindow(number: 2, owner: "Finder", bounds: CGRect(x: 0, y: 0, width: 400, height: 400))
        let finder = WindowUnderMouseFinder(provider: FakeWindowListProvider(windows: [front, back]))
        XCTAssertEqual(finder.window(at: CGPoint(x: 50, y: 50)), front)
    }

    func test_ignoresNonNormalLayers() {
        // e.g. menus, the Dock, and other system chrome use non-zero layers
        // and must never be reported as "the window under the mouse".
        let menu = makeWindow(number: 1, owner: "Finder", bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 24)
        let normal = makeWindow(number: 2, owner: "Finder", bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0)
        let finder = WindowUnderMouseFinder(provider: FakeWindowListProvider(windows: [menu, normal]))
        XCTAssertEqual(finder.window(at: CGPoint(x: 50, y: 50)), normal)
    }

    func test_boundaryPoint_atOriginIsInside() {
        let window = makeWindow(number: 1, owner: "Finder", bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        let finder = WindowUnderMouseFinder(provider: FakeWindowListProvider(windows: [window]))
        XCTAssertEqual(finder.window(at: CGPoint(x: 0, y: 0)), window)
    }

    func test_boundaryPoint_atFarEdgeIsOutside() {
        // CGRect.contains excludes maxX/maxY, matching AppKit/UIKit convention.
        let window = makeWindow(number: 1, owner: "Finder", bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        let finder = WindowUnderMouseFinder(provider: FakeWindowListProvider(windows: [window]))
        XCTAssertNil(finder.window(at: CGPoint(x: 100, y: 100)))
    }
}
