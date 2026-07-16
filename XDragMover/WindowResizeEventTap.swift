import Foundation
import CoreGraphics

/// Right-mouse-button counterpart to `WindowMoveEventTap`: creates a global
/// `CGEventTap` for the right mouse button and feeds it into
/// `WindowResizeController`. See `WindowMoveEventTap`'s documentation for
/// the shared rationale (Accessibility permission requirement, why this
/// isn't `@MainActor`-wide, and the `CGEventTapCallBack` refcon plumbing) —
/// it all applies here unchanged, just for `.rightMouseDown`/
/// `.rightMouseDragged`/`.rightMouseUp` instead of the left-button events.
final class WindowResizeEventTap {

    /// Not `private`: `AppDelegate` needs to push live `exclusionMatcher`
    /// changes from the Settings window directly into it, mirroring
    /// `FocusFollowsMouseEventTap.controller`.
    let controller: WindowResizeController
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// The most recent drag point not yet applied to the window, and
    /// whether a run-loop turn to apply it has already been scheduled.
    ///
    /// Resizing is much more expensive per-event than moving: most apps
    /// do a full layout pass on every `AXUIElementSetAttributeValue` size
    /// change, unlike a move's cheap pure translate. If `mouseDragged`'s
    /// (synchronous, cross-process) AX calls were made directly from the
    /// `CGEventTap` callback, a slow target app would make every raw mouse
    /// event wait for the previous one's AX round-trip to finish — visibly
    /// laggy at best, and at worst risks macOS deciding the tap itself is
    /// too slow and disabling it (`tapDisabledByTimeout`). Instead, the
    /// callback only ever records the latest point and returns immediately;
    /// the actual resize is applied on the next main run loop turn, using
    /// only the latest point, coalescing away any intermediate ones a slow
    /// target app couldn't keep up with.
    private var pendingDragPoint: CGPoint?
    private var isDragUpdateScheduled = false

    /// See `WindowMoveEventTap.gestureModifier` — same purpose, shared
    /// default and update mechanism, kept as a separate property since the
    /// two taps are otherwise fully independent.
    var gestureModifier: GestureModifier = .defaultValue

    init(controller: WindowResizeController) {
        self.controller = controller
    }

    /// Creates and enables the event tap. Safe to call multiple times;
    /// subsequent calls are a no-op while already started.
    @MainActor
    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passRetained(event) }
                let instance = Unmanaged<WindowResizeEventTap>.fromOpaque(context).takeUnretainedValue()
                return instance.handle(type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            DebugLogger.shared.log(
                "Failed to create window-resize event tap (is Accessibility permission granted?)."
            )
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Disables and tears down the event tap. Safe to call even if not
    /// started.
    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // See WindowMoveEventTap.handle for why this uses an outer `var`
        // instead of returning a value directly from `assumeIsolated`.
        var result: Unmanaged<CGEvent>?
        MainActor.assumeIsolated {
            switch type {
            case .rightMouseDown:
                let consumed = controller.mouseDown(
                    at: event.location,
                    modifierPressed: gestureModifier.isSatisfied(by: event.flags)
                )
                result = consumed ? nil : Unmanaged.passRetained(event)

            case .rightMouseDragged:
                guard controller.isResizing else {
                    result = Unmanaged.passRetained(event)
                    return
                }
                pendingDragPoint = event.location
                scheduleDragUpdateIfNeeded()
                result = nil

            case .rightMouseUp:
                pendingDragPoint = nil
                let wasResizing = controller.isResizing
                controller.mouseUp()
                result = wasResizing ? nil : Unmanaged.passRetained(event)

            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                result = Unmanaged.passRetained(event)

            default:
                result = Unmanaged.passRetained(event)
            }
        }
        return result
    }

    /// Schedules applying `pendingDragPoint` on the next main run loop
    /// turn, unless one is already scheduled — so a burst of raw drag
    /// events between now and then all collapse into a single update using
    /// only the latest point. Uses `Task { @MainActor in }` rather than
    /// `DispatchQueue.main.async` since the latter doesn't give its closure
    /// actual `@MainActor` isolation, which `controller.mouseDragged` (an
    /// isolated method, so it can log to `DebugLogger`) now requires.
    @MainActor
    private func scheduleDragUpdateIfNeeded() {
        guard !isDragUpdateScheduled else { return }
        isDragUpdateScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isDragUpdateScheduled = false
            guard let point = self.pendingDragPoint else { return }
            self.pendingDragPoint = nil
            self.controller.mouseDragged(to: point)
        }
    }

    deinit {
        stop()
    }
}
