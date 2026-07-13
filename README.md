# XDragMover

A lightweight macOS menu bar utility that brings KDE/Linux-style window manipulation shortcuts to the Mac. It monitors global keyboard and mouse events and lets you move and resize any window from anywhere on its surface, without needing to grab the title bar or a resize handle. It can also optionally give focus to the window under the mouse cursor after the cursor has come to rest for a configurable amount of time.

## Motivation

On many Linux desktop environments (KDE, GNOME, etc.), holding a modifier key (typically `Alt` or the `Super`/`Meta` key) while pressing the mouse anywhere inside a window lets you drag it around, and holding the same modifier with the right mouse button lets you resize it from the nearest corner. macOS has no built-in equivalent. XDragMover recreates this familiar, efficient workflow on macOS, defaulting to the `Command (⌘)` key as the modifier — configurable in Settings (see "Configuration" below).

## Features

### 1. Move a window with a modifier + Left Click

Hold the configured modifier (default `⌘`) and press the left mouse button anywhere inside a window. While the button remains held, dragging the mouse moves the window; the window follows the mouse 1:1 until the button is released. It does not matter which part of the window is clicked — title bar, content area, or anywhere else. Can be disabled entirely from Settings.

### 2. Resize a window with a modifier + Right Click

Hold the configured modifier (default `⌘`) and press the right mouse button anywhere inside a window. The corner of the window closest to the click point becomes the active resize handle, and while the button remains held, dragging the mouse resizes the window exactly as if that corner had been grabbed and dragged manually. Releasing the button ends the resize. Can be disabled entirely from Settings.

### 3. Configurable focus-follows-mouse (window activation on hover)

**Experimental and not fully reliable.** This feature relies on a private,
undocumented WindowServer mechanism (see stage 1 below) that Apple could
change or remove without notice, and its behavior has been observed to vary
by app — some apps (confirmed: Firefox) raise themselves as soon as they
receive input, defeating the "no raise" part of stage 1 (see
`USER_STORIES.md`/`DEVELOPMENT.md` for the yabai-assisted window-order
mitigation this app applies for that case). Off by default for this reason;
Settings shows a one-time warning the first time you turn it on (see
"Configuration" below).

When enabled in Settings, the window under the mouse cursor automatically receives keyboard and mouse input after the cursor has been stationary over it for a dwell time (150ms by default, adjustable in Settings). The dwell timer only starts counting once the mouse stops moving, and any further mouse movement resets it — so the window only activates once the cursor has genuinely come to rest, not simply after passing over it. End-to-end activation latency (dwell time plus the poll interval that checks it) stays comfortably under 200ms.

Activation via hover happens (or, for stage 2, will happen) in two stages:

1. **Input focus (no raise) — implemented (US-3).** Once the dwell delay elapses, the hovered window becomes the recipient of keyboard and mouse input, but it is *not* brought to the front — it stays in its current stacking position. This lets the user type into or scroll a window under the cursor without other windows visually jumping around. macOS has no first-class public API for "focus this window but don't touch stacking order", so this uses a private/undocumented WindowServer mechanism (ported from the yabai window manager), with a public-API-only (`AXFocused`) fallback if that's ever unavailable — see `USER_STORIES.md`'s Non-Functional notes for exactly how, and the fragility that comes with relying on undocumented APIs.
2. **Raise to front (second, separate delay) — not yet implemented (US-3a).** If the cursor keeps hovering (without triggering a click) for an additional, independently configurable delay after input focus was granted, the window is then automatically raised in front of other windows.

