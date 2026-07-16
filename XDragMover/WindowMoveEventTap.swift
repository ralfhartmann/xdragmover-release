import Foundation
import CoreGraphics

/// Thin, deliberately untestable glue between the real system event stream
/// and `WindowMoveController`: creates a global `CGEventTap` for the left
/// mouse button, translates each event into the plain
/// point/command-key-flag calls `WindowMoveController` understands, and
/// consumes (drops) exactly the events the controller reports it handled —
/// so a Cmd+drag never reaches the application under the window being
/// moved.
///
/// Requires Accessibility permission (`AccessibilityPermissionManager`); if
/// it has not been granted, `CGEvent.tapCreate` fails and `start()` logs and
/// does nothing further (no crash, no retry loop — the same permission
/// change that lets `MouseWindowWatcher`'s window lookups work will also
/// need a fresh `start()` call, so `AppDelegate` only calls this once
/// trust is expected to already be in place; see README's Accessibility
/// permission flow).
///
/// Not marked `@MainActor`: the callback passed to `CGEvent.tapCreate` must
/// be a plain, non-capturing C function (`@convention(c)`), which cannot be
/// actor-isolated. `self` is instead threaded through manually via the
/// `userInfo`/refcon pointer. In practice the callback always runs on the
/// main thread anyway, because `start()` attaches the tap's run loop source
/// to `CFRunLoopGetMain()` and is itself only ever called from
/// `AppDelegate` on the main thread — `handle` bridges into `WindowMoveController`'s
/// `@MainActor` isolation via `MainActor.assumeIsolated`, which is exactly
/// the sanctioned way to assert "this synchronous context is already
/// running on the main actor" without an `await`.
final class WindowMoveEventTap {

    /// Not `private`: `AppDelegate` needs to push live `exclusionMatcher`
    /// changes from the Settings window directly into it, mirroring
    /// `FocusFollowsMouseEventTap.controller`.
    let controller: WindowMoveController
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// The modifier(s) that must be held for a mouse-down to start a move —
    /// mutable so `AppDelegate` can push a live update whenever
    /// `AppSettings.gestureModifier` changes, matching
    /// `FocusFollowsMouseController.dwellDelay`'s pattern for live-tunable
    /// settings. Defaults to Command, matching `GestureModifier.defaultValue`.
    var gestureModifier: GestureModifier = .defaultValue

    init(controller: WindowMoveController) {
        self.controller = controller
    }

    /// Creates and enables the event tap. Safe to call multiple times;
    /// subsequent calls are a no-op while already started.
    ///
    /// Marked `@MainActor` (unlike the rest of this otherwise nonisolated
    /// class) only because its failure path logs to the `@MainActor`
    /// `DebugLogger.shared`. It's always called from `AppDelegate`, itself
    /// `@MainActor`, so this adds no actual hop — see `MouseWindowWatcher`
    /// for the sibling case of a `DebugLogger` access needing to line up
    /// with its caller's isolation.
    @MainActor
    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passRetained(event) }
                let instance = Unmanaged<WindowMoveEventTap>.fromOpaque(context).takeUnretainedValue()
                return instance.handle(type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            DebugLogger.shared.log(
                "Failed to create window-move event tap (is Accessibility permission granted?)."
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
        // MainActor.assumeIsolated's operation closure must return a
        // Sendable value; rather than relying on Unmanaged<CGEvent>?'s
        // Sendable conformance (uncertain across SDK versions), the
        // isolated block just writes into this plain local instead.
        var result: Unmanaged<CGEvent>?
        MainActor.assumeIsolated {
            switch type {
            case .leftMouseDown:
                let consumed = controller.mouseDown(
                    at: event.location,
                    modifierPressed: gestureModifier.isSatisfied(by: event.flags)
                )
                result = consumed ? nil : Unmanaged.passRetained(event)

            case .leftMouseDragged:
                let consumed = controller.mouseDragged(to: event.location)
                result = consumed ? nil : Unmanaged.passRetained(event)

            case .leftMouseUp:
                let wasDragging = controller.isDragging
                controller.mouseUp()
                result = wasDragging ? nil : Unmanaged.passRetained(event)

            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                // macOS disables a tap if its callback is judged too slow, or
                // on certain user actions (e.g. the secure input field case).
                // Since ours does small, fast, local work only, just re-enable it.
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

    deinit {
        stop()
    }
}
