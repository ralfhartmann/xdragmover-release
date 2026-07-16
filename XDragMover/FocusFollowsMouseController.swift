import Foundation
import CoreGraphics

/// Implements US-3 (stage 1 of focus-follows-mouse): once the mouse cursor
/// has been stationary over a point for `dwellDelay`, the window there is
/// given input focus via `AXWindowHandling.focus()` — deliberately without
/// raising it (see that method's doc comment for why this can only ever be
/// best-effort on macOS).
///
/// Pure state-machine logic, mirroring `WindowMoveController`'s split
/// between this testable core and `FocusFollowsMouseEventTap`'s untestable
/// `CGEventTap`/`Timer` glue. Time is passed in explicitly (`at`/`now`
/// parameters) rather than read from the system clock internally, so tests
/// can drive the dwell timer deterministically without real delays.
///
/// Stage 2 (auto-raise after a further dwell, US-3a) and the on/off toggle
/// (US-4) are separate, not-yet-implemented stories. `dwellDelay` itself
/// (US-5) is already a mutable property rather than a baked-in constant,
/// specifically so a future settings UI can adjust it live without needing
/// to recreate this controller — there just isn't one yet.
///
/// Also guards against apps (confirmed: Firefox) that raise their own
/// window in reaction to receiving real keyboard input shortly after being
/// focused this way — see `YabaiWindowOrder`'s doc comment for the full
/// story and why this is only a best-effort, opt-in (requires yabai)
/// correction rather than a true prevention.
@MainActor
final class FocusFollowsMouseController {

    private let locator: AXWindowLocating
    private let logger: DebugLogger
    private let windowListProviding: WindowListProviding
    private let windowOrderRestoring: WindowOrderRestoring

    /// How long to keep correcting an unwanted self-raise after focusing a
    /// window — apps that do this tend to do it in reaction to a keystroke,
    /// which could come at any point after the dwell fires, not just
    /// immediately.
    static let raiseGuardDuration: TimeInterval = 5

    /// How long the cursor must stay stationary before the window under it
    /// is focused. Settable at any time — a change takes effect on the
    /// next `checkDwell` poll, including for a dwell period already in
    /// progress. Default (150ms) keeps end-to-end activation latency
    /// (dwell + poll interval, see `FocusFollowsMouseEventTap`) comfortably
    /// under the 200ms feel-instant threshold.
    var dwellDelay: TimeInterval

    private var lastMovementPoint: CGPoint?
    private var lastMovementTime: Date?

    /// Whether the current stationary period (since `lastMovementTime`) has
    /// already triggered a focus attempt — set once `checkDwell` acts on it
    /// (whether or not a window was actually found there), so a still mouse
    /// doesn't repeatedly re-query/re-focus on every subsequent poll tick.
    private var hasHandledCurrentDwell = false

    /// Tracks a window we recently focused that wasn't already the
    /// frontmost on-screen window, so `checkForUnwantedRaise` can tell
    /// "this app raised itself" apart from "this window was already in
    /// front, nothing to protect".
    private struct RaiseGuard {
        let targetWindowNumber: Int
        let windowToRestore: WindowInfo
        let deadline: Date
    }
    private var raiseGuard: RaiseGuard?

    // See WindowMoveController's init for why `logger` has no default value.
    init(
        locator: AXWindowLocating,
        logger: DebugLogger,
        dwellDelay: TimeInterval = 0.15,
        windowListProviding: WindowListProviding = CGWindowListProvider(),
        windowOrderRestoring: WindowOrderRestoring = YabaiWindowOrder()
    ) {
        self.locator = locator
        self.logger = logger
        self.dwellDelay = dwellDelay
        self.windowListProviding = windowListProviding
        self.windowOrderRestoring = windowOrderRestoring
    }

