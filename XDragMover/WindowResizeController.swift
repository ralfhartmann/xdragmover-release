import Foundation
import CoreGraphics

/// Implements US-2 ("resize a window by modifier+Right-drag, from whichever
/// corner is nearest the click point"): pure state-machine logic, mirroring
/// `WindowMoveController`'s split between this testable core and
/// `WindowResizeEventTap`'s untestable `CGEventTap` glue.
///
/// Behavior:
/// - Only the initial mouse-down needs the configured gesture modifier held
///   (Right button); as with move, the resize continues to follow the mouse
///   until mouse-up even if the modifier is released mid-drag.
/// - The corner of the window nearest the click point becomes the "grabbed"
///   corner; the diagonally opposite corner stays fixed in place for the
///   whole drag, exactly as if the user had grabbed and were dragging that
///   nearest corner (per US-2's acceptance criteria).
/// - The grabbed corner's new position is computed from the mouse's
///   on-screen delta since mouse-down, the same way `WindowMoveController`
///   computes a moved window's new origin — not from the mouse's absolute
///   position — so the window doesn't jump if the initial click wasn't
///   exactly on the corner.
/// - Width/height are clamped to `minimumSize` by holding the *moving* edge
///   back, never by moving the fixed corner, so the window can never be
///   dragged through itself or collapse to a negative size.
@MainActor
final class WindowResizeController {

    /// Floor on width/height so a resize can never collapse a window to
    /// nothing (or invert it) if the mouse is dragged past the opposite,
    /// fixed corner.
    static let minimumSize = CGSize(width: 20, height: 20)

    private let locator: AXWindowLocating
    private let logger: DebugLogger

    private var resizedWindow: AXWindowHandling?
    private var dragStartMouseLocation: CGPoint?

    /// Whether the grabbed corner is on the window's left (vs. right) edge,
    /// and top (vs. bottom) edge — together these identify which corner was
    /// grabbed and, equivalently, which edges move vs. stay fixed.
    private var grabbedIsLeftEdge: Bool?
    private var grabbedIsTopEdge: Bool?

    /// The screen-space coordinate of the fixed (non-moving) edge on each
    /// axis, captured once at mouse-down.
    private var fixedX: CGFloat?
    private var fixedY: CGFloat?

    /// The grabbed corner's own original coordinate on each axis, captured
    /// once at mouse-down, so drags are computed via mouse delta rather
    /// than absolute mouse position.
    private var grabbedEdgeStartX: CGFloat?
    private var grabbedEdgeStartY: CGFloat?

    /// The origin/size last actually written via `setPosition`/`setSize`,
    /// so unchanged values are never re-applied. `AXUIElementSetAttributeValue`
    /// is a synchronous cross-process call that can be noticeably slow —
    /// worse, most apps also do a full layout pass on every resize (unlike
    /// a move, which is a cheap pure translate), which is the main reason
    /// resize feels heavier than move to begin with. Grabbing a corner
    /// where one axis' edge is fixed (e.g. the very common bottom-right
    /// corner never moves the origin at all) would otherwise still repeat
    /// an identical, pointless `setPosition` call on every single drag
    /// tick; skipping it directly cuts the number of AX calls per corner
    /// in half for that (most common) case, and avoids repeats once a
    /// drag has been clamped to `minimumSize`.
    private var lastAppliedOrigin: CGPoint?
    private var lastAppliedSize: CGSize?

    /// Apps protected from being resized (`AppSettings.excludedWindowPatterns`),
    /// mutable so `AppDelegate` can push live updates whenever Settings
    /// changes, matching `WindowResizeEventTap.gestureModifier`'s pattern.
    /// Defaults to an empty list (nothing excluded).
    var exclusionMatcher: WindowExclusionMatching = WindowExclusionList(patterns: [])

    // See WindowMoveController's init for why `logger` has no default value.
    init(locator: AXWindowLocating, logger: DebugLogger) {
        self.locator = locator
        self.logger = logger
    }

    /// Whether a resize is currently in progress.
    var isResizing: Bool { resizedWindow != nil }

