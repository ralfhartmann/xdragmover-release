import Foundation
import ApplicationServices
import CoreGraphics

/// Best-effort, private/undocumented WindowServer API access for giving a
/// window real cross-process keyboard focus without the full
/// `kAXRaiseAction` reordering that normally comes with it — see US-3's
/// "Non-Functional" notes in `USER_STORIES.md` for why this exists at all:
/// real-machine testing showed the public `AXFocused` attribute
/// (`AXWindowElement.focus()`'s fallback below) does not actually redirect
/// keyboard input away from the frontmost app; it only affects which
/// window is "key" *within* an already-active app.
///
/// Ported from yabai's `window_manager_focus_window_without_raise` /
/// `window_manager_make_key_window`
/// (https://github.com/koekeishiya/yabai/blob/master/src/window_manager.c),
/// which reverse-engineered the raw event-record byte layout
/// `SLPSPostEventRecordTo` expects — completely undocumented by Apple.
/// yabai's own issue history shows this exact mechanism has repeatedly
/// needed adjustment across macOS releases, so this is inherently fragile:
/// every private symbol is resolved via `dlsym` at runtime, never linked at
/// build time, and every call site checks a `Bool` return so a missing
/// symbol (or a resolvable-but-no-longer-correct byte layout on some future
/// macOS version) fails safe into the `AXFocused` fallback instead of
/// crashing or silently doing nothing at all.
// Carbon's deprecated `ProcessSerialNumber` (two `UInt32`s,
// `highLongOfPSN`/`lowLongOfPSN`) is what the private focus APIs below key
// off, but no Swift-visible declaration of it exists to reference, and a
// custom Swift struct standing in for it isn't Objective-C-representable —
// required for `@convention(c)` — even as a plain top-level type. Untyped
// `UnsafeMutableRawPointer`s to a manually-sized 8-byte buffer sidestep
// that entirely; there's no Swift-level type safety to lose here anyway,
// since every one of these symbols is already resolved dynamically via
// `dlsym` rather than linked against a real declaration.
private typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> OSStatus
private typealias GetWindowFn = @convention(c) (
    AXUIElement, UnsafeMutablePointer<CGWindowID>
) -> AXError
private typealias PostEventRecordToFn = @convention(c) (
    UnsafeMutableRawPointer, UnsafePointer<UInt8>
) -> CGError
private typealias SetFrontProcessWithOptionsFn = @convention(c) (
    UnsafeMutableRawPointer, UInt32, UInt32
) -> CGError

enum PrivateWindowFocus {

    /// yabai's `kCPSUserGenerated` (`src/window_manager.h`): a flag passed
    /// to `_SLPSSetFrontProcessWithOptions` marking the activation as
    /// user-initiated.
    private static let kCPSUserGenerated: UInt32 = 0x200

    private static func resolve<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    // `_AXUIElementGetWindow` is a long-standing, widely-relied-upon private
    // accessibility call (used by many shipping window-management utilities)
    // that maps an AX window element to its `CGWindowID` — needed because
    // the byte-level focus event below is keyed by window ID, not by an
    // `AXUIElement` reference.
    private static let getWindow = resolve("_AXUIElementGetWindow", as: GetWindowFn.self)
    private static let getProcessForPID = resolve("GetProcessForPID", as: GetProcessForPIDFn.self)
    private static let postEventRecordTo = resolve("SLPSPostEventRecordTo", as: PostEventRecordToFn.self)
    private static let setFrontProcessWithOptions = resolve(
        "_SLPSSetFrontProcessWithOptions", as: SetFrontProcessWithOptionsFn.self
    )

    /// The PSN/window ID last given focus by `focusWithoutRaise`, so a
    /// later call can tell "switching to another window of the same
    /// already-active app" apart from "switching to a different app" — see
    /// that method's doc comment. `nonisolated(unsafe)` because this is
    /// only ever touched from the main thread in practice (the only
    /// caller, `AXWindowElement.focus()`, is only ever invoked from
    /// `FocusFollowsMouseController`, itself `@MainActor`), and there's no
    /// way to express that isolation on a plain top-level enum without
    /// pulling every private-API type above into `@MainActor` too.
    nonisolated(unsafe) private static var lastFocusedPSNBytes: [UInt8]?
    nonisolated(unsafe) private static var lastFocusedWindowID: CGWindowID?

