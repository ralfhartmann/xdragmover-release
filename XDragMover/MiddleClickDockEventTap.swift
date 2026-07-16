import Foundation
import CoreGraphics

/// Thin, deliberately untestable glue between the real system event stream
/// and `MiddleClickDockController` (US-16): creates a global `CGEventTap`
/// for the middle mouse button and forwards each click's location to the
/// controller.
///
/// Originally used `options: .listenOnly`, since middle-clicks anywhere
/// outside an app's Dock icon (including everywhere outside the Dock
/// entirely, e.g. a browser's "open link in new tab") must behave exactly
/// as if this app didn't exist. Live testing found that wasn't enough for
/// clicks the controller *does* act on, though: a middle-click on a Dock
/// icon can also open the Dock's own icon context menu natively — left
/// unsuppressed, that menu stays open on screen after this feature has
/// already opened the new window/instance. This now uses
/// `options: .defaultTap` and consumes both `.otherMouseDown` and its
/// matching `.otherMouseUp` exactly when `MiddleClickDockController
/// .middleMouseDown` reports it handled the click (i.e. it was a resolved
/// Dock icon) — every other middle-click, on or off the Dock, is still
/// passed through completely untouched.
///
/// Requires Accessibility permission, same as the other event taps; see
/// `WindowMoveEventTap`'s doc comment for the shared rationale behind this
/// class's threading/actor-isolation shape.
final class MiddleClickDockEventTap {

    let controller: MiddleClickDockController
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingHandledDown = false

    /// `CGEventField` value identifying which mouse button an
    /// other-mouse event belongs to: 0 = left, 1 = right, 2 = middle.
    private static let middleButtonNumber: Int64 = 2

    init(controller: MiddleClickDockController) {
        self.controller = controller
    }

    /// Creates and enables the event tap. Safe to call multiple times;
    /// subsequent calls are a no-op while already started.
    @MainActor
    func start() {
        guard eventTap == nil else { return }

        let eventMask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passRetained(event) }
                let instance = Unmanaged<MiddleClickDockEventTap>.fromOpaque(context).takeUnretainedValue()
                return instance.handle(type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            DebugLogger.shared.log(
                "Failed to create middle-click-Dock event tap (is Accessibility permission granted?)."
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
        guard event.getIntegerValueField(.mouseEventButtonNumber) == Self.middleButtonNumber else {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .otherMouseDown:
            var handled = false
            MainActor.assumeIsolated {
                handled = controller.middleMouseDown(at: event.location)
            }
            pendingHandledDown = handled
            return handled ? nil : Unmanaged.passRetained(event)

        case .otherMouseUp:
            defer { pendingHandledDown = false }
            return pendingHandledDown ? nil : Unmanaged.passRetained(event)

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Same re-enable handling as WindowMoveEventTap — macOS
            // disables a tap it judges too slow or on certain user
            // actions; ours does small, fast, local work only.
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)

        default:
            return Unmanaged.passRetained(event)
        }
    }

    deinit {
        stop()
    }
}