Not yet implemented (US-5a/US-5b): either of two events is meant to immediately bring a hover-focused window to the front, without waiting for the second delay — any mouse click on it, or (if the move/resize modifier is held and it isn't already frontmost) a click that raises the window without also being forwarded to the application.

### 4. Exclude specific apps from move/resize

Settings' "Excluded Windows" tab holds a list of regex patterns, matched against an app's name (e.g. `^Calculator$`); any app matching a pattern in the list can never be moved or resized by XDragMover, regardless of the modifier held. Patterns are normally added via "Add from Open Windows…", a picker listing currently-open apps that generates an exact-match pattern for the one you pick, but each entry stays freely editable as plain text afterward for anyone who wants a broader (e.g. substring) match — invalid regexes are shown in red and simply never match anything, rather than blocking or crashing.

### 5. Automatic suspension while a menu is open

While any application's menu bar menu is expanded (open and showing its items), the move, resize, and focus-follows-mouse behaviors should be automatically suspended, so that mouse movement over menu items does not accidentally trigger a window move, resize, or focus change (US-6). **Not yet implemented** for any of the three gestures — see "Status" below.

### 6. Optional update notifications

Settings' General tab has a "Check for Updates" checkbox, off by default since this is the app's only networking code. When enabled, XDragMover checks the public release repo for a newer version 5 minutes after launch and once a day thereafter; if one is found, a dialog offers a direct download link to the new `.dmg`.

### 7. Middle-click a Dock icon for a new instance

Settings' Gestures tab has a "Middle-Click Dock Icon for New Instance" checkbox, off by default (US-16). When enabled, middle-clicking an app's Dock icon opens a new window/instance of that app, resolved via the Dock's own Accessibility hierarchy and opened with `NSWorkspace`. Middle-clicks anywhere outside an app's Dock icon are left completely untouched.

## How It Works

XDragMover runs as a background (menu bar) application that installs a global event monitor (via the macOS Accessibility / Quartz Event Services APIs) to observe keyboard modifier state and mouse button/movement events system-wide. When it detects a qualifying `⌘`+click gesture, it identifies the target window under the cursor via the Accessibility API and drives its position or frame directly using `AXUIElement` position/size attributes, tracking mouse deltas for the duration of the gesture.

Because it needs to observe input events system-wide and reposition windows belonging to other applications, the app requires the user to grant **Accessibility** permissions (System Settings → Privacy & Security → Accessibility) on first launch.

`WindowMoveEventTap`/`WindowResizeEventTap` compare each event's flags against `AppSettings.gestureModifier` (a `GestureModifier` `OptionSet` of Command/Option/Control/Shift, any non-empty combination except Shift alone), instead of a hardcoded `⌘` check — see `GestureModifier.swift`.

> **Technical note:** macOS normally ties keyboard input focus to the frontmost application/window. Delivering input to a hovered window without raising it (stage 1 above) therefore isn't achievable through any public API — confirmed by testing: the public `AXFocused` window attribute alone does not redirect keyboard input away from the actual frontmost app. Instead this uses a private, undocumented WindowServer mechanism (see `USER_STORIES.md`'s Non-Functional notes), falling back to `AXFocused` if that's ever unavailable on a future macOS version.
>
> **Known limitation:** some apps (confirmed: Firefox) raise their own window anyway when they receive real keyboard input — a documented Firefox/WindowServer interaction, not a bug here. An optional, best-effort correction (US-14) exists (`FocusFollowsMouseController`'s raise guard) but requires the external `yabai` window manager with System Integrity Protection partially disabled — see `DEVELOPMENT.md`. Without that setup, the app behaves exactly as before; nothing is required to use XDragMover normally.

## Requirements

- macOS 13 Ventura or later (the Xcode project's deployment target)
- Accessibility permission granted to the app
- Built and signed with Xcode

## Building

1. Open the project in Xcode.
2. Select the app target and build (`⌘B`) or run (`⌘R`).
3. On first launch, grant Accessibility access when prompted.
4. The app runs as a menu bar / background utility; configure its options (enable/disable focus-follows-mouse, set the dwell delay, etc.) from its preferences.

Alternatively, from the command line (requires Xcode's command line tools):

```sh
make                 # build (default target)
make run             # build (into build/) and launch the app
make debug           # like 'run', but shows the debug log window (--debug)
make test            # run the unit tests
make clean           # clean build products
make all             # build, then test
make package         # build a Release .app and zip it into dist/
make install         # build a package and install it into /Applications
                      # (quitting/replacing any existing copy)
make uninstall       # quit the app if running and remove it from /Applications
make dmg             # build a drag-to-Applications .dmg installer into dist/
make bump-version    # bump VERSION.md (BUMP=patch|minor|major, default patch)
make release         # cut a release from dev: test, README review, version
                      # bump, merge dev into main, package (BUMP as above)
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for what `release` and `bump-version` actually do.

### Debug mode

By default, XDragMover runs with **no Dock icon and no visible
window at all** in its idle state — only its menu bar status item. The
Dock icon reappears automatically whenever the Settings or Debug Log
window is open, and disappears again once both are closed. Pass `--debug`
on the command line to keep the Dock icon
and the debug log window described above showing permanently for the
whole session, regardless of open windows. In `--debug` mode, the log
also records the start and end of every move and resize gesture (with,
for resize, which corner was grabbed):

```sh
make debug                              # build + launch with --debug
open build/XDragMover.app --args --debug   # launch an existing build with --debug
```

Without `--debug` (e.g. plain `make run`, or launching normally from
Finder), the app runs silently in the background with no Dock icon,
showing only its menu bar status item, until Settings or the Debug Log
window is opened.

The Debug Log window's "Scroll Lock" button (off by default, persisted)
keeps the console pinned to the newest line as entries arrive when off;
turning it on lets you scroll back through history freely without being
pulled back down on every new line.

## Contributing / Development Workflow

This project uses a `main`/`dev`/`feature`/`bugfix` branching model with a
scripted release process (`make release`). See [DEVELOPMENT.md](DEVELOPMENT.md)
for details before starting work on a feature or bugfix.

## Configuration

Available from the menu bar item's "Settings…" (`SettingsView.swift`), backed by `AppSettings.swift` (persisted via `UserDefaults`, survives uninstalling the app — see `USER_STORIES.md`'s Non-Functional notes for the versioned-migration mechanism in place for when this shape changes in the future):

| Setting | Description | Status |
|---|---|---|
| Start at Login | Toggles the login item (`SMAppService`) | ✅ Implemented |
| Hide from Menu Bar | Hides the status item entirely (US-11). Once hidden, relaunching the app (US-10) is the way to bring Settings back and turn it off again | ✅ Implemented |
| Enable window move | Toggles the move gesture (US-1) on or off. Default: on | ✅ Implemented |
| Enable window resize | Toggles the resize gesture (US-2) on or off. Default: on | ✅ Implemented |
| Modifier key | Which modifier(s) (any combination of Command/Option/Control/Shift, Shift alone excluded) move/resize require. Default: Command | ✅ Implemented |
| Enable focus-follows-mouse | Toggles automatic input focus for the window under the cursor (US-4). Default: off. Experimental — see "Configurable focus-follows-mouse" above; the first time you turn this on, a warning dialog explains why, with a "Don't show this again" checkbox | ✅ Implemented |
| Focus-follows-mouse delay | Dwell time the mouse must remain stationary over a window before it receives input focus (US-3/US-5) | ✅ Implemented |
| Focus-follows-mouse raise delay | Additional dwell time, counted after input focus was granted, after which the focused window is automatically raised to the front (US-3a/US-5) | ⬜ Not implemented — US-3a itself doesn't exist yet |
| Excluded window patterns | Regex patterns (matched against app name) identifying apps that can never be moved or resized (US-15). Add via the "Add from Open Windows…" picker or type a pattern directly | ✅ Implemented |
| Check for Updates | Checks the public release repo for a newer version 5 minutes after launch, then once a day; shows a dialog with a download link if one is found. Default: off — this is the app's only networking code | ✅ Implemented |
| Middle-Click Dock Icon for New Instance | Middle-clicking an app's Dock icon opens a new window/instance of it (US-16). Default: off | ✅ Implemented |

OK closes the dialog keeping any changes made; Cancel reverts every setting (including Start at Login) back to what it was when the dialog was opened. Not (yet) exposed as a pane/section inside System Settings.app — just a standalone dialog.

## Project Structure

- `XDragMover.xcodeproj` – the Xcode project (open this in Xcode).
- `XDragMover/` – app sources. Implemented so far: an `AccessibilityPermissionManager` that checks/requests the Accessibility permission and polls until it's granted; a `WindowUnderMouseFinder`/`CGWindowListProvider` pair that determines which window is currently under the mouse (for the debug log); a polling-based `MouseWindowWatcher` that reports that window; a `DebugLogger`/`DebugLogView` that show this (and future) debug output in a window — only when the app is launched with the `--debug` flag (`make debug`); the modifier+Left-drag window move feature (US-1) and modifier+Right-drag resize feature (US-2), sharing a global-event-tap/testable-controller split (`WindowMoveEventTap`/`WindowMoveController`, `WindowResizeEventTap`/`WindowResizeController`), an `AXWindowLocating`/`AXWindowHandling` pair that reads/moves/resizes/raises/focuses windows via the Accessibility API, and a `GestureModifier` (`OptionSet` of Command/Option/Control/Shift) shared by both taps for which modifier(s) they require; stage 1 of focus-follows-mouse (US-3), sharing the same global-event-tap/testable-controller split (`FocusFollowsMouseEventTap`/`FocusFollowsMouseController`); a `StatusMenuController` that installs the menu bar status item (About, Start at Login, "Hide from Menu Bar", Settings…, Quit), backed by `LoginItemManaging`/`SMAppServiceLoginItemManager`; `AppSettings`/`SettingsView` (US-8) persist and expose every adjustable knob (move/resize enable, the gesture modifier, focus-follows-mouse's on/off switch and dwell delay, hiding the menu bar icon) via `UserDefaults`, with a versioned migration mechanism for future changes to their shape, and OK/Cancel semantics (Cancel restores an `AppSettings.Snapshot` taken when the dialog opened). The Settings window is organized into tabs (General, Gestures, Excluded Windows, Focus Follows Mouse, and — last — About, which shows app name/version/copyright and a "Show Debug Console" button (US-13) instead of a separate modal alert); "About XDragMover" in the menu bar opens Settings directly on that last tab. The "Excluded Windows" tab (US-15) is backed by `WindowExclusionList` (a list of regex patterns matched against `AXWindowHandling.ownerName`, consulted by `WindowMoveController`/`WindowResizeController` before starting a drag) and `WindowPickerView` (the "Add from Open Windows…" sheet, listing distinct running apps via `CGWindowListProvider`). `AppDelegate.showSettingsWindow` creates a fresh `SettingsView`/window every time none is currently open, rather than caching one forever, so the dialog always reflects live state (e.g. "Start at Login" toggled from the menu); `applicationShouldHandleReopen` (US-10) shows that same Settings window whenever the app is relaunched while already running, which is also the way back in after hiding the menu bar icon (US-11). Without `--debug`, the app has no Dock icon and no visible window at all in its idle state — the menu bar item is the only permanent UI — but the Dock icon reappears automatically while the Settings or Debug Log window is open (`AppDelegate.updateActivationPolicyForOpenWindows`) and clicking it then behaves like relaunching the app (US-10). The General tab's "Check for Updates" toggle is backed by `UpdateCheckScheduler` (owns the 5-minutes-after-launch-then-daily `Timer`s) and `UpdateChecker.swift` (the `UpdateChecking` protocol, its real `GitHubReleaseUpdateChecker` implementation querying the release repo's GitHub API, and the `SemanticVersion` comparison used to decide whether to show the "new version available" alert). The Gestures tab's "Middle-Click Dock Icon for New Instance" toggle (US-16) is backed by `MiddleClickDockEventTap`/`MiddleClickDockController` (the same event-tap/testable-controller split as move/resize/focus-follows-mouse; uses `options: .defaultTap` and consumes the click only when it lands on a resolved Dock icon, so the Dock's own icon context menu can't linger on screen alongside the new window — every other middle-click, on or off the Dock, passes through untouched), `DockIconResolving`/`SystemDockIconResolver` (resolves which app's Dock icon, if any, is at a point via `AXUIElementCopyElementAtPosition` on the system-wide accessibility element — the same technique `SystemAXWindowLocator` uses for window hit-testing, applied to the Dock's `AXDockItem` elements and their `AXURL` attribute), and `AppLaunching`/`WorkspaceAppLauncher` (opens a not-yet-running app normally; for an already-running one, searches its whole menu bar for an item titled exactly "New Window" or "New Finder Window" and presses it directly via the Accessibility API — a genuine new window in the existing process, covering Finder and most window-based apps like iTerm2 — falling back to `NSWorkspace.openApplication(at:configuration:)` with `createsNewApplicationInstance = true` only for apps exposing neither, e.g. document-based apps like TextEdit). Stage 2 of focus-follows-mouse and beyond (US-3a through US-6) are not implemented yet — see "Status" below.
- `XDragMoverTests/` – unit tests for the above, using fakes/protocols (`WindowListProviding`, `AccessibilityTrustChecking`) instead of real system state so they run reliably in CI/headless.

Note: `PRODUCT_BUNDLE_IDENTIFIER` is `de.xdragmover` (`de.xdragmover.tests` for the test target) — the reverse-DNS form of this project's own domain, xdragmover.de.

## Status

Implemented: the permission request, debug window (now also reachable on demand from the Settings window's About tab, without `--debug` — US-13), window-under-mouse detection, modifier+Left-drag window move (US-1) and modifier+Right-drag window resize (US-2) — both independently toggleable and sharing a configurable modifier key (default Command; any Command/Option/Control/Shift combination except Shift alone), stage 1 of focus-follows-mouse — input focus without raising, with a configurable dwell delay defaulting to 150ms, off by default (US-3), its on/off toggle (US-4), the menu bar status item (About, Start at Login, "Hide from Menu Bar", Settings…, Quit), a real Settings window persisting all of the above with OK/Cancel semantics (US-8, minus the System Settings.app pane half), relaunching the app while it's running to bring Settings back (US-10), hiding the menu bar icon (US-11), a Dock icon that tracks whether Settings/the Debug Log window is open rather than only ever showing in `--debug` mode, a regex-based exclusion list that permanently opts specific apps out of move/resize (US-15), an opt-in update checker (5 minutes after launch, then daily, with a download-link dialog when a newer release is found), an opt-in middle-click-Dock-icon gesture that opens a new instance of the clicked app (US-16). Not yet implemented: raising a hover-focused window after a further delay (US-3a) and its own configurable delay (rest of US-5), immediately raising a hover-focused window on click (US-5a/US-5b), a window switcher (US-9), and a per-app exclusion list for focus-follows-mouse specifically (US-12 — distinct from US-15, which only covers move/resize). Also note: none of US-1/US-2/US-3 suspend while a menu is open yet (US-6).

## Author

Ralf Hartmann <RalfHartmann@gmx.net>

## License

GNU General Public License v3.0 — see [`LICENSE`](LICENSE). This project is
dual-licensed to allow a future Apple App Store release; see
[`LICENSING.md`](LICENSING.md) for why and what that means for
contributions.
