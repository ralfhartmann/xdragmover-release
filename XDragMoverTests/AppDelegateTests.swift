import XCTest
import AppKit
@testable import XDragMover

@MainActor
final class AppDelegateTests: XCTestCase {

    // Regression test for: `make test` / `xcodebuild test` launches
    // XDragMover as the real TEST_HOST app, which used to run its
    // normal startup path — including a real, blocking Accessibility
    // permission prompt — on every CI test run. `AppDelegate` must detect
    // that it's hosting an XCTest run and skip that startup path.
    //
    // Since this test itself only ever executes *while* being run by
    // XCTest, `isRunningUnitTests` must be true right here — this directly
    // exercises the same environment-variable check the app relies on at
    // launch, in the same process context where the bug occurred.
    func test_isRunningUnitTests_isTrue_whileHostedByXCTest() {
        XCTAssertTrue(AppDelegate.isRunningUnitTests)
    }

    func test_isDebugModeRequested_trueWhenFlagPresent() {
        XCTAssertTrue(AppDelegate.isDebugModeRequested(arguments: ["/path/XDragMover", "--debug"]))
    }

    func test_isDebugModeRequested_falseWhenFlagAbsent() {
        XCTAssertFalse(AppDelegate.isDebugModeRequested(arguments: ["/path/XDragMover"]))
    }

    func test_isDebugModeRequested_falseForEmptyArguments() {
        XCTAssertFalse(AppDelegate.isDebugModeRequested(arguments: []))
    }

    func test_isDebugModeRequested_trueRegardlessOfFlagPosition() {
        XCTAssertTrue(AppDelegate.isDebugModeRequested(arguments: ["--debug", "/path/XDragMover"]))
    }

    // MARK: - Dock icon policy (`desiredActivationPolicy`)

    func test_desiredActivationPolicy_debugMode_alwaysRegular() {
        XCTAssertEqual(
            AppDelegate.desiredActivationPolicy(isDebugMode: true, hasAnyOwnWindowOpen: false),
            .regular
        )
        XCTAssertEqual(
            AppDelegate.desiredActivationPolicy(isDebugMode: true, hasAnyOwnWindowOpen: true),
            .regular
        )
    }

    func test_desiredActivationPolicy_normalMode_regularOnlyWhileAWindowIsOpen() {
        XCTAssertEqual(
            AppDelegate.desiredActivationPolicy(isDebugMode: false, hasAnyOwnWindowOpen: true),
            .regular
        )
        XCTAssertEqual(
            AppDelegate.desiredActivationPolicy(isDebugMode: false, hasAnyOwnWindowOpen: false),
            .accessory
        )
    }
}
