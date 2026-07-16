import Foundation
import AppKit

/// Persisted, user-facing settings backing the Settings window (US-8).
/// Backed by `UserDefaults` — the standard, idiomatic mac mechanism for
/// simple app preferences — under the app's own bundle-ID domain, which
/// lives in `~/Library/Preferences/` independently of the `.app` bundle:
/// deleting the app (`scripts/uninstall.sh`, or a plain drag to the Trash)
/// does not touch it, so settings survive an uninstall/reinstall cycle.
///
/// "Start at Login" is deliberately *not* stored here even though it's
/// shown in the Settings window: `SMAppService` (via `LoginItemManaging`)
/// is already its own persisted, OS-level source of truth, and duplicating
/// it here would risk the two disagreeing. `AppSettings` only owns values
/// that have no other source of truth.
@MainActor
final class AppSettings: ObservableObject {

    /// Bumped whenever the shape/meaning of the persisted keys changes.
    /// `init` compares this against whatever was last written
    /// (`SettingsSchemaVersion`) to decide whether a migration is needed —
    /// see `init` and `migrate(from:defaults:)`.
    static let currentSchemaVersion = 1

    private enum Key {
        static let schemaVersion = "SettingsSchemaVersion"
        static let focusFollowsMouseEnabled = "FocusFollowsMouseEnabled"
        static let focusFollowsMouseDelayMS = "FocusFollowsMouseDelayMS"
        static let moveEnabled = "MoveEnabled"
        static let resizeEnabled = "ResizeEnabled"
        static let gestureModifier = "GestureModifier"
        static let hideMenuBarIconEnabled = "HideMenuBarIconEnabled"
        static let excludedWindowPatterns = "ExcludedWindowPatterns"
        static let middleClickDockNewInstanceEnabled = "MiddleClickDockNewInstanceEnabled"
        static let checkForUpdatesEnabled = "CheckForUpdatesEnabled"
    }

    /// Matches `FocusFollowsMouseController`'s own default, so a fresh
    /// install behaves identically whether or not Settings has ever been
    /// opened.
    static let defaultFocusFollowsMouseDelayMS: Double = 150

    /// Off by default: unlike move/resize (whose gesture is an explicit,
    /// deliberate modifier+click the user can't trigger by accident),
    /// focus-follows-mouse changes keyboard focus just from hovering, which
    /// surprises users who haven't opted into it.
    @Published var focusFollowsMouseEnabled: Bool {
        didSet {
            persist()
            onFocusFollowsMouseEnabledChange?(focusFollowsMouseEnabled)
        }
    }

    /// In milliseconds for UI friendliness (a `Slider` over whole
    /// milliseconds reads better than one over fractional seconds);
    /// `FocusFollowsMouseController.dwellDelay` itself is in seconds, so
    /// callers observing this value need to divide by 1000.
    @Published var focusFollowsMouseDelayMS: Double {
        didSet {
            persist()
            onFocusFollowsMouseDelayChange?(focusFollowsMouseDelayMS)
        }
    }

    @Published var moveEnabled: Bool {
        didSet {
            persist()
            onMoveEnabledChange?(moveEnabled)
        }
    }

    @Published var resizeEnabled: Bool {
        didSet {
            persist()
            onResizeEnabledChange?(resizeEnabled)
        }
    }

    /// Hides the menu bar status item entirely. Since that item is the
    /// app's only UI, the sole way back in once this is on is relaunching
    /// the app (e.g. double-clicking it again in Finder/Launchpad) — which
    /// `AppDelegate.applicationShouldHandleReopen` repurposes to show the
    /// Settings window regardless of whether the icon is visible.
    @Published var hideMenuBarIconEnabled: Bool {
        didSet {
            persist()
            onHideMenuBarIconEnabledChange?(hideMenuBarIconEnabled)
        }
    }