    /// Attempts to give `element` (a window belonging to `pid`) real
    /// keyboard focus by making its owning process the front process and
    /// injecting synthesized "become key window" event records, the same
    /// way yabai's `focus_follows_mouse=autofocus` mode does. Returns
    /// `false`, having done nothing, if any required private symbol is
    /// unavailable on this macOS version or the window/process couldn't be
    /// resolved — callers should fall back to `AXFocused` in that case.
    static func focusWithoutRaise(_ element: AXUIElement, pid: pid_t) -> Bool {
        guard
            let getWindow, let getProcessForPID,
            let postEventRecordTo, let setFrontProcessWithOptions
        else {
            return false
        }

        var windowID: CGWindowID = 0
        guard getWindow(element, &windowID) == .success else { return false }

        // 8 bytes: Carbon's `ProcessSerialNumber` is two `UInt32`s
        // (`highLongOfPSN`/`lowLongOfPSN`) — see this file's top-of-file
        // comment for why this is a raw buffer rather than a typed struct.
        var psnBytes = [UInt8](repeating: 0, count: 8)
        let status = psnBytes.withUnsafeMutableBytes { getProcessForPID(pid, $0.baseAddress!) }
        guard status == noErr else { return false }

        // Computed before entering the closure below: comparing against
        // `psnBytes` from inside its own `withUnsafeMutableBytes` closure
        // is an overlapping-access exclusivity violation.
        let sameAppAsLastFocused = lastFocusedPSNBytes == psnBytes

        psnBytes.withUnsafeMutableBytes { psnBuf in
            // Switching between two windows *of the same already-active
            // app* needs an extra nudge: posting only the "become key
            // window" events below (which is all `else` case does) reliably
            // moves app-level activation across apps, but doesn't reliably
            // move key-window status between two windows of an app that's
            // already frontmost — the app has no reason to think anything
            // changed. Ported from yabai's `window_manager_focus_window_without_raise`:
            // if the target's PSN matches the app we last focused through
            // here, explicitly deactivate the previously-focused window
            // (event type 0x0d, sub-flag 0x8a = 0x02) before activating the
            // new one (same type, sub-flag 0x01) — with the same 40ms
            // delay yabai's source notes is needed because some apps get
            // confused if both arrive instantaneously.
            if sameAppAsLastFocused, let lastFocusedWindowID {
                var activationEventBytes = [UInt8](repeating: 0, count: 0xf8)
                activationEventBytes[0x04] = 0xf8
                activationEventBytes[0x08] = 0x0d

                activationEventBytes[0x8a] = 0x02
                withUnsafeBytes(of: lastFocusedWindowID) {
                    activationEventBytes.replaceSubrange(0x3c..<0x40, with: $0)
                }
                _ = activationEventBytes.withUnsafeBufferPointer { postEventRecordTo(psnBuf.baseAddress!, $0.baseAddress!) }

                usleep(40000)

                activationEventBytes[0x8a] = 0x01
                withUnsafeBytes(of: windowID) {
                    activationEventBytes.replaceSubrange(0x3c..<0x40, with: $0)
                }
                _ = activationEventBytes.withUnsafeBufferPointer { postEventRecordTo(psnBuf.baseAddress!, $0.baseAddress!) }
            }

            // Byte layout ported verbatim from yabai's
            // `window_manager_make_key_window`: an undocumented, fixed-size
            // (0xf8 byte) synthetic event record that WindowServer interprets
            // as "this window just became key", posted twice (0x08 = 0x01,
            // then 0x02) to the target process's connection.
            var eventBytes = [UInt8](repeating: 0, count: 0xf8)
            eventBytes[0x04] = 0xf8
            eventBytes[0x3a] = 0x10
            withUnsafeBytes(of: windowID) { eventBytes.replaceSubrange(0x3c..<0x40, with: $0) }
            for i in 0x20..<0x30 { eventBytes[i] = 0xff }

            eventBytes[0x08] = 0x01
            _ = eventBytes.withUnsafeBufferPointer { postEventRecordTo(psnBuf.baseAddress!, $0.baseAddress!) }
            eventBytes[0x08] = 0x02
            _ = eventBytes.withUnsafeBufferPointer { postEventRecordTo(psnBuf.baseAddress!, $0.baseAddress!) }

            _ = setFrontProcessWithOptions(psnBuf.baseAddress!, windowID, kCPSUserGenerated)
        }

        lastFocusedPSNBytes = psnBytes
        lastFocusedWindowID = windowID
        return true
    }
}
