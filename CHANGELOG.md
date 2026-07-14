# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.7.0] - 2026-07-14

### Fixed

- The menu bar icon's dropdown menu could stop opening entirely after
  launch — a click reached the icon, but nothing appeared. Root cause was
  `closeStrayWindows()` (added in 3.4.1 to fix an unrelated empty-Settings-
  window bug): its deferred cleanup pass ran after the status item was
  installed and closed the status item's own private window right along
  with the actual stray windows it was meant to catch, silently breaking
  the icon's click-to-menu handling from then on. The earlier 3.6.0 "fix"
  for this (switching to a manual target/action click handler) did not
  address the real cause and has been superseded by this one.

### Removed

- Snap-window-to-screen-edge-on-drag-release (US-20), added in 3.5.0. On a
  real multi-monitor setup, the "screen edge" a user visually aims for is
  often the seam between two adjacent monitors, which isn't a real edge in
  a per-monitor-rectangle model — the feature felt broken/unpredictable in
  practice. Pulled out to revisit later with a better notion of what counts
  as a snappable edge; the "Snap Window to Screen Edge on Release" toggle
  and its Gestures-tab setting no longer exist.

## [3.6.0] - 2026-07-14

### Added

- "Quit XDragMover" is now also available directly in the Settings window
  (previously only in the menu bar item), with the same confirmation
  prompt.

### Fixed

- The menu bar icon could sometimes not react to a click at all (no
  highlight, no menu) — most noticeable right after launch, especially as
  a login item. Caused by the app not yet being fully activated in the
  window server session; fixed by activating once before installing the
  status item.
- Edge-snap-on-release (US-20) rarely triggered in real use: the dwell
  ("stationary") check required the mouse to report the exact same
  sub-pixel position across the whole 1-second hold, which real mouse/
  trackpad input essentially never does. Small jitter no longer resets the
  dwell clock. Also increased the edge-proximity threshold from 5px to
  10px, matching typical cursor precision near a screen edge.

## [3.5.0] - 2026-07-13

### Added

- Snap a window to a screen half or quarter by releasing it near a screen
  edge while moving it (US-20): hold it within 5px of an edge for 1 second,
  then release — the middle third of the edge snaps to that edge's half,
  the two outer thirds snap to the nearest corner's quarter. Off by
  default; toggle in Settings → Gestures → "Snap Window to Screen Edge on
  Release".

## [3.4.1] - 2026-07-13

### Fixed

- An empty "XDragMover Settings" window could appear unrequested at
  launch — most reliably when launched as a login item, occasionally on
  a manual relaunch too. Caused by SwiftUI auto-showing the app's
  placeholder `Settings` scene and/or AppKit's window-state restoration
  reopening a previously-open window. Fixed by closing any window
  AppKit/SwiftUI opens on its own at launch.

## [3.4.0] - 2026-07-13

### Added

- German, Russian, and French localization. XDragMover's UI (Settings,
  menu bar, alerts) now follows the system language via a String
  Catalog; falls back to English for any other language.

### Fixed

- Removing a pattern from Settings' "Excluded Windows" tab could crash
  the app when it wasn't the last one in the list — a stale array index
  captured by another, still-visible row's text field. Live-reproduced
  and fixed.

## [3.3.1] - 2026-07-13

### Changed

- Bundle identifier changed from the placeholder `com.example.XDragMover`
  to `de.xdragmover` (`de.xdragmover.tests` for the test target) — the
  reverse-DNS form of this project's own domain, xdragmover.de. Anyone
  with a previous build installed will need to re-grant Accessibility
  access once, since macOS ties that permission to the bundle identifier.

### Fixed

- `make dmg` failed signing the `.dmg` container on the GitLab Runner
  ("The following argument was not expected: --timestamp") because its
  non-interactive PATH resolved a different, unrelated `codesign`-named
  binary ahead of Apple's real one — now calls `/usr/bin/codesign`
  explicitly, sidestepping PATH resolution entirely.

## [3.3.0] - 2026-07-13

### Added

- Middle-click an app's Dock icon to open a new window/instance of it
  (US-16). Off by default; toggle in Settings → Gestures → "Middle-Click
  Dock Icon for New Instance".

### Changed

- Restored the app icon (Dock/Finder/`.app` bundle), using a new design
  (`assets/logo.png`) in place of the one removed in 3.1.0 over trademark
  concerns.
- Release builds are now signed with a paid "Developer ID Application"
  identity and notarized+stapled, so a machine that's never run this app
  before no longer sees Gatekeeper's "unidentified developer" warning —
  see `DEVELOPMENT.md`'s "Notarization" section.

### Fixed