    /// The modifier(s) that must be held to start a move/resize gesture
    /// (US-1/US-2), shared by both. The setter silently rejects invalid
    /// combinations (see `GestureModifier.isValid`) by leaving the previous
    /// value in place entirely — no persist, no change callback, no
    /// `objectWillChange` — rather than ever broadcasting one; the UI
    /// (`SettingsView`) is expected to check `isValid` itself before
    /// assigning, so this is a last-resort guard, not the primary check.
    ///
    /// Backed by a plain (non-`@Published`) private property with a manual
    /// `objectWillChange.send()` instead of `@Published`'s own `didSet`,
    /// because `@Published`'s `didSet` already runs *after* the value is
    /// stored — reassigning back to the old value to reject an invalid one
    /// would itself retrigger `didSet` (with the now-valid value), firing
    /// `onGestureModifierChange` anyway even though nothing actually
    /// changed.
    var gestureModifier: GestureModifier {
        get { rawGestureModifier }
        set {
            guard newValue.isValid, newValue != rawGestureModifier else { return }
            objectWillChange.send()
            rawGestureModifier = newValue
            persist()
            onGestureModifierChange?(rawGestureModifier)
        }
    }
    private var rawGestureModifier: GestureModifier = .defaultValue

    /// Regex patterns (matched against `AXWindowHandling.ownerName`/
    /// `kCGWindowOwnerName`) identifying apps that must never be moved or
    /// resized — see `WindowExclusionList`. Normally populated via
    /// `SettingsView`'s window picker (which generates an exact-match
    /// pattern for a chosen app), but each entry stays freely editable as
    /// plain text.
    @Published var excludedWindowPatterns: [String] {
        didSet {
            persist()
            onExcludedWindowPatternsChange?(excludedWindowPatterns)
        }
    }

    /// Off by default (US-16): launching a new instance of whatever app is
    /// clicked has a real, visible side effect the user hasn't necessarily
    /// asked for yet — an accidental middle-click (e.g. a trackpad
    /// three-finger-tap misfire) shouldn't silently spawn a new window —
    /// so this opt-in gesture stays off until explicitly enabled, unlike
    /// move/resize which require a deliberate modifier+click.
    @Published var middleClickDockNewInstanceEnabled: Bool {
        didSet {
            persist()
            onMiddleClickDockNewInstanceEnabledChange?(middleClickDockNewInstanceEnabled)
        }
    }

    /// Off by default: this is the app's only networking code, and it
    /// phones home to GitHub on a schedule (`UpdateCheckScheduler`) — kept
    /// opt-in for the same reason focus-follows-mouse defaults off, even
    /// though this feature carries no functional risk of its own.
    @Published var checkForUpdatesEnabled: Bool {
        didSet {
            persist()
            onCheckForUpdatesEnabledChange?(checkForUpdatesEnabled)
        }
    }

    /// Fired after every change to the matching property (including ones
    /// made before these are set, e.g. during `init`'s migration — callers
    /// that need the initial value too should read the property directly
    /// right after constructing `AppSettings`). `AppDelegate` uses these to
    /// start/stop the corresponding event tap and push live updates,
    /// instead of this file depending on those types directly.
    var onFocusFollowsMouseEnabledChange: ((Bool) -> Void)?
    var onFocusFollowsMouseDelayChange: ((Double) -> Void)?
    var onMoveEnabledChange: ((Bool) -> Void)?
    var onResizeEnabledChange: ((Bool) -> Void)?
    var onGestureModifierChange: ((GestureModifier) -> Void)?
    var onHideMenuBarIconEnabledChange: ((Bool) -> Void)?
    var onExcludedWindowPatternsChange: (([String]) -> Void)?
    var onMiddleClickDockNewInstanceEnabledChange: ((Bool) -> Void)?
    var onCheckForUpdatesEnabledChange: ((Bool) -> Void)?

    private let defaults: UserDefaults

    /// What `resolveStoredVersion` decided to do about whatever
    /// `SettingsSchemaVersion` was found on disk — pulled out as its own
    /// pure, `currentVersion`-parameterized function (rather than being
    /// inlined into `init` against the hardcoded `currentSchemaVersion`)
    /// specifically so it stays unit-testable even though, today, with
    /// only one schema version ever having existed, there's no way to
    /// produce a genuine "older stored version" through real app data —
    /// see `AppSettingsTests`.
    enum MigrationOutcome: Equatable {
        /// No `SettingsSchemaVersion` was stored at all — a fresh install,
        /// not a prior version to migrate from.
        case freshInstall
        /// Stored version is already current; use it as-is.
        case upToDate
        /// Stored version was older; the user confirmed converting it.
        case migrated
        /// Stored version was older; the user declined — fall back to
        /// defaults rather than use possibly-incompatible old values.
        case declinedUsingDefaults
    }

