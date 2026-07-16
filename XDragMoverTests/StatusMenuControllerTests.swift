import XCTest
@testable import XDragMover

/// A fake `LoginItemManaging` recording every `setEnabled` call, so the
/// toggle logic in `StatusMenuController` can be verified without touching
/// the real `SMAppService`/login item registry.
private final class FakeLoginItemManager: LoginItemManaging {
    var isEnabled: Bool
    var shouldThrow = false
    private(set) var setEnabledCalls: [Bool] = []

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        guard !shouldThrow else {
            throw NSError(domain: "StatusMenuControllerTests", code: 1)
        }
        isEnabled = enabled
    }
}

@MainActor
final class StatusMenuControllerTests: XCTestCase {

    func test_toggleStartAtLogin_enablesWhenCurrentlyDisabled() {
        let loginItems = FakeLoginItemManager(isEnabled: false)
        let controller = StatusMenuController(loginItemManaging: loginItems)

        controller.toggleStartAtLogin()

        XCTAssertEqual(loginItems.setEnabledCalls, [true])
        XCTAssertTrue(loginItems.isEnabled)
    }

    func test_toggleStartAtLogin_disablesWhenCurrentlyEnabled() {
        let loginItems = FakeLoginItemManager(isEnabled: true)
        let controller = StatusMenuController(loginItemManaging: loginItems)

        controller.toggleStartAtLogin()

        XCTAssertEqual(loginItems.setEnabledCalls, [false])
        XCTAssertFalse(loginItems.isEnabled)
    }

    func test_toggleStartAtLogin_doesNotCrash_whenUnderlyingCallThrows() {
        let loginItems = FakeLoginItemManager(isEnabled: false)
        loginItems.shouldThrow = true
        let controller = StatusMenuController(loginItemManaging: loginItems)

        controller.toggleStartAtLogin()

        // The attempt was made (and failed), but nothing crashed and the
        // fake's state was correctly left unchanged since the call threw.
        XCTAssertEqual(loginItems.setEnabledCalls, [true])
        XCTAssertFalse(loginItems.isEnabled)
    }

    func test_toggleStartAtLogin_isSafeWithoutInstall() {
        // install() (which creates the real NSStatusItem/menu) was never
        // called; toggling must still work since it only depends on
        // loginItemManaging, not on any menu item existing.
        let loginItems = FakeLoginItemManager(isEnabled: false)
        let controller = StatusMenuController(loginItemManaging: loginItems)

        controller.toggleStartAtLogin()

        XCTAssertEqual(loginItems.setEnabledCalls, [true])
    }

    func test_openSettings_callsInjectedClosure() {
        var callCount = 0
        let controller = StatusMenuController(
            loginItemManaging: FakeLoginItemManager(),
            showSettings: { callCount += 1 }
        )

        controller.openSettings()

        XCTAssertEqual(callCount, 1)
    }

    func test_showAboutTapped_callsInjectedClosure() {
        var callCount = 0
        let controller = StatusMenuController(
            loginItemManaging: FakeLoginItemManager(),
            showAbout: { callCount += 1 }
        )

        controller.showAboutTapped()

        XCTAssertEqual(callCount, 1)
    }

    func test_hideFromMenuBarTapped_callsInjectedClosure() {
        var callCount = 0
        let controller = StatusMenuController(
            loginItemManaging: FakeLoginItemManager(),
            hideFromMenuBar: { callCount += 1 }
        )

        controller.hideFromMenuBarTapped()

        XCTAssertEqual(callCount, 1)
    }

    func test_checkForUpdatesTapped_callsInjectedClosure() {
        var callCount = 0
        let controller = StatusMenuController(
            loginItemManaging: FakeLoginItemManager(),
            checkForUpdatesNow: { callCount += 1 }
        )

        controller.checkForUpdatesTapped()

        XCTAssertEqual(callCount, 1)
    }

    func test_setIconVisible_isSafeWithoutInstall() {
        // install() (which creates the real NSStatusItem) was never called;
        // this must still be safe, mirroring test_toggleStartAtLogin_isSafeWithoutInstall.
        let controller = StatusMenuController(loginItemManaging: FakeLoginItemManager())

        controller.setIconVisible(false)
        controller.setIconVisible(true)
    }
}