- Middle-clicking Finder's Dock icon while Finder was already running
  (i.e. essentially always) failed outright with "The application
  "Finder.app" can't be opened." instead of opening a new window (US-16).
  Middle-clicking an already-running app's Dock icon now presses that
  app's own "New Window" menu item directly via the Accessibility API
  when it has one (covers Finder and most window-based apps, e.g.
  iTerm2), rather than trying to force a new instance; apps without such
  a menu item (e.g. document-based apps like TextEdit) still open a new
  instance as before.
- Middle-clicking iTerm2's Dock icon spawned an entire new heavyweight
  process (its own shell/session daemon) per click instead of just a new
  window in the app already open (US-16); fixed by the same "New Window"
  menu item press described above.
- Middle-clicking a Dock icon could leave the Dock's own icon context
  menu open on screen alongside the new window/instance (US-16); the
  middle-click is now consumed when this feature acts on it.

## [3.2.0] - 2026-07-11

### Added

- Optional update checker (Settings → General → "Check for Updates", off
  by default). When enabled, checks the public release repo for a newer
  version 5 minutes after launch and once a day thereafter; if one is
  found, shows a dialog with a "Download" button linking straight to the
  new `.dmg`.

## [3.1.0] - 2026-07-09

### Changed

- Temporarily removed the custom app icon added in 3.0.0 (its design
  incorporated the Apple logo silhouette, a possible trademark concern);
  the app now falls back to the default macOS-generated icon until a
  replacement design is ready.

## [3.0.0] - 2026-07-09

### Added

- Excluded Windows (Settings): a list of regex patterns matched against an
  app's name — any app in the list can never be moved or resized. Entries
  are normally added via "Add from Open Windows…", a picker listing
  currently-open apps that generates an exact-match pattern (e.g.
  `^Calculator$`) for the one you pick; each pattern stays editable as
  plain text afterward ("Add Pattern" adds a blank row), with invalid
  regexes shown in red without blocking anything.
- Debug Console: a "Scroll Lock" button. Off (default, persisted) keeps the
  console scrolled to the newest line as new entries arrive, matching prior
  behavior. On lets you scroll freely through history without being pulled
  back to the bottom on every new log line.
- Focus Follows Mouse now shows a one-time warning ("Focus Follows Mouse Is
  Experimental…", with a "Don't show this again" checkbox) the first time
  it's turned on in Settings, explaining that it relies on an undocumented
  macOS mechanism and can behave unreliably in some apps. README also now
  calls this out explicitly instead of only implying it. The Focus Follows
  Mouse tab additionally shows this warning permanently (not just once),
  so it's visible every time you open that tab, not only on first use.

### Changed

- Project renamed: **KDEMoverSizerMacOS** → **XDragMover**. Affects the
  GitLab project slug/remote, the Xcode project/targets/scheme, both bundle
  identifiers (now `com.example.XDragMover`/`...Tests`), and every
  source/doc/script reference. As with the previous rename (2.0.0), the
  bundle identifier change means existing installs lose their persisted
  Settings (new `UserDefaults` domain) and need to re-grant Accessibility
  permission once after updating. Breaking change for existing installs,
  hence a major version bump when this is released.
- App icon replaced with a new design combining the rainbow Apple logo
  silhouette, the X.Org "X" (from `assets/X.Org_Logo.png`), and the
  move-arrows cross, regenerated at all `mac` idiom sizes (16–1024px).
- Settings window reorganized into tabs (General, Gestures, Excluded
  Windows, Focus Follows Mouse, About) via a segmented control, instead of
  one long scrolling list of every section stacked vertically.
- "About XDragMover" (menu bar) now opens the Settings window's About tab
  (last tab) instead of a separate modal alert — the "Show Debug Console"
  button moved there with it. Clicking "About" while Settings is already
  open on a different tab switches it to About, rather than leaving it on
  whatever tab it happened to be showing.
- Licensing: added `LICENSE` (GPLv3) and `LICENSING.md` explaining the
  dual-licensing arrangement that keeps a future Apple App Store release
  possible; credited Ralf Hartmann as author in the README and the app's
  copyright string.

### Fixed

- Debug Console's "Scroll Lock" button looked the same (a plain neutral-grey
  background) whether on or off, only the tiny padlock glyph changed — easy
  to miss, so it looked inactive even while engaged. It now fills with the
  accent color while locked, matching how other macOS toolbar toggle
  buttons indicate an active/pressed state.
- Settings window: the first item ("Start at Login") and the Cancel/OK
  buttons had shrunk to sit flush against the window's top/bottom edges as
  more sections were added over time, since everything shared one
  fixed-height, non-scrolling stack. The settings sections now scroll
  independently inside the window, with Cancel/OK pinned in an always-fully-
  padded footer below a divider — both ends keep their intended spacing
  regardless of how much content is above.