    /// - Parameter confirmMigration: Called with a human-readable
    ///   description of the pending migration when an *older* (but
    ///   present) schema version is found, so the caller can ask the user
    ///   before converting — return `true` to proceed, `false` to discard
    ///   the old values and start fresh from defaults instead. Not called
    ///   at all for `.freshInstall`/`.upToDate`.
    // `currentVersion` has no default value (unlike a simpler API might
    // suggest) because a default referencing the @MainActor-isolated
    // `currentSchemaVersion` can't be evaluated from the nonisolated
    // context Swift evaluates default-argument expressions in — see
    // `MouseWindowWatcher`'s `logger` parameter for the same rationale
    // applied elsewhere in this codebase. Callers pass
    // `AppSettings.currentSchemaVersion` explicitly instead (see `init`).
    static func resolveStoredVersion(
        storedVersion: Int,
        currentVersion: Int,
        confirmMigration: (String) -> Bool
    ) -> MigrationOutcome {
        if storedVersion == 0 {
            return .freshInstall
        } else if storedVersion < currentVersion {
            let description = migrationDescription(fromStoredVersion: storedVersion, currentVersion: currentVersion)
            return confirmMigration(description) ? .migrated : .declinedUsingDefaults
        } else {
            return .upToDate
        }
    }

    /// - Parameter confirmMigration: See `resolveStoredVersion`. Defaults
    ///   to a real `NSAlert`; overridable for tests.
    init(
        defaults: UserDefaults = .standard,
        confirmMigration: @MainActor (String) -> Bool = { AppSettings.presentMigrationAlert(description: $0) }
    ) {
        self.defaults = defaults

        let storedVersion = defaults.object(forKey: Key.schemaVersion) as? Int ?? 0
        let outcome = Self.resolveStoredVersion(
            storedVersion: storedVersion,
            currentVersion: Self.currentSchemaVersion,
            confirmMigration: confirmMigration
        )

        switch outcome {
        case .migrated:
            Self.migrate(from: storedVersion, defaults: defaults)
            fallthrough
        case .upToDate:
            focusFollowsMouseEnabled = defaults.object(forKey: Key.focusFollowsMouseEnabled) as? Bool ?? false
            focusFollowsMouseDelayMS = defaults.object(forKey: Key.focusFollowsMouseDelayMS) as? Double
                ?? Self.defaultFocusFollowsMouseDelayMS
            moveEnabled = defaults.object(forKey: Key.moveEnabled) as? Bool ?? true
            resizeEnabled = defaults.object(forKey: Key.resizeEnabled) as? Bool ?? true
            hideMenuBarIconEnabled = defaults.object(forKey: Key.hideMenuBarIconEnabled) as? Bool ?? false
            excludedWindowPatterns = defaults.object(forKey: Key.excludedWindowPatterns) as? [String] ?? []
            middleClickDockNewInstanceEnabled = defaults.object(forKey: Key.middleClickDockNewInstanceEnabled) as? Bool ?? false
            checkForUpdatesEnabled = defaults.object(forKey: Key.checkForUpdatesEnabled) as? Bool ?? false
            if let storedModifierRawValue = defaults.object(forKey: Key.gestureModifier) as? Int {
                let storedModifier = GestureModifier(rawValue: storedModifierRawValue)
                gestureModifier = storedModifier.isValid ? storedModifier : .defaultValue
            } else {
                gestureModifier = .defaultValue
            }
        case .freshInstall, .declinedUsingDefaults:
            focusFollowsMouseEnabled = false
            focusFollowsMouseDelayMS = Self.defaultFocusFollowsMouseDelayMS
            moveEnabled = true
            resizeEnabled = true
            hideMenuBarIconEnabled = false
            excludedWindowPatterns = []
            middleClickDockNewInstanceEnabled = false
            checkForUpdatesEnabled = false
            gestureModifier = .defaultValue
        }

        defaults.set(Self.currentSchemaVersion, forKey: Key.schemaVersion)
    }

