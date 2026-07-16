import XCTest
@testable import XDragMover

@MainActor
final class AppSettingsTests: XCTestCase {

    /// A fresh, isolated `UserDefaults` domain per test, so these never
    /// read/write the real `.standard` domain (which would pollute other
    /// tests and the developer's actual machine) — cleaned up in
    /// `tearDown`.
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_freshInstall_usesDefaults_withoutPromptingForMigration() {
        var confirmMigrationCallCount = 0
        let settings = AppSettings(defaults: defaults) { _ in
            confirmMigrationCallCount += 1
            return true
        }

        XCTAssertEqual(confirmMigrationCallCount, 0, "no prior settings exist — this isn't a migration")
        XCTAssertFalse(settings.focusFollowsMouseEnabled, "focus-follows-mouse defaults to off")
        XCTAssertEqual(settings.focusFollowsMouseDelayMS, AppSettings.defaultFocusFollowsMouseDelayMS)
        XCTAssertTrue(settings.moveEnabled)
        XCTAssertTrue(settings.resizeEnabled)
        XCTAssertEqual(settings.gestureModifier, .command)
        XCTAssertFalse(settings.hideMenuBarIconEnabled)
        XCTAssertEqual(settings.excludedWindowPatterns, [])
        XCTAssertFalse(settings.middleClickDockNewInstanceEnabled, "middle-click-Dock is opt-in — it has a real, visible side effect")
        XCTAssertFalse(settings.checkForUpdatesEnabled, "update checks are opt-in — this is the app's only networking code")
    }

    func test_freshInstall_writesCurrentSchemaVersion() {
        _ = AppSettings(defaults: defaults) { _ in true }

        XCTAssertEqual(defaults.integer(forKey: "SettingsSchemaVersion"), AppSettings.currentSchemaVersion)
    }

    func test_changedValues_persistAcrossANewInstance() {
        let first = AppSettings(defaults: defaults) { _ in true }
        first.focusFollowsMouseEnabled = true
        first.focusFollowsMouseDelayMS = 400
        first.moveEnabled = false
        first.resizeEnabled = false
        first.gestureModifier = .option
        first.hideMenuBarIconEnabled = true
        first.excludedWindowPatterns = ["^Calculator$"]
        first.middleClickDockNewInstanceEnabled = true
        first.checkForUpdatesEnabled = true

        let second = AppSettings(defaults: defaults) { _ in true }

        XCTAssertTrue(second.focusFollowsMouseEnabled)
        XCTAssertEqual(second.focusFollowsMouseDelayMS, 400)
        XCTAssertFalse(second.moveEnabled)
        XCTAssertFalse(second.resizeEnabled)
        XCTAssertEqual(second.gestureModifier, .option)
        XCTAssertTrue(second.hideMenuBarIconEnabled)
        XCTAssertEqual(second.excludedWindowPatterns, ["^Calculator$"])
        XCTAssertTrue(second.middleClickDockNewInstanceEnabled)
        XCTAssertTrue(second.checkForUpdatesEnabled)
    }

    func test_upToDateStoredVersion_doesNotPromptAndUsesStoredValues() {
        defaults.set(AppSettings.currentSchemaVersion, forKey: "SettingsSchemaVersion")
        defaults.set(false, forKey: "FocusFollowsMouseEnabled")
        defaults.set(999.0, forKey: "FocusFollowsMouseDelayMS")

        var confirmMigrationCallCount = 0
        let settings = AppSettings(defaults: defaults) { _ in
            confirmMigrationCallCount += 1
            return true
        }

        XCTAssertEqual(confirmMigrationCallCount, 0, "already current — nothing to migrate")
        XCTAssertFalse(settings.focusFollowsMouseEnabled)
        XCTAssertEqual(settings.focusFollowsMouseDelayMS, 999)
    }

    // MARK: - Migration decision logic (`resolveStoredVersion`)
    //
    // `AppSettings.currentSchemaVersion` is `1` today — there is no real
    // "older but present" version an actual install could have on disk,
    // since this is the first schema version ever shipped. These tests
    // call the pure decision function directly with an explicit
    // `currentVersion` override to exercise the migration branch anyway,
    // independent of `AppSettings.init`/real persistence — see that
    // function's doc comment.

    func test_resolveStoredVersion_noStoredVersion_isFreshInstall() {
        let outcome = AppSettings.resolveStoredVersion(storedVersion: 0, currentVersion: 3) { _ in true }
        XCTAssertEqual(outcome, .freshInstall)
    }

    func test_resolveStoredVersion_matchingCurrentVersion_isUpToDate() {
        let outcome = AppSettings.resolveStoredVersion(storedVersion: 3, currentVersion: 3) { _ in true }
        XCTAssertEqual(outcome, .upToDate)
    }

    func test_resolveStoredVersion_olderVersion_promptsAndMigratesWhenConfirmed() {
        var descriptionShown: String?
        let outcome = AppSettings.resolveStoredVersion(storedVersion: 1, currentVersion: 2) { description in
            descriptionShown = description
            return true
        }

        XCTAssertEqual(outcome, .migrated)
        XCTAssertNotNil(descriptionShown, "user should be told what's being converted")
    }

    func test_resolveStoredVersion_olderVersion_fallsBackToDefaultsWhenDeclined() {
        let outcome = AppSettings.resolveStoredVersion(storedVersion: 1, currentVersion: 2) { _ in false }
        XCTAssertEqual(outcome, .declinedUsingDefaults)
    }