- Focus-follows-mouse delay slider was hard to land on a precise value —
  its 10ms step packed 95 discrete positions into a narrow drag control,
  easy to overshoot. Added a `Stepper` next to it for exact, click-or-hold
  ±10ms adjustment; the slider stays for fast coarse positioning.
- Move/resize (and focus-follows-mouse) silently stayed broken for an
  entire run if Accessibility permission wasn't granted yet at the exact
  moment of launch — a common race with the system prompt, and guaranteed
  after any bundle identifier change (e.g. the rename above), since that
  always requires granting access again from scratch. The event taps only
  ever attempted to start once, at launch; granting access moments later
  was never noticed, even though the debug window's own status indicator
  correctly showed "granted". `AccessibilityPermissionManager` now reports
  when trust changes (`onTrustedChange`), and the app retries starting
  every enabled tap when it does — granting access at any point now makes
  move/resize/focus-follows-mouse work immediately, no relaunch needed.

## [2.2.0] - 2026-07-06

### Added

- "Quit" now asks for confirmation ("Quit KDEMoverSizerMacOS?" / "Window
  move, resize, and focus-follows-mouse will stop working until you
  relaunch it." with Quit/Cancel buttons) instead of terminating
  immediately — accidentally hitting Quit or its `⌘Q` key equivalent no
  longer silently kills window move/resize with no undo.

## [2.1.0] - 2026-07-06

### Added

- Real app icon (Dock/Finder/`.app` bundle): a `KDEMoverSizerMacOS/Assets.xcassets/AppIcon.appiconset` wired into the Xcode project via `ASSETCATALOG_COMPILER_APPICON_NAME`, generated at all required
  `mac` idiom sizes (16–1024px) from `assets/KDE_Window-Sizer-for-macOS_256px.png`. Previously the app had no custom icon at all. The menu bar status item icon (an SF Symbol) is unchanged.

## [2.0.0] - 2026-07-06

### Changed

- Project renamed: **KDESizeMoverMac** → **KDEMoverSizerMacOS**. Affects
  the GitLab project slug/remote, the Xcode project/targets/scheme, both
  bundle identifiers, and every source/doc/script reference. The bundle
  identifier change means existing installs lose their persisted
  Settings (new `UserDefaults` domain) and need to re-grant Accessibility
  permission once after updating — a one-time cost of the rename, not a
  regression. Breaking change for existing installs, hence the major
  version bump.

## [1.1.1] - 2026-07-06

### Fixed

- The Settings and Debug Log windows didn't reliably come to the actual
  foreground — as a menu-bar-only (`.accessory`) app, KDEMoverSizerMacOS is
  never the active app, so `makeKeyAndOrderFront` alone could leave either
  window behind whatever other app was actually active. Both now call
  `NSApp.activate(ignoringOtherApps: true)` first, matching the fix the
  About dialog already needed for the same reason.
- The Dock icon now appears exactly while the Settings or Debug Log
  window is open (in addition to always showing when launched with
  `--debug`), instead of never appearing outside `--debug` mode. This
  also means clicking the Dock icon while it's showing brings Settings
  back to front, the same way relaunching the app already does.

## [1.1.0] - 2026-07-06

### Added

- Real Settings window (US-8): "Start at Login", enable/disable
  focus-follows-mouse (US-4), and its dwell delay (partial US-5) are all
  now changeable from a proper settings dialog instead of only via code
  defaults. Persisted with `UserDefaults` (survives uninstalling the app)
  and versioned for future migrations.
- "Show Debug Console" button in the About dialog, so the debug log
  window can be opened without launching with `--debug`.
- Mitigation for apps (confirmed: Firefox) that raise themselves after
  focus-follows-mouse gives them input — see `USER_STORIES.md` and
  `DEVELOPMENT.md`'s "Optional: yabai-assisted window-order correction".
- `BACKLOG.md` and US-9 (window switcher) added to `USER_STORIES.md`.
- Independent Settings toggles for window move (US-1) and window resize
  (US-2), so either gesture can be disabled on its own.
- Configurable move/resize modifier key (`GestureModifier`): any
  combination of Command/Option/Control/Shift, Shift alone excluded,
  replacing the previously hardcoded `⌘`. Default remains Command.
- OK/Cancel buttons on the Settings window: OK closes it keeping changes;
  Cancel reverts every setting (including "Start at Login") to what it
  was when the dialog was opened.
- New defaults: focus-follows-mouse now off by default (was on); move and
  resize remain on by default.
- `DEVELOPMENT.md`: a "Changing existing tests" policy, and a new
  `TEST_CHANGELOG.md` tracking modifications to existing tests specifically
  (separate from this file, which only covers user-facing behavior).
- Relaunching the app while it's already running (e.g. double-clicking it
  again in Finder/Launchpad) now shows the Settings window instead of
  doing nothing (US-10).