    private func persist() {
        defaults.set(focusFollowsMouseEnabled, forKey: Key.focusFollowsMouseEnabled)
        defaults.set(focusFollowsMouseDelayMS, forKey: Key.focusFollowsMouseDelayMS)
        defaults.set(moveEnabled, forKey: Key.moveEnabled)
        defaults.set(resizeEnabled, forKey: Key.resizeEnabled)
        defaults.set(gestureModifier.rawValue, forKey: Key.gestureModifier)
        defaults.set(hideMenuBarIconEnabled, forKey: Key.hideMenuBarIconEnabled)
        defaults.set(excludedWindowPatterns, forKey: Key.excludedWindowPatterns)
        defaults.set(middleClickDockNewInstanceEnabled, forKey: Key.middleClickDockNewInstanceEnabled)
        defaults.set(checkForUpdatesEnabled, forKey: Key.checkForUpdatesEnabled)
        defaults.set(Self.currentSchemaVersion, forKey: Key.schemaVersion)
    }

    /// A point-in-time copy of every persisted setting, used by
    /// `SettingsView`'s Cancel button to restore exactly what was in effect
    /// when the Settings window was opened, discarding any changes made
    /// since.
    struct Snapshot {
        var focusFollowsMouseEnabled: Bool
        var focusFollowsMouseDelayMS: Double
        var moveEnabled: Bool
        var resizeEnabled: Bool
        var gestureModifier: GestureModifier
        var hideMenuBarIconEnabled: Bool
        var excludedWindowPatterns: [String]
        var middleClickDockNewInstanceEnabled: Bool
        var checkForUpdatesEnabled: Bool
    }

    func makeSnapshot() -> Snapshot {
        Snapshot(
            focusFollowsMouseEnabled: focusFollowsMouseEnabled,
            focusFollowsMouseDelayMS: focusFollowsMouseDelayMS,
            moveEnabled: moveEnabled,
            resizeEnabled: resizeEnabled,
            gestureModifier: gestureModifier,
            hideMenuBarIconEnabled: hideMenuBarIconEnabled,
            excludedWindowPatterns: excludedWindowPatterns,
            middleClickDockNewInstanceEnabled: middleClickDockNewInstanceEnabled,
            checkForUpdatesEnabled: checkForUpdatesEnabled
        )
    }

    /// Re-assigns every property through its normal setter (rather than
    /// writing directly to `defaults`), so `didSet`'s `persist()` call and
    /// change callbacks fire exactly as if the user had changed each value
    /// back by hand — this is what makes Cancel correctly re-stop/re-start
    /// the move/resize/focus-follows-mouse event taps and push the
    /// reverted gesture modifier, not just restore what's on disk.
    func restore(_ snapshot: Snapshot) {
        focusFollowsMouseEnabled = snapshot.focusFollowsMouseEnabled
        focusFollowsMouseDelayMS = snapshot.focusFollowsMouseDelayMS
        moveEnabled = snapshot.moveEnabled
        resizeEnabled = snapshot.resizeEnabled
        gestureModifier = snapshot.gestureModifier
        hideMenuBarIconEnabled = snapshot.hideMenuBarIconEnabled
        excludedWindowPatterns = snapshot.excludedWindowPatterns
        middleClickDockNewInstanceEnabled = snapshot.middleClickDockNewInstanceEnabled
        checkForUpdatesEnabled = snapshot.checkForUpdatesEnabled
    }

    /// Applies whatever steps are needed to bring `defaults`' stored
    /// values from `storedVersion` up to `currentSchemaVersion`. Empty
    /// today — this is the first schema version ever shipped — but kept
    /// as the designated place future migrations plug into, e.g.:
    /// ```swift
    /// if fromVersion < 2 {
    ///     // rename/convert a key that changed shape in v2
    /// }
    /// ```
    private static func migrate(from storedVersion: Int, defaults: UserDefaults) {
        // No prior schema versions exist yet; nothing to convert.
    }

    /// Human-readable description of what a migration from
    /// `storedVersion` would involve, for `confirmMigration` to show the
    /// user. Generic today since there's only ever been one schema.
    private static func migrationDescription(fromStoredVersion storedVersion: Int, currentVersion: Int) -> String {
        "XDragMover found settings saved by an older version of the app " +
        "(format \(storedVersion), current format \(currentVersion)). " +
        "Convert them to the current format?"
    }

    private static func presentMigrationAlert(description: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Update Settings Format?")
        // description is a dynamic, technical migration summary that's
        // never actually shown in practice (there's only ever been one
        // schema version so far) — left untranslated rather than adding
        // translation overhead for a message with no real-world audience.
        alert.informativeText = description
        alert.addButton(withTitle: String(localized: "Convert"))
        alert.addButton(withTitle: String(localized: "Use Defaults Instead"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
