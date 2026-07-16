import XCTest
@testable import XDragMover

private struct FakeDockIconResolver: DockIconResolving {
    var urlToReturn: URL?
    func appURL(at point: CGPoint) -> URL? { urlToReturn }
}

private final class FakeAppLauncher: AppLaunching {
    var launchedURLs: [URL] = []
    func launchNewInstance(at url: URL) { launchedURLs.append(url) }
}

@MainActor
final class MiddleClickDockControllerTests: XCTestCase {

    func test_middleMouseDown_onAppDockIcon_launchesNewInstance() {
        let url = URL(fileURLWithPath: "/Applications/Calculator.app")
        let resolver = FakeDockIconResolver(urlToReturn: url)
        let launcher = FakeAppLauncher()
        let controller = MiddleClickDockController(dockIconResolver: resolver, appLauncher: launcher, logger: DebugLogger.shared)

        let handled = controller.middleMouseDown(at: CGPoint(x: 100, y: 200))

        XCTAssertTrue(handled)
        XCTAssertEqual(launcher.launchedURLs, [url])
    }

    func test_middleMouseDown_notOnAppDockIcon_doesNothing() {
        let resolver = FakeDockIconResolver(urlToReturn: nil)
        let launcher = FakeAppLauncher()
        let controller = MiddleClickDockController(dockIconResolver: resolver, appLauncher: launcher, logger: DebugLogger.shared)

        let handled = controller.middleMouseDown(at: CGPoint(x: 500, y: 500))

        XCTAssertFalse(handled)
        XCTAssertTrue(launcher.launchedURLs.isEmpty)
    }
}
