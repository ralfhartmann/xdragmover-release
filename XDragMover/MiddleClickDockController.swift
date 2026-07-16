import Foundation

/// Testable logic behind US-16: given where a middle-click landed, decides
/// whether it was on an app's Dock icon and, if so, opens a new instance
/// of that app. Kept separate from `MiddleClickDockEventTap` so this
/// decision logic can be unit tested with fakes, matching this codebase's
/// EventTap-vs-Controller split (e.g. `WindowMoveEventTap`/
/// `WindowMoveController`).
@MainActor
final class MiddleClickDockController {
    private let dockIconResolver: DockIconResolving
    private let appLauncher: AppLaunching
    private let logger: DebugLogger

    init(dockIconResolver: DockIconResolving, appLauncher: AppLaunching, logger: DebugLogger) {
        self.dockIconResolver = dockIconResolver
        self.appLauncher = appLauncher
        self.logger = logger
    }

    /// Returns whether the point was over an app's Dock icon (and a new
    /// instance was launched) — the caller never needs to act on this
    /// (the tap always lets the underlying middle-click event pass
    /// through untouched either way), but it's useful for tests.
    @discardableResult
    func middleMouseDown(at point: CGPoint) -> Bool {
        guard let url = dockIconResolver.appURL(at: point) else { return false }
        logger.log("Middle-click on Dock icon (\(url.lastPathComponent)) — opening a new window/instance.")
        appLauncher.launchNewInstance(at: url)
        return true
    }
}
