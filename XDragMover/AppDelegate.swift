import AppKit
import SwiftUI
import Foundation

/// Application lifecycle glue: requests the Accessibility permission,
/// starts the mouse/window watcher, the Cmd+drag window move/resize event
/// taps, and (if enabled in `appSettings`) the focus-follows-mouse event
/// tap (US-3) on launch, installs the menu bar status item, and — only
/// when launched with `--debug` — shows the debug log window and a Dock
/// icon, per the README's description of this milestone ("it asks for the
/// necessary permissions", "it shows, as debug output, the window
/// currently under the mouse"). Without `--debug`, the app runs as a
/// background/menu-bar-only utility: no Dock icon, no visible window — the
/// debug log window can still be opened on demand from the Settings
/// window's About tab's "Show Debug Console" button, and the Settings
/// window itself (US-8) from the menu bar item, both via
/// `showDebugWindow()`/`showSettingsWindow()`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    let permissionManager = AccessibilityPermissionManager()
    let watcher = MouseWindowWatcher(logger: DebugLogger.shared)
    let windowMover = WindowMoveEventTap(
        controller: WindowMoveController(locator: SystemAXWindowLocator(), logger: DebugLogger.shared)
    )
    let windowResizer = WindowResizeEventTap(
        controller: WindowResizeController(locator: SystemAXWindowLocator(), logger: DebugLogger.shared)
    )
    let middleClickDock = MiddleClickDockEventTap(
        controller: MiddleClickDockController(
            dockIconResolver: SystemDockIconResolver(),
            appLauncher: WorkspaceAppLauncher(),
            logger: DebugLogger.shared
        )
    )
    let appSettings = AppSettings()
    let updateCheckScheduler = UpdateCheckScheduler()
    private var debugWindow: NSWindow?
    private var settingsWindow: NSWindow?

    // `focusFollowsMouse` and `statusMenu` are `lazy` (rather than plain
    // stored `let`s, like the other properties here) because they need to
    // read `appSettings`/capture `self` — not possible from a stored
    // property's own initializer, since `self` isn't fully initialized at
    // that point yet. `appSettings` itself must stay non-lazy so both of
    // these can rely on it already being set by the time they run.
    lazy var focusFollowsMouse = FocusFollowsMouseEventTap(
        controller: FocusFollowsMouseController(
            locator: SystemAXWindowLocator(),
            logger: DebugLogger.shared,
            dwellDelay: appSettings.focusFollowsMouseDelayMS / 1000
        )
    )
    lazy var statusMenu = StatusMenuController(
        showSettings: { [weak self] in self?.showSettingsWindow() },
        showAbout: { [weak self] in self?.showAboutTab() },
        hideFromMenuBar: { [weak self] in self?.appSettings.hideMenuBarIconEnabled = true },
        checkForUpdatesNow: { [weak self] in self?.checkForUpdatesNow() }
    )

    /// True when this process is running as the host app for an XCTest run
    /// (i.e. `XDragMoverTests`, via `make test` / `xcodebuild test` —
    /// our test target's `TEST_HOST` launches the real app to test against
    /// it with `@testable import`).
    ///
    /// Normal startup must be skipped in that case: requesting the
    /// Accessibility permission pops a real, blocking system dialog, which
    /// hangs an unattended CI runner forever waiting for someone to click
    /// it. `XCTestConfigurationFilePath` is set by Xcode/xcodebuild in the
    /// environment of any process involved in a test run, and is the
    /// standard way to detect this.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// True when the app was launched with the `--debug` command line flag
    /// (e.g. via `make debug`), which is what makes the debug log window
    /// appear. Without it, the app runs with no visible window at all.
    ///
    /// Takes `arguments` as a parameter (defaulting to the real
    /// `CommandLine.arguments`) purely so tests can exercise the flag logic
    /// without depending on how the test binary itself was launched.
    static func isDebugModeRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains("--debug")
    }

    /// Sets the Dock/app-switcher presence before the app finishes
    /// launching, so there's no visible flash of a Dock icon that then
    /// disappears: `.accessory` (menu-bar-only, no Dock icon, no app menu
    /// bar) normally, `.regular` (a normal, Dock-visible app) when launched
    /// with `--debug`, so the debug window behaves like an ordinary window
    /// during development.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Self.isDebugModeRequested() ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLogger.shared.log("XDragMover started.")
        // This is a background/menu-bar utility: it must keep running with
        // no windows open at all (the normal, non-debug case) and must
        // never be silently reclaimed by the OS just because it looks idle
        // — only the menu bar item's explicit "Quit" should end it (see
        // applicationShouldTerminateAfterLastWindowClosed below).
        ProcessInfo.processInfo.disableAutomaticTermination(
            "XDragMover is a background menu bar utility with no main window."
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        // Defensive guard against an empty "XDragMover Settings" window
        // showing up unrequested — most reliably reproducible when launched
        // as a login item, occasionally on a manual relaunch too. Two
        // distinct AppKit/SwiftUI mechanisms can cause this, neither ever
        // wanted here: (1) the placeholder `Settings { EmptyView() }` scene
        // in XDragMoverApp.swift getting auto-shown because it's the only
        // scene this app declares, and (2) AppKit's window-state
        // restoration reopening whatever window was open when the app last
        // quit. Closing it here (and once more, asynchronously, since the
        // placeholder isn't always created yet by the time this method runs
        // synchronously) handles both without depending on which one is at
        // fault. `closeStrayWindows()` skips `settingsWindow`/`debugWindow`
        // so it can't clobber a window this class intentionally opened
        // (e.g. `showDebugWindow()` below, for `--debug`).
        closeStrayWindows()
        DispatchQueue.main.async { [weak self] in self?.closeStrayWindows() }
        guard !Self.isRunningUnitTests else {
            DebugLogger.shared.log("Running as XCTest host — skipping permission request and mouse watcher.")
            return
        }
        watcher.start()
        windowMover.gestureModifier = appSettings.gestureModifier
        windowResizer.gestureModifier = appSettings.gestureModifier
        let exclusionList = WindowExclusionList(patterns: appSettings.excludedWindowPatterns)
        windowMover.controller.exclusionMatcher = exclusionList
        windowResizer.controller.exclusionMatcher = exclusionList
        startEnabledEventTaps()
        permissionManager.onTrustedChange = { [weak self] trusted in
            guard trusted else { return }
            self?.startEnabledEventTaps()
        }
        permissionManager.requestAccessIfNeeded()
        appSettings.onFocusFollowsMouseEnabledChange = { [weak self] enabled in
            guard let self else { return }
            enabled ? self.focusFollowsMouse.start() : self.focusFollowsMouse.stop()
        }
        appSettings.onFocusFollowsMouseDelayChange = { [weak self] delayMS in
            self?.focusFollowsMouse.controller.dwellDelay = delayMS / 1000
        }
        appSettings.onMoveEnabledChange = { [weak self] enabled in
            guard let self else { return }
            enabled ? self.windowMover.start() : self.windowMover.stop()
        }
        appSettings.onResizeEnabledChange = { [weak self] enabled in
            guard let self else { return }
            enabled ? self.windowResizer.start() : self.windowResizer.stop()
        }
        appSettings.onGestureModifierChange = { [weak self] modifier in
            guard let self else { return }
            self.windowMover.gestureModifier = modifier
            self.windowResizer.gestureModifier = modifier
        }
        appSettings.onExcludedWindowPatternsChange = { [weak self] patterns in
            guard let self else { return }
            let list = WindowExclusionList(patterns: patterns)
            self.windowMover.controller.exclusionMatcher = list
            self.windowResizer.controller.exclusionMatcher = list
        }
        appSettings.onHideMenuBarIconEnabledChange = { [weak self] hidden in
            self?.statusMenu.setIconVisible(!hidden)
        }
        appSettings.onMiddleClickDockNewInstanceEnabledChange = { [weak self] enabled in
            guard let self else { return }
            enabled ? self.middleClickDock.start() : self.middleClickDock.stop()
        }
        updateCheckScheduler.onUpdateAvailable = { [weak self] latestVersion in
            self?.presentUpdateAvailableAlert(latestVersion: latestVersion)
        }
        if appSettings.checkForUpdatesEnabled {
            updateCheckScheduler.start()
        }
        appSettings.onCheckForUpdatesEnabledChange = { [weak self] enabled in
            guard let self else { return }
            enabled ? self.updateCheckScheduler.start() : self.updateCheckScheduler.stop()
        }
        // A freshly launched `.accessory` app — especially one launched as a
        // login item rather than double-clicked in Finder — is not always
        // fully connected to the window server yet. Activating once up
        // front, right before the status item is installed, is a cheap,
        // harmless precaution against launch-timing races in general — see
        // `StatusMenuController.statusItemClicked` for the actual fix for
        // the menu-not-opening report this alone didn't resolve.
        NSApp.activate(ignoringOtherApps: true)
        statusMenu.install()
        statusMenu.setIconVisible(!appSettings.hideMenuBarIconEnabled)
        if Self.isDebugModeRequested() {
            showDebugWindow()
        }
    }

    /// Starts whichever of `windowMover`/`windowResizer`/`focusFollowsMouse`
    /// are enabled in `appSettings` and require the Accessibility
    /// permission to actually create their `CGEventTap`s. Called once at
    /// launch, and again every time `permissionManager.onTrustedChange`
    /// reports permission just became available.
    ///
    /// This second call site matters: at launch, permission is very
    /// commonly *not yet* granted — the system prompt takes a moment for
    /// the user to click through, or (after a bundle identifier change,
    /// e.g. a rename) it needs granting from scratch. Without retrying
    /// here, that one failed attempt at launch was final: `.start()` was
    /// never called again for the rest of that run, so move/resize/focus-
    /// follows-mouse silently stayed broken even after the user granted
    /// access a moment later — the debug window's status indicator showed
    /// "granted" while the features themselves still didn't work. `.start()`
    /// on each tap is documented safe to call repeatedly (a no-op once
    /// already running), so re-invoking this whenever trust changes to
    /// `true` is enough to pick up the pending, correctly-enabled taps
    /// without duplicating anything already working.
    private func startEnabledEventTaps() {
        if appSettings.moveEnabled {
            windowMover.start()
        }
        if appSettings.resizeEnabled {
            windowResizer.start()
        }
        if appSettings.middleClickDockNewInstanceEnabled {
            middleClickDock.start()
        }
        if appSettings.focusFollowsMouseEnabled {
            focusFollowsMouse.start()
        }
    }

    /// Same `NSAlert` + `NSApp.activate(ignoringOtherApps:)` + `runModal()`
    /// convention as `AppSettings.presentMigrationAlert` and
    /// `SettingsView.presentFocusFollowsMouseWarning` — required here for
    /// the same reason: as a menu-bar-only (`.accessory`) app, XDragMover
    /// is never the active app, so the alert needs to force itself forward
    /// rather than relying on normal window activation.
    ///
    /// `NSAlert` has no native inline hyperlink, so "clickable download
    /// link" is a "Download" button that opens the URL via
    /// `NSWorkspace.shared.open` when clicked, rather than an in-text link.
    private static let updateDownloadURL = URL(
        string: "https://github.com/ralfhartmann/xdragmover-release/releases/latest/download/XDragMover.dmg"
    )!

    private func presentUpdateAvailableAlert(latestVersion: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "A new version is available")
        alert.informativeText = String(localized: "XDragMover \(latestVersion) is available for download.")
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Self.updateDownloadURL)
        }
    }

    /// US-22: "Check for Updates…" (menu bar item) and "Check Now"
    /// (Settings' General tab) both call this — a user-initiated check
    /// that, unlike the silent scheduled one (`UpdateCheckScheduler.
    /// performCheck`), always reports its outcome, matching how any
    /// ordinary "check for updates now" button behaves.
    private func checkForUpdatesNow() {
        updateCheckScheduler.checkNow { [weak self] result in
            switch result {
            case .updateAvailable(let latestVersion):
                self?.presentUpdateAvailableAlert(latestVersion: latestVersion)
            case .upToDate:
                self?.presentUpToDateAlert()
            case .failed(let error):
                self?.presentUpdateCheckFailedAlert(error: error)
            }
        }
    }

    private func presentUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "You're up to date")
        alert.informativeText = String(localized: "XDragMover \(Self.currentVersionString) is the latest version.")
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentUpdateCheckFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Couldn't Check for Updates")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static var currentVersionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Deliberately creates a fresh `SettingsView`/window every time none is
    /// currently open, rather than caching one forever after first creation
    /// (as `showDebugWindow` does) — `SettingsView.init` captures a snapshot
    /// of live state (e.g. `loginItemManaging.isEnabled`) once, so reusing a
    /// stale window would show data that's gone out of sync with changes
    /// made elsewhere (e.g. toggling "Start at Login" from the menu) since
    /// it was first created. `windowWillClose` below clears `settingsWindow`
    /// back to `nil` so the *next* "Settings…" click is guaranteed fresh.
    ///
    /// `NSApp.activate(ignoringOtherApps: true)` is called before
    /// `makeKeyAndOrderFront` for the same reason `showDebugWindow` needs
    /// it: as a menu-bar-only (`.accessory`) app, XDragMover is never the
    /// active app, so `makeKeyAndOrderFront` alone only orders the window
    /// frontmost *within this app's own windows* — confirmed by testing
    /// that without activating first, the Settings window could end up
    /// behind whatever other app was actually active, both when first
    /// created and when re-shown from a cached reference.
    ///
    /// - Parameter initialTab: Which tab the window opens on if it needs to
    ///   be created fresh. Has no effect if a `settingsWindow` is already
    ///   open — see `showAboutTab()`, which closes any existing window
    ///   first specifically so its `initialTab: .about` always takes
    ///   effect, rather than silently landing on whatever tab was already
    ///   showing.
    private func showSettingsWindow(initialTab: SettingsView.Tab = .general) {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentViewController: NSViewController())
        let view = SettingsView(
            settings: appSettings,
            loginItemManaging: SMAppServiceLoginItemManager(),
            showDebugConsole: { [weak self] in self?.showDebugWindow() },
            checkForUpdatesNow: { [weak self] in self?.checkForUpdatesNow() },
            initialTab: initialTab,
            close: { [weak window] in window?.close() }
        )
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "XDragMover Settings"
        // Deliberately does *not* touch `styleMask` (e.g. removing
        // `.resizable`) — confirmed by a real crash that doing so here
        // conflicts with `NSHostingView`'s own constraint-based window
        // sizing (`_postWindowNeedsUpdateConstraints` throws an
        // NSException during `updateWindowContentSizeExtremaIfNecessary`).
        // A resizable settings window is harmless; matches `showDebugWindow`,
        // which has never touched `styleMask` either.
        window.delegate = self
        window.center()
        settingsWindow = window
        updateActivationPolicyForOpenWindows()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The "About XDragMover" menu item's action: opens Settings on its
    /// About tab. Closes any already-open Settings window first — even
    /// though `showSettingsWindow` just brings an existing window forward
    /// as-is, `initialTab` only takes effect while *creating* a fresh
    /// `SettingsView`, so without this, clicking "About" while Settings was
    /// already open on some other tab would bring the window forward
    /// without actually switching tabs. `windowWillClose` (below) clears
    /// `settingsWindow` synchronously as part of `close()`, so the
    /// subsequent `showSettingsWindow` call is guaranteed to take the
    /// fresh-window path.
    private func showAboutTab() {
        settingsWindow?.close()
        showSettingsWindow(initialTab: .about)
    }

    /// Clears `settingsWindow`/`debugWindow` once the corresponding window
    /// closes (via OK, Cancel, or the standard close button), and updates
    /// the Dock icon accordingly (see `updateActivationPolicyForOpenWindows`).
    /// `settingsWindow` additionally needs this so the next "Settings…"
    /// click creates a genuinely fresh window/view instead of finding a
    /// stale cached one; `debugWindow` doesn't strictly need the fresh-copy
    /// behavior, but re-showing a *closed* `NSWindow` (rather than creating
    /// a new one) is unreliable, so it's cleared the same way.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
        } else if window === debugWindow {
            debugWindow = nil
        } else {
            return
        }
        updateActivationPolicyForOpenWindows()
    }

    /// See `showSettingsWindow`'s doc comment for why `NSApp.activate` is
    /// needed before `makeKeyAndOrderFront` on a menu-bar-only app.
    private func showDebugWindow() {
        if let debugWindow {
            NSApp.activate(ignoringOtherApps: true)
            debugWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = DebugLogView(logger: DebugLogger.shared, permissionManager: permissionManager)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "XDragMover Debug Log"
        window.setContentSize(NSSize(width: 560, height: 360))
        window.center()
        window.delegate = self
        debugWindow = window
        updateActivationPolicyForOpenWindows()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Whether the Dock icon should currently be showing: always when
    /// launched with `--debug` (unchanged, existing behavior — a permanent
    /// `.regular` policy for that whole session), otherwise exactly while
    /// at least one of this app's own windows (Settings, Debug Log) is
    /// open. Pulled out as a pure function (rather than inlined into
    /// `updateActivationPolicyForOpenWindows`) so the decision logic is
    /// unit-testable without needing a real `NSApplication`/window — see
    /// `AppDelegateTests`.
    static func desiredActivationPolicy(
        isDebugMode: Bool,
        hasAnyOwnWindowOpen: Bool
    ) -> NSApplication.ActivationPolicy {
        (isDebugMode || hasAnyOwnWindowOpen) ? .regular : .accessory
    }

    /// Applied every time a window is shown/closed so the Dock icon tracks
    /// exactly whether the app currently has a window open — mirroring how
    /// a normal Mac app behaves, and specifically enabling: clicking the
    /// now-visible Dock icon sends the same "reopen" Apple Event as
    /// relaunching the app (see `applicationShouldHandleReopen`), so it
    /// brings Settings back exactly like US-10 already does; once the
    /// window is closed again (and, in `--debug` mode, this is always a
    /// no-op — the Dock icon stays up for the whole session regardless).
    /// Closes any window this class did not itself open — see the call
    /// sites in `applicationDidFinishLaunching` for why this is needed.
    /// Must also skip `statusMenu.window` (the status item's own private
    /// backing window): closing it out from under the status item silently
    /// broke the menu bar icon's click-to-menu handling — the deferred,
    /// `DispatchQueue.main.async`-scheduled call runs after `statusMenu.
    /// install()`, by which point that window already exists in
    /// `NSApp.windows` like any other and would otherwise get swept up
    /// here as "stray".
    private func closeStrayWindows() {
        for window in NSApp.windows
        where window !== settingsWindow && window !== debugWindow && window !== statusMenu.window {
            window.close()
        }
    }

    private func updateActivationPolicyForOpenWindows() {
        NSApp.setActivationPolicy(Self.desiredActivationPolicy(
            isDebugMode: Self.isDebugModeRequested(),
            hasAnyOwnWindowOpen: settingsWindow != nil || debugWindow != nil
        ))
    }

    /// Launching the app again while it's already running doesn't start a
    /// second process — `NSWorkspace`/Launch Services instead sends the
    /// already-running instance this "reopen" Apple Event (the same one
    /// that fires when clicking a running app's Dock icon), regardless of
    /// activation policy. Since this is a menu-bar-only app with no Dock
    /// icon and no window to "reopen", relaunching it is repurposed as a
    /// deliberate way back into the UI — most importantly, as the way to
    /// get the Settings window back if "Hide from Menu Bar" was enabled
    /// and there's no menu bar item left to click.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    /// Must be `false` in normal (non-`--debug`) operation: this is a
    /// background/menu-bar-only utility that never has a "main" window to
    /// begin with, so it must not quit itself just because some transient,
    /// AppKit-internal window closed — including, critically, the status
    /// item's own dropdown menu, which is itself backed by a window. This
    /// returning `true` unconditionally was an existing latent bug from
    /// before the menu bar item existed; it only surfaced once there was a
    /// menu whose closing could be mistaken for "the last window closed"
    /// with no other window around to keep that count above zero, causing
    /// the app to silently quit right after using the status item's menu.
    ///
    /// In `--debug` mode, this stays `true` so closing the debug log window
    /// behaves as it did before: ending that debug session.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.isDebugModeRequested()
    }
}
