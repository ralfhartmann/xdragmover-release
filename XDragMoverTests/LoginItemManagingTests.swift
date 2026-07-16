import XCTest
@testable import XDragMover

final class LoginItemManagingTests: XCTestCase {

    func test_isStableApplicationsPath_trueForSystemApplications() {
        XCTAssertTrue(SMAppServiceLoginItemManager.isStableApplicationsPath(
            "/Applications/XDragMover.app"
        ))
    }

    func test_isStableApplicationsPath_trueForUserApplications() {
        XCTAssertTrue(SMAppServiceLoginItemManager.isStableApplicationsPath(
            "/Users/ralf/Applications/XDragMover.app",
            homeDirectory: "/Users/ralf"
        ))
    }

    func test_isStableApplicationsPath_falseForProjectBuildFolder() {
        // What `make run`/`make debug` actually produce.
        XCTAssertFalse(SMAppServiceLoginItemManager.isStableApplicationsPath(
            "/Users/ralf/Claude/Projects/XDragMover/build/XDragMover.app",
            homeDirectory: "/Users/ralf"
        ))
    }

    func test_isStableApplicationsPath_falseForDownloadsFolder() {
        XCTAssertFalse(SMAppServiceLoginItemManager.isStableApplicationsPath(
            "/Users/ralf/Downloads/XDragMover.app",
            homeDirectory: "/Users/ralf"
        ))
    }

    func test_isStableApplicationsPath_falseForDifferentUsersApplicationsFolder() {
        // Must not match another user's ~/Applications just because the
        // string "Applications" appears somewhere in the path.
        XCTAssertFalse(SMAppServiceLoginItemManager.isStableApplicationsPath(
            "/Users/someoneElse/Applications/XDragMover.app",
            homeDirectory: "/Users/ralf"
        ))
    }
}