- "Hide from Menu Bar" (US-11): a menu item and matching Settings checkbox
  that hide the status item entirely; relaunching the app (US-10) is the
  way to bring Settings back and turn it off again.
- `USER_STORIES.md`: documented a new, not-yet-implemented US-12 — a
  per-app exclusion list for focus-follows-mouse.

### Fixed

- Toggling "Start at Login" from the menu bar item no longer left the
  Settings dialog's checkbox stale — the Settings window is now recreated
  fresh each time it's opened instead of being cached for the entire app
  session.
- The Settings window's content had outgrown its fixed size, clipping the
  top ("Start at Login") and bottom (OK/Cancel) rows flush against the
  window edges. Its frame is now generously sized against the content's
  actually-measured minimum height.

## [1.0.1] - 2026-07-05

### Added

- US-3: focus-follows-mouse, stage 1 — the window under the mouse receives
  real keyboard/mouse input after a 150ms dwell, without being raised
  above other windows. Implemented via a private/undocumented WindowServer
  mechanism ported from the yabai window manager, since the public
  `AXFocused` attribute alone doesn't redirect input across apps; falls
  back to `AXFocused` if that mechanism is ever unavailable.

### Fixed

- Focus-follows-mouse didn't reliably target the correct window when its
  app already had multiple windows open — restored yabai's same-app
  window-switch handling that the initial port had dropped.
- Focus-follows-mouse activation latency reduced from up to 350ms to
  under 200ms (150ms dwell delay + 20ms poll interval, both down from
  300ms/50ms).
- Corrected stale notes in `USER_STORIES.md` (menu bar item list was
  missing "About"; the "doesn't suspend while a menu is open" gap didn't
  mention US-3).

## [1.0.0] - 2026-07-05

### Added

- "About" menu item: a modal alert with app name, version, build, and
  copyright — not AppKit's shared standard about panel, which testing
  showed doesn't reliably come to the front for a menu-bar-only
  (`.accessory`) app.

### Fixed

- `Info.plist` now reads `CFBundleShortVersionString`/`CFBundleVersion`
  from build settings instead of hardcoded, stale values.

## [0.1.8] - 2026-07-05

No functional changes (version bump only).

## [0.1.7] - 2026-07-05

### Added

- US-1: move any window with `⌘`+Left-drag.
- US-2: resize any window with `⌘`+Right-drag, anchored at the nearest
  corner.
- Menu bar status item (Start at Login, Quit) and hidden Dock icon
  outside `--debug` mode.
- Debug logging of move/resize start/end events (and, for resize, which
  corner was grabbed).
- `make install`, `make uninstall`, and `make dmg` targets.

### Fixed

- Xcode signing: select a real Apple Development Team for Automatic
  signing.
- App quit unexpectedly when toggling "Start at Login".
- App quit unexpectedly when interacting with the menu bar item's own
  dropdown menu (non-debug mode).
- Resize responsiveness: skip redundant Accessibility API calls and
  coalesce drag updates onto the main run loop.
- `make dmg`: the mounted volume was invisible to Finder (first due to
  `-nobrowse`, then due to a custom `-mountpoint` outside `/Volumes/`).

## [0.1.6] - 2026-07-05

### Fixed

- Package code signing: a self-signed certificate doesn't satisfy TCC's
  Accessibility permission checks; switched to Team-based signing.

## [0.1.5] - 2026-07-05

No functional changes (version bump only).

## [0.1.4] - 2026-07-05

### Added

- CI: build a package on every push to `dev`, versioned with the commit
  SHA.

### Docs

- Documented App Translocation as a cause of repeated permission prompts.

## [0.1.3] - 2026-07-05

### Fixed

- Released packages re-prompted for Accessibility access on every
  install.

## [0.1.2] - 2026-07-05

### Fixed

- `make package`/`make release` failed to build due to a temp-directory
  cleanup issue.

## [0.1.1] - 2026-07-05

### Added

- Initial project skeleton: Accessibility permission request, debug
  window, window-under-mouse detection, unit tests.
- `Makefile` (`build`/`test`/`clean`/`all`).
- `main`/`dev`/`feature`/`bugfix` git branching workflow with a scripted
  release process (`make release`).
- GitLab CI pipeline (test on push to `dev`, release on push to `main`).
- `make run` and the `--debug` flag.

### Fixed

- Accessibility permission re-prompting on every rebuild/run.
- Startup side effects (permission prompt, event taps) running when the
  app is hosted by XCTest.
