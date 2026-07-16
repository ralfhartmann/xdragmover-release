import AppKit

/// Owns the app's menu bar (status item) presence — the only UI most users
/// will ever see, since the app otherwise runs with no Dock icon and no
/// visible window (see `AppDelegate`). Offers "About" (opens the Settings
/// window's last tab — see `AppDelegate.showSettingsWindow`), "Check for
/// Updates…" (US-22), "Start at Login", "Settings…" (US-8), and "Quit".
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {

    private let loginItemManaging: LoginItemManaging
    private let showSettings: () -> Void
    private let showAbout: () -> Void
    private let hideFromMenuBar: () -> Void
    private let checkForUpdatesNow: () -> Void
    private var statusItem: NSStatusItem?
    private var startAtLoginMenuItem: NSMenuItem?

    /// The private `NSStatusBarWindow` backing the status item's button —
    /// present in `NSApp.windows` like any other window once `install()`
    /// has run. `AppDelegate.closeStrayWindows()` needs to recognize and
    /// skip it by identity, the same way it already skips `settingsWindow`/
    /// `debugWindow`: closing it out from under the status item silently
    /// breaks the button's own click-to-menu tracking (confirmed live —
    /// the click still reached the button, but AppKit's menu-tracking
    /// session for it never started again afterwards).
    var window: NSWindow? { statusItem?.button?.window }

    /// Built once in `install()`, but deliberately *not* assigned to
    /// `statusItem.menu` at rest — see `statusItemClicked`.
    private var menu: NSMenu?

    init(
        loginItemManaging: LoginItemManaging = SMAppServiceLoginItemManager(),
        showSettings: @escaping () -> Void = {},
        showAbout: @escaping () -> Void = {},
        hideFromMenuBar: @escaping () -> Void = {},
        checkForUpdatesNow: @escaping () -> Void = {}
    ) {
        self.loginItemManaging = loginItemManaging
        self.showSettings = showSettings
        self.showAbout = showAbout
        self.hideFromMenuBar = hideFromMenuBar
        self.checkForUpdatesNow = checkForUpdatesNow
        super.init()
    }

    /// Creates the menu bar status item and its dropdown menu. Safe to call
    /// multiple times; subsequent calls are a no-op.
    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
            accessibilityDescription: "XDragMover"
        )

        let menu = NSMenu()
        menu.delegate = self

        let about = NSMenuItem(
            title: String(localized: "About XDragMover"),
            action: #selector(showAboutTapped),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        let checkForUpdates = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(checkForUpdatesTapped),
            keyEquivalent: ""
        )
        checkForUpdates.target = self
        menu.addItem(checkForUpdates)

        menu.addItem(.separator())

        let startAtLogin = NSMenuItem(
            title: String(localized: "Start at Login"),
            action: #selector(toggleStartAtLogin),
            keyEquivalent: ""
        )
        startAtLogin.target = self
        startAtLogin.state = loginItemManaging.isEnabled ? .on : .off
        menu.addItem(startAtLogin)
        startAtLoginMenuItem = startAtLogin

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let hideFromMenuBarItem = NSMenuItem(
            title: String(localized: "Hide from Menu Bar"),
            action: #selector(hideFromMenuBarTapped),
            keyEquivalent: ""
        )
        hideFromMenuBarItem.target = self
        menu.addItem(hideFromMenuBarItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "Quit XDragMover"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        self.menu = menu
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
    }

    /// Presents the menu manually instead of relying on `NSStatusItem`'s
    /// automatic "click opens `.menu`" attachment (i.e. assigning
    /// `item.menu` directly and never touching `target`/`action`). Live
    /// debugging of a report that the menu sometimes doesn't open on click
    /// at all found that with the automatic attachment, `NSMenuDelegate.
    /// menuWillOpen` was never called even though the click itself was
    /// confirmed delivered to the button — i.e. AppKit's own click-tracking
    /// session for the attached menu never started. Driving it explicitly
    /// through a real target/action click (the same mechanism every
    /// ordinary `NSButton` uses) is the standard, more robust alternative
    /// to automatic menu attachment for exactly this class of problem.
    /// `menu` is assigned to `statusItem.menu` only for the duration of
    /// this call — `performClick` synchronously runs the menu's whole
    /// tracking session (it doesn't return until the menu closes) — and
    /// cleared again in `menuDidClose` so the *next* click also goes
    /// through `action` instead of AppKit short-circuiting straight to the
    /// (by-then reattached) menu.
    @objc private func statusItemClicked() {
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    /// See `statusItemClicked` — undoes the temporary `statusItem.menu`
    /// assignment once the menu has closed.
    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    /// Internal (not `private`) so `StatusMenuControllerTests` can drive it
    /// directly, mirroring `openSettings`. Delegates to the injected
    /// `showAbout` closure — `AppDelegate` opens the Settings window on its
    /// About tab, rather than this class showing a modal alert directly (as
    /// it used to): a real tab can hold the "Show Debug Console" button
    /// without the awkwardness of a secondary alert button, and reuses the
    /// Settings window's own already-solved "always come to the front on
    /// this menu-bar-only app" handling instead of needing its own.
    @objc func showAboutTapped() {
        showAbout()
    }

    /// Internal (not `private`) so `StatusMenuControllerTests` can drive it
    /// directly, mirroring `showAboutTapped`. Delegates to the injected
    /// `checkForUpdatesNow` closure — `AppDelegate` owns the actual
    /// network check and result alert, keeping this class as decoupled
    /// from `UpdateCheckScheduler` as it already is from `AppSettings`.
    @objc func checkForUpdatesTapped() {
        checkForUpdatesNow()
    }

    /// Internal (not `private`) so `StatusMenuControllerTests` can drive it
    /// directly, mirroring `toggleStartAtLogin`.
    @objc func openSettings() {
        showSettings()
    }

    /// Internal (not `private`) so `StatusMenuControllerTests` can drive it
    /// directly, mirroring `openSettings`. Delegates to the injected
    /// closure rather than touching `AppSettings` directly, keeping this
    /// class decoupled from it exactly like `showSettings`/`showAbout`.
    @objc func hideFromMenuBarTapped() {
        hideFromMenuBar()
    }

    /// Shows or hides the status item itself — used by `AppDelegate` to
    /// apply `AppSettings.hideMenuBarIconEnabled` (including on launch, and
    /// live whenever it's toggled from Settings). Safe to call before
    /// `install()`; a no-op in that case, since there's no item yet to
    /// show/hide (matching normal startup order, where `AppDelegate` applies
    /// the persisted value only after `install()`).
    func setIconVisible(_ visible: Bool) {
        statusItem?.isVisible = visible
    }

    /// Toggles the login item and refreshes the menu item's checkmark.
    /// Internal (not `private`) so `StatusMenuControllerTests` can drive it
    /// directly without needing a real status item/menu to exist — this
    /// works standalone since it only depends on `loginItemManaging`.
    @objc func toggleStartAtLogin() {
        do {
            try loginItemManaging.setEnabled(!loginItemManaging.isEnabled)
        } catch {
            DebugLogger.shared.log("Failed to change \"Start at Login\": \(error.localizedDescription)")
        }
        startAtLoginMenuItem?.state = loginItemManaging.isEnabled ? .on : .off
    }

    /// Re-reads `loginItemManaging.isEnabled` right before the menu is
    /// shown, so toggling "Start at Login" from the Settings window (which
    /// talks to `LoginItemManaging` directly, not through this class) is
    /// reflected here too — the checkmark otherwise only reflected changes
    /// made via this same menu item.
    func menuWillOpen(_ menu: NSMenu) {
        startAtLoginMenuItem?.state = loginItemManaging.isEnabled ? .on : .off
    }

    /// Confirms before quitting — accidentally hitting "Quit" (or its "q"
    /// key equivalent) would otherwise silently kill window move/resize
    /// with no undo. Uses the same activate-then-modal-`NSAlert` pattern
    /// `AppDelegate.showSettingsWindow`/`showDebugWindow` use, for the same
    /// reason: as a menu-bar-only (`.accessory`) app, we're never the
    /// frontmost app, so the alert needs to force itself forward rather
    /// than relying on normal window activation.
    @objc private func quit() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit XDragMover?")
        alert.informativeText = String(localized: "Window move, resize, and focus-follows-mouse will stop working until you relaunch it.")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }
}