    func test_enabledChange_firesCallback() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        var observedValues: [Bool] = []
        settings.onFocusFollowsMouseEnabledChange = { observedValues.append($0) }

        settings.focusFollowsMouseEnabled = false

        XCTAssertEqual(observedValues, [false])
    }

    func test_delayChange_firesCallback() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        var observedValues: [Double] = []
        settings.onFocusFollowsMouseDelayChange = { observedValues.append($0) }

        settings.focusFollowsMouseDelayMS = 250

        XCTAssertEqual(observedValues, [250])
    }

    func test_moveEnabledChange_firesCallback() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        var observedValues: [Bool] = []
        settings.onMoveEnabledChange = { observedValues.append($0) }

        settings.moveEnabled = false

        XCTAssertEqual(observedValues, [false])
    }

    func test_resizeEnabledChange_firesCallback() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        var observedValues: [Bool] = []
        settings.onResizeEnabledChange = { observedValues.append($0) }

        settings.resizeEnabled = false

        XCTAssertEqual(observedValues, [false])
    }

    func test_hideMenuBarIconEnabledChange_firesCallback() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        var observedValues: [Bool] = []
        settings.onHideMenuBarIconEnabledChange = { observedValues.append($0) }

        settings.hideMenuBarIconEnabled = true

        XCTAssertEqual(observedValues, [true])
    }

    func test_checkForUpdatesEnabledChange_firesCallback() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        var observedValues: [Bool] = []
        settings.onCheckForUpdatesEnabledChange = { observedValues.append($0) }

        settings.checkForUpdatesEnabled = true

        XCTAssertEqual(observedValues, [true])
    }

    func test_middleClickDockNewInstanceEnabledChange_firesCallback() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        var observedValues: [Bool] = []
        settings.onMiddleClickDockNewInstanceEnabledChange = { observedValues.append($0) }

        settings.middleClickDockNewInstanceEnabled = true

        XCTAssertEqual(observedValues, [true])
    }

    func test_gestureModifierChange_firesCallback() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        var observedValues: [GestureModifier] = []
        settings.onGestureModifierChange = { observedValues.append($0) }

        settings.gestureModifier = .option

        XCTAssertEqual(observedValues, [.option])
    }

    func test_excludedWindowPatternsChange_firesCallback() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        var observedValues: [[String]] = []
        settings.onExcludedWindowPatternsChange = { observedValues.append($0) }

        settings.excludedWindowPatterns = ["^Calculator$"]

        XCTAssertEqual(observedValues, [["^Calculator$"]])
    }

    func test_gestureModifier_rejectsShiftAlone() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        var observedValues: [GestureModifier] = []
        settings.onGestureModifierChange = { observedValues.append($0) }

        settings.gestureModifier = .shift

        XCTAssertEqual(settings.gestureModifier, .command, "invalid assignment should be reverted")
        XCTAssertTrue(observedValues.isEmpty, "an invalid assignment should never persist/broadcast")
    }

    func test_gestureModifier_rejectsEmptySet() {
        let settings = AppSettings(defaults: defaults) { _ in true }

        settings.gestureModifier = []

        XCTAssertEqual(settings.gestureModifier, .command)
    }

    // MARK: - Snapshot / restore

    func test_makeSnapshot_restore_revertsEveryProperty() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        let snapshot = settings.makeSnapshot()

        settings.focusFollowsMouseEnabled = true
        settings.focusFollowsMouseDelayMS = 700
        settings.moveEnabled = false
        settings.resizeEnabled = false
        settings.gestureModifier = .option
        settings.hideMenuBarIconEnabled = true
        settings.excludedWindowPatterns = ["^Calculator$"]
        settings.middleClickDockNewInstanceEnabled = true
        settings.checkForUpdatesEnabled = true

        settings.restore(snapshot)

        XCTAssertFalse(settings.focusFollowsMouseEnabled)
        XCTAssertEqual(settings.focusFollowsMouseDelayMS, AppSettings.defaultFocusFollowsMouseDelayMS)
        XCTAssertTrue(settings.moveEnabled)
        XCTAssertTrue(settings.resizeEnabled)
        XCTAssertEqual(settings.gestureModifier, .command)
        XCTAssertFalse(settings.hideMenuBarIconEnabled)
        XCTAssertEqual(settings.excludedWindowPatterns, [])
        XCTAssertFalse(settings.middleClickDockNewInstanceEnabled)
        XCTAssertFalse(settings.checkForUpdatesEnabled)
    }

    func test_restore_firesChangeCallbacks() {
        let settings = AppSettings(defaults: defaults) { _ in true }
        let snapshot = settings.makeSnapshot()
        settings.moveEnabled = false
        settings.excludedWindowPatterns = ["^Calculator$"]

        var observedMoveEnabled: [Bool] = []
        settings.onMoveEnabledChange = { observedMoveEnabled.append($0) }
        var observedExcludedWindowPatterns: [[String]] = []
        settings.onExcludedWindowPatternsChange = { observedExcludedWindowPatterns.append($0) }

        settings.restore(snapshot)

        XCTAssertEqual(observedMoveEnabled, [true], "restore should fire the callback, not just write the property silently")
        XCTAssertEqual(observedExcludedWindowPatterns, [[]])
    }
}
