import AppKit
import ApplicationServices

/// Abstraction over "open a new instance of the app at this URL", so
/// `MiddleClickDockController` can be unit tested without really
/// launching an application — mirrors this codebase's existing
/// protocol-plus-fake split (e.g. `UpdateChecking`).
protocol AppLaunching {
    func launchNewInstance(at url: URL)
}

/// Real implementation. For an app that isn't running yet, this is a plain
/// launch — its own default window(s) already give "a" window, nothing
/// more is needed.
///
/// For an app that IS already running, this used to unconditionally pass
/// `createsNewApplicationInstance = true` to `NSWorkspace.openApplication`
/// — the same Launch-Services-level flag underlying macOS's own, per-app-
/// inconsistently-supported ⌘+click-Dock-icon-for-new-window convention.
/// Live testing found two real problems with that as the *general*
/// mechanism, not just Finder:
///
/// - Finder (`LSMultipleInstancesProhibited`) fails outright while already
///   running ("The application "Finder.app" can't be opened." —
///   live-reproduced), rather than doing nothing.
/// - iTerm2 doesn't fail, but forcing a genuinely new *process* per click
///   is the wrong behavior for apps like it: each click spawned an entire
///   new heavyweight instance (its own shell/session daemon and helper
///   processes, confirmed live via a dozen redundant `iTerm2` processes
///   accumulating in `ps aux`) instead of simply a new default window in
///   the app the user already has open — not what "open a new window"
///   should mean for a single-instance-style app.
///
/// This now presses the app's own "New Window" menu item directly via
/// `AXUIElementPerformAction`, searching the whole menu bar for an exact
/// title match — `"New Window"` covers ordinary window-based apps (e.g.
/// iTerm2's Shell > New Window, confirmed live), and `"New Finder
/// Window"` covers Finder specifically (its own name for the same
/// concept). This is a genuine new window in the *existing* process,
/// with none of the above problems, and — since it never posts a
/// synthetic event — sidesteps a related problem found with an earlier,
/// abandoned attempt: a process with any active `CGEventTap` (this app
/// always has at least the move/resize taps running) can't reliably
/// inject synthetic keyboard events system-wide, so synthesizing Cmd+N
/// wasn't a viable general mechanism either (isolated by running the
/// identical Cmd+N-posting code both with and without an unrelated,
/// otherwise-inert `.listenOnly` tap active in the same process — it
/// silently did nothing with a tap active, worked immediately with none).
///
/// Only apps that expose neither menu item (e.g. document-based apps like
/// TextEdit, which use "New" rather than "New Window") fall back to
/// `createsNewApplicationInstance = true` — a new lightweight process is
/// harmless for that class of app, unlike iTerm2's heavier one.
struct WorkspaceAppLauncher: AppLaunching {
    /// Menu item titles that mean "open a new default window", checked as
    /// an exact (not partial) match against every item in the app's menu
    /// bar, in this priority order.
    private static let newWindowMenuItemTitles = ["New Window", "New Finder Window"]

    func launchNewInstance(at url: URL) {
        guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == url }) else {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                guard let error else { return }
                // The completion handler isn't guaranteed to run on the main
                // thread; DebugLogger.shared is @MainActor (same fix needed
                // for UpdateCheckScheduler's fetch-failure logging).
                DispatchQueue.main.async {
                    DebugLogger.shared.log("Failed to open \(url.path): \(error.localizedDescription)")
                }
            }
            return
        }

        running.activate()
        let processID = running.processIdentifier
        DispatchQueue.main.async {
            if !Self.pressNewWindowMenuItem(processID: processID) {
                Self.launchAdditionalInstance(at: url)
            }
        }
    }

    /// Searches every top-level menu for an item exactly titled
    /// `"New Window"` or `"New Finder Window"` and presses it. Returns
    /// whether a matching item was found (and pressed).
    @MainActor
    private static func pressNewWindowMenuItem(processID: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(processID)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarRef
        else { return false }
        // swiftlint:disable:next force_cast — kAXMenuBarAttribute is
        // always an AXUIElement when present.
        let menuBar = menuBarRef as! AXUIElement

        for menuBarItem in axChildren(of: menuBar) {
            guard let menu = axChildren(of: menuBarItem).first else { continue }
            for item in axChildren(of: menu) {
                if let title = axTitle(of: item), newWindowMenuItemTitles.contains(title) {
                    AXUIElementPerformAction(item, kAXPressAction as CFString)
                    return true
                }
            }
        }
        return false
    }

    private static func launchAdditionalInstance(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                DebugLogger.shared.log("Failed to open a new instance at \(url.path): \(error.localizedDescription)")
            }
        }
    }

    private static func axChildren(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func axTitle(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