    /// Handles a right-mouse-down event. Returns `true` if this event
    /// started a resize (and should be consumed); `false` if it should pass
    /// through untouched (Command not held, or no window at `point`).
    @discardableResult
    func mouseDown(at point: CGPoint, modifierPressed: Bool) -> Bool {
        guard modifierPressed else { return false }
        guard
            let window = locator.window(at: point),
            let origin = window.position,
            let size = window.size
        else {
            return false
        }
        if let ownerName = window.ownerName, exclusionMatcher.isExcluded(ownerName: ownerName) {
            logger.log("Window resize blocked: \"\(ownerName)\" is in the excluded list.")
            return false
        }

        let isLeft = point.x < origin.x + size.width / 2
        let isTop = point.y < origin.y + size.height / 2

        resizedWindow = window
        dragStartMouseLocation = point
        grabbedIsLeftEdge = isLeft
        grabbedIsTopEdge = isTop
        fixedX = isLeft ? origin.x + size.width : origin.x
        fixedY = isTop ? origin.y + size.height : origin.y
        grabbedEdgeStartX = isLeft ? origin.x : origin.x + size.width
        grabbedEdgeStartY = isTop ? origin.y : origin.y + size.height
        lastAppliedOrigin = origin
        lastAppliedSize = size
        window.raise()
        logger.log("Window resize started (corner: \(Self.cornerDescription(isLeft: isLeft, isTop: isTop))).")
        return true
    }

    /// Handles a right-mouse-dragged event. Returns `true` if it was
    /// consumed (a resize is in progress and the window was resized);
    /// `false` if there is no resize in progress.
    @discardableResult
    func mouseDragged(to point: CGPoint) -> Bool {
        guard
            let window = resizedWindow,
            let startMouse = dragStartMouseLocation,
            let isLeft = grabbedIsLeftEdge,
            let isTop = grabbedIsTopEdge,
            let fixedX,
            let fixedY,
            let grabbedEdgeStartX,
            let grabbedEdgeStartY
        else {
            return false
        }

        let delta = CGPoint(x: point.x - startMouse.x, y: point.y - startMouse.y)
        let movingX = grabbedEdgeStartX + delta.x
        let movingY = grabbedEdgeStartY + delta.y

        let (originX, width) = Self.resizedAxis(
            fixed: fixedX,
            moving: movingX,
            movingIsMinEdge: isLeft,
            minimumLength: Self.minimumSize.width
        )
        let (originY, height) = Self.resizedAxis(
            fixed: fixedY,
            moving: movingY,
            movingIsMinEdge: isTop,
            minimumLength: Self.minimumSize.height
        )

        let newSize = CGSize(width: width, height: height)
        if newSize != lastAppliedSize {
            window.setSize(newSize)
            lastAppliedSize = newSize
        }

        let newOrigin = CGPoint(x: originX, y: originY)
        if newOrigin != lastAppliedOrigin {
            window.setPosition(newOrigin)
            lastAppliedOrigin = newOrigin
        }

        return true
    }

    /// Handles a right-mouse-up event, ending any resize in progress.
    func mouseUp() {
        if isResizing {
            logger.log("Window resize ended.")
        }
        resizedWindow = nil
        dragStartMouseLocation = nil
        grabbedIsLeftEdge = nil
        grabbedIsTopEdge = nil
        fixedX = nil
        fixedY = nil
        grabbedEdgeStartX = nil
        grabbedEdgeStartY = nil
        lastAppliedOrigin = nil
        lastAppliedSize = nil
    }

    /// Computes one axis (x or y) of the new origin/size, given the fixed
    /// edge's coordinate and the moving edge's desired new coordinate.
    /// `movingIsMinEdge` is `true` when the moving edge is the smaller-
    /// coordinate one (left/top) and the fixed edge is the larger-
    /// coordinate one (right/bottom) — i.e. `grabbedIsLeftEdge`/
    /// `grabbedIsTopEdge`. The moving edge (never the fixed one) is clamped
    /// so the resulting length never drops below `minimumLength`.
    private static func resizedAxis(
        fixed: CGFloat,
        moving: CGFloat,
        movingIsMinEdge: Bool,
        minimumLength: CGFloat
    ) -> (origin: CGFloat, length: CGFloat) {
        if movingIsMinEdge {
            let clampedMoving = min(moving, fixed - minimumLength)
            return (origin: clampedMoving, length: fixed - clampedMoving)
        } else {
            let clampedMoving = max(moving, fixed + minimumLength)
            return (origin: fixed, length: clampedMoving - fixed)
        }
    }

    private static func cornerDescription(isLeft: Bool, isTop: Bool) -> String {
        "\(isTop ? "top" : "bottom")-\(isLeft ? "left" : "right")"
    }
}