    /// Call on every raw mouse-move/drag sample. Resets the dwell clock
    /// whenever the point actually changed; repeated reports of the same
    /// point (e.g. redundant events) do not restart it.
    func mouseMoved(to point: CGPoint, at time: Date) {
        guard point != lastMovementPoint else { return }
        lastMovementPoint = point
        lastMovementTime = time
        hasHandledCurrentDwell = false
    }

    /// Call periodically (e.g. from a repeating timer). If the cursor has
    /// been stationary at the last-seen point for at least `dwellDelay`,
    /// and this stationary period hasn't already been handled, focuses the
    /// window at that point (if any).
    func checkDwell(now: Date) {
        // The `- 0.0001` tolerance absorbs floating-point rounding in the
        // `Date` arithmetic (e.g. `addingTimeInterval`/`timeIntervalSince`
        // round-tripping a delay like 0.3 doesn't always land on exactly
        // 0.3), so a poll landing right at the boundary isn't missed by a
        // fraction of a millisecond — immaterial in practice since real
        // callers pass wall-clock time, not a value engineered to land
        // exactly on the boundary.
        guard
            !hasHandledCurrentDwell,
            let lastMovementPoint,
            let lastMovementTime,
            now.timeIntervalSince(lastMovementTime) >= dwellDelay - 0.0001
        else {
            return
        }

        hasHandledCurrentDwell = true
        guard let window = locator.window(at: lastMovementPoint) else { return }

        let windowsBeforeFocus = windowListProviding.currentWindows()
        window.focus()
        logger.log("Focus-follows-mouse: focused window under mouse.")
        armRaiseGuard(for: window, windowsBeforeFocus: windowsBeforeFocus, now: now)
    }

    /// Sets up `raiseGuard` if `window` wasn't already the frontmost
    /// on-screen (normal-layer) window — i.e. there's something to protect
    /// against it wrongly becoming frontmost as a side effect of receiving
    /// input. Matches `window` against `windowsBeforeFocus` by bounds,
    /// since `AXWindowHandling` doesn't expose a `CGWindowID` directly.
    private func armRaiseGuard(for window: AXWindowHandling, windowsBeforeFocus: [WindowInfo], now: Date) {
        guard
            let position = window.position,
            let size = window.size,
            let targetInfo = windowsBeforeFocus.first(where: {
                $0.bounds.origin == position && $0.bounds.size == size
            }),
            let previousFront = windowsBeforeFocus.first(where: { $0.layer == WindowUnderMouseFinder.normalWindowLayer }),
            previousFront.windowNumber != targetInfo.windowNumber
        else {
            raiseGuard = nil
            return
        }
        raiseGuard = RaiseGuard(
            targetWindowNumber: targetInfo.windowNumber,
            windowToRestore: previousFront,
            deadline: now.addingTimeInterval(Self.raiseGuardDuration)
        )
    }

    /// Call periodically, alongside `checkDwell`. If a window recently
    /// focused by `checkDwell` has, within `raiseGuardDuration`, become the
    /// actual frontmost on-screen window despite not having been before we
    /// focused it, undoes that by asking `windowOrderRestoring` to put
    /// whatever window WAS frontmost back — see this class's and
    /// `YabaiWindowOrder`'s doc comments for why this only ever corrects
    /// after the fact, and only where `windowOrderRestoring` is functional
    /// (a no-op there means a silent no-op here too).
    func checkForUnwantedRaise(now: Date) {
        guard let raiseGuard else { return }
        guard now < raiseGuard.deadline else {
            self.raiseGuard = nil
            return
        }

        let windows = windowListProviding.currentWindows()
        guard
            let front = windows.first(where: { $0.layer == WindowUnderMouseFinder.normalWindowLayer }),
            front.windowNumber == raiseGuard.targetWindowNumber
        else {
            return
        }

        windowOrderRestoring.raiseWithoutActivating(windowID: CGWindowID(raiseGuard.windowToRestore.windowNumber))
        logger.log("Focus-follows-mouse: undid an unwanted raise by \(front.ownerName).")
        self.raiseGuard = nil
    }
}
