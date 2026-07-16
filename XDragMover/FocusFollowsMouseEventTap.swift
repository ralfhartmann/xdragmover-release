import Foundation
import CoreGraphics

/// Thin, deliberately untestable glue between the real system event stream
/// and `FocusFollowsMouseController`: creates a global `CGEventTap` for raw
/// mouse movement (including drags, since a button held down elsewhere
/// still means the cursor is moving) and a repeating `Timer` that polls the
/// controller's dwell state. See `WindowMoveEventTap`'s documentation for
/// the shared rationale (Accessibility permission requirement, why this
/// isn't `@MainActor`-wide, and the `CGEventTapCallBack` refcon plumbing) —
/// it all applies here unchanged.
///
/// Unlike `WindowMoveEventTap`/`WindowResizeEventTap`, this tap never
/// consumes anything: it only observes, so every event is always passed
/// through unmodified.
final class FocusFollowsMouseEventTap {

    /// Not `private`: `AppDelegate` needs to push live `dwellDelay`
    /// changes from the Settings window (US-8) directly into it.
    let controller: FocusFollowsMouseController
    private let pollInterval: TimeInterval
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: Timer?

    // 20ms: fine enough that this adds only a small, bounded slice on top of
    // the controller's dwellDelay (150ms default) while keeping the total
    // comfortably under the 200ms feel-instant threshold — a plain Date
    // comparison every tick is cheap enough that this rate costs nothing
    // noticeable.
    init(controller: FocusFollowsMouseController, pollInterval: TimeInterval = 0.02) {
        self.controller = controller
        self.pollInterval = pollInterval
    }

    /// Creates and enables the event tap and poll timer. Safe to call
    /// multiple times; subsequent calls are a no-op while already started.
    @MainActor
    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passRetained(event) }
                let instance = Unmanaged<FocusFollowsMouseEventTap>.fromOpaque(context).takeUnretainedValue()
                return instance.handle(type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            DebugLogger.shared.log(
                "Failed to create focus-follows-mouse event tap (is Accessibility permission granted?)."
            )
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let now = Date()
                self.controller.checkDwell(now: now)
                self.controller.checkForUnwantedRaise(now: now)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Disables and tears down the event tap and poll timer. Safe to call
    /// even if not started.
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil

        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        MainActor.assumeIsolated {
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                // macOS disables a tap if its callback is judged too slow, or
                // on certain user actions. Since ours does small, fast, local
                // work only, just re-enable it.
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            default:
                controller.mouseMoved(to: event.location, at: Date())
            }
        }
        return Unmanaged.passRetained(event)
    }

    deinit {
        stop()
    }
}
