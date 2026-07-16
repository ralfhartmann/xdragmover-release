import Foundation
import CoreGraphics

/// Implements US-1 ("move a window by modifier+Left-drag"): pure
/// state-machine logic driven by raw mouse-down/dragged/up events plus
/// whether the configured gesture modifier (`AppSettings.gestureModifier`,
/// default Command — see `GestureModifier`) is held, kept free of any
/// direct `CGEventTap`/Accessibility-API calls so it can be unit tested
/// with a fake `AXWindowLocating`/`AXWindowHandling` (see
/// `WindowMoveControllerTests`). `WindowMoveEventTap` is the thin,
/// untestable glue that feeds this from real system events.
///
/// Behavior, matching the KDE Alt(+drag)-style window move this app is
/// modeled on:
/// - Only the initial mouse-down needs the modifier held; once a drag has
///   started, it continues to follow the mouse (and ends only on mouse-up)
///   even if the modifier is released mid-drag.
/// - The window is moved by the same screen-space delta the mouse has moved
///   since the initial mouse-down, computed from the original mouse-down
///   position and the window's original position (not incrementally from
///   the previous drag tick), so small per-tick rounding never accumulates.
/// - Grabbing a window to move it also raises it to the front, so a
///   background window comes forward as soon as you start dragging it.
@MainActor
final class WindowMoveController {

    private let locator: AXWindowLocating
    private let logger: DebugLogger

    private var draggedWindow: AXWindowHandling?
    private var dragStartMouseLocation: CGPoint?
    private var dragStartWindowOrigin: CGPoint?

    /// Apps protected from being moved (`AppSettings.excludedWindowPatterns`),
    /// mutable so `AppDelegate` can push live updates whenever Settings
    /// changes, matching `WindowMoveEventTap.gestureModifier`'s pattern.
    /// Defaults to an empty list (nothing excluded).
    var exclusionMatcher: WindowExclusionMatching = WindowExclusionList(patterns: [])

    // `logger` has no default value on purpose, matching MouseWindowWatcher:
    // default argument expressions are always evaluated in a nonisolated
    // context regardless of the enclosing (here, @MainActor) type, so a
    // default of `= .shared` would still hit the same "main actor-isolated
    // static property 'shared' can not be referenced from a nonisolated
    // context" problem. Callers pass `DebugLogger.shared` explicitly.
    init(locator: AXWindowLocating, logger: DebugLogger) {
        self.locator = locator
        self.logger = logger
    }

    /// Whether a drag is currently in progress (a preceding `mouseDown`
    /// found a window to move and hasn't been followed by `mouseUp` yet).
    var isDragging: Bool { draggedWindow != nil }

    /// Handles a left-mouse-down event. Returns `true` if this event should
    /// be consumed (not forwarded to whatever app is under the mouse)
    /// because it started a window move; `false` if it should pass through
    /// as normal (Command not held, or no window found at `point`).
    @discardableResult
    func mouseDown(at point: CGPoint, modifierPressed: Bool) -> Bool {
        guard modifierPressed else { return false }
        guard let window = locator.window(at: point), let origin = window.position else { return false }
        if let ownerName = window.ownerName, exclusionMatcher.isExcluded(ownerName: ownerName) {
            logger.log("Window move blocked: \"\(ownerName)\" is in the excluded list.")
            return false
        }

        draggedWindow = window
        dragStartMouseLocation = point
        dragStartWindowOrigin = origin
        window.raise()
        logger.log("Window move started.")
        return true
    }

    /// Handles a left-mouse-dragged event. Returns `true` if it was
    /// consumed (a drag is in progress and the window was repositioned);
    /// `false` if there is no drag in progress and the event should pass
    /// through untouched.
    @discardableResult
    func mouseDragged(to point: CGPoint) -> Bool {
        guard
            let window = draggedWindow,
            let startMouse = dragStartMouseLocation,
            let startOrigin = dragStartWindowOrigin
        else {
            return false
        }

        let delta = CGPoint(x: point.x - startMouse.x, y: point.y - startMouse.y)
        window.setPosition(CGPoint(x: startOrigin.x + delta.x, y: startOrigin.y + delta.y))
        return true
    }

    /// Handles a left-mouse-up event, ending any drag in progress.
    func mouseUp() {
        guard draggedWindow != nil else { return }
        draggedWindow = nil
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        logger.log("Window move ended.")
    }
}
