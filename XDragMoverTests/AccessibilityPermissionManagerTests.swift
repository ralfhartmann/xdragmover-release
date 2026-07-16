import XCTest
@testable import XDragMover

/// A fake `AccessibilityTrustChecking` whose answer can be scripted per
/// test, and which records how it was called, so tests never touch the
/// real system Accessibility trust state.
private final class FakeAccessibilityTrustChecker: AccessibilityTrustChecking {
    var isTrusted: Bool
    private(set) var promptedCallCount = 0
    private(set) var unpromptedCallCount = 0

    /// Optional queue of results returned in order, one per call (regardless
    /// of `promptIfNeeded`), before falling back to `isTrusted`. Lets tests
    /// simulate the trust state changing *between* the two calls
    /// `requestAccessIfNeeded()` can make in a single invocation (an
    /// unprompted check, followed by a prompted one).
    var resultQueue: [Bool] = []

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        if promptIfNeeded {
            promptedCallCount += 1
        } else {
            unpromptedCallCount += 1
        }
        if !resultQueue.isEmpty {
            return resultQueue.removeFirst()
        }
        return isTrusted
    }
}

@MainActor
final class AccessibilityPermissionManagerTests: XCTestCase {

    func test_init_reflectsInitialTrustState_withoutPrompting() {
        let checker = FakeAccessibilityTrustChecker(isTrusted: true)
        let manager = AccessibilityPermissionManager(checker: checker)
        XCTAssertTrue(manager.isTrusted)
        XCTAssertEqual(checker.promptedCallCount, 0)
    }

    func test_init_reflectsUntrustedInitialState() {
        let checker = FakeAccessibilityTrustChecker(isTrusted: false)
        let manager = AccessibilityPermissionManager(checker: checker)
        XCTAssertFalse(manager.isTrusted)
    }

    func test_requestAccessIfNeeded_prompts_whenNotYetTrusted_andUpdatesStateFromPromptResult() {
        let checker = FakeAccessibilityTrustChecker(isTrusted: false)
        let manager = AccessibilityPermissionManager(checker: checker)

        // Simulate: still not trusted on the unprompted check, but granted
        // by the time the prompted check runs.
        checker.resultQueue = [false, true]
        manager.requestAccessIfNeeded()

        XCTAssertEqual(checker.promptedCallCount, 1)
        XCTAssertTrue(manager.isTrusted)
    }

    // Regression test for: the app was showing (or attempting to show) the
    // Accessibility prompt on every launch, even when access had already
    // been granted. `requestAccessIfNeeded()` must check without prompting
    // first, and only fall back to the prompting call when actually needed.
    func test_requestAccessIfNeeded_doesNotPrompt_whenAlreadyTrusted() {
        let checker = FakeAccessibilityTrustChecker(isTrusted: true)
        let manager = AccessibilityPermissionManager(checker: checker)

        manager.requestAccessIfNeeded()

        XCTAssertEqual(checker.promptedCallCount, 0)
        XCTAssertTrue(manager.isTrusted)
    }

    func test_requestAccessIfNeeded_neverPrompts_whenCalledRepeatedlyWhileTrusted() {
        let checker = FakeAccessibilityTrustChecker(isTrusted: true)
        let manager = AccessibilityPermissionManager(checker: checker)

        manager.requestAccessIfNeeded()
        manager.requestAccessIfNeeded()
        manager.requestAccessIfNeeded()

        XCTAssertEqual(checker.promptedCallCount, 0)
    }

    func test_refresh_updatesStateWhenTrustChanges() {
        let checker = FakeAccessibilityTrustChecker(isTrusted: false)
        let manager = AccessibilityPermissionManager(checker: checker)

        checker.isTrusted = true
        manager.refresh()

        XCTAssertTrue(manager.isTrusted)
    }

    func test_refresh_isNoOpWhenTrustUnchanged() {
        let checker = FakeAccessibilityTrustChecker(isTrusted: true)
        let manager = AccessibilityPermissionManager(checker: checker)
        // `init` already performed one unprompted check.
        XCTAssertEqual(checker.unpromptedCallCount, 1)

        manager.refresh()

        XCTAssertEqual(checker.unpromptedCallCount, 2)
        XCTAssertTrue(manager.isTrusted)
    }

    // MARK: - onTrustedChange
    //
    // Regression coverage for: the event taps (move/resize/focus-follows-
    // mouse) only ever attempted to start once, at launch — if permission
    // wasn't granted yet at that exact moment (a common race with the
    // system prompt, or after a bundle identifier change requiring a fresh
    // grant), they silently stayed broken for the rest of that run even
    // once the user granted access moments later. `AppDelegate` now retries
    // starting them via this callback; these tests cover the callback
    // itself firing (or not) at exactly the right times.

    func test_onTrustedChange_firesWhenRefreshTransitionsToTrusted() {
        let checker = FakeAccessibilityTrustChecker(isTrusted: false)
        let manager = AccessibilityPermissionManager(checker: checker)
        var observedValues: [Bool] = []
        manager.onTrustedChange = { observedValues.append($0) }

        checker.isTrusted = true
        manager.refresh()

        XCTAssertEqual(observedValues, [true])
    }

    func test_onTrustedChange_doesNotFire_whenRefreshFindsNoChange() {
        let checker = FakeAccessibilityTrustChecker(isTrusted: true)
        let manager = AccessibilityPermissionManager(checker: checker)
        var observedValues: [Bool] = []
        manager.onTrustedChange = { observedValues.append($0) }

        manager.refresh()

        XCTAssertTrue(observedValues.isEmpty)
    }

    func test_onTrustedChange_firesWhenRequestAccessIfNeeded_transitionsToTrusted() {
        let checker = FakeAccessibilityTrustChecker(isTrusted: false)
        let manager = AccessibilityPermissionManager(checker: checker)
        var observedValues: [Bool] = []
        manager.onTrustedChange = { observedValues.append($0) }

        checker.resultQueue = [false, true]
        manager.requestAccessIfNeeded()

        XCTAssertEqual(observedValues, [true])
    }
}
