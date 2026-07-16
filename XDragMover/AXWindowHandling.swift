import Foundation
import CoreGraphics

/// Abstraction over "a specific on-screen window, obtained via the
/// Accessibility API, that can be read/moved/raised". Kept as a protocol
/// (mirroring `WindowListProviding`) so the move/drag logic in
/// `WindowMoveController` can be unit tested with a fake window instead of a
/// real `AXUIElement`, which requires a live windowed process and
/// Accessibility permission to exist at all.
protocol AXWindowHandling: AnyObject {
    /// The window's current top-left origin, in the same top-left-origin
    /// global screen coordinate space as `kCGWindowBounds` and
    /// `AXUIElementCopyElementAtPosition` (i.e. NOT `NSEvent.mouseLocation`'s
    /// bottom-left origin space). `nil` if the position could not be read
    /// (e.g. the window has since closed).
    var position: CGPoint? { get }

    /// The window's current size in points. `nil` if it could not be read
    /// (e.g. the window has since closed).
    var size: CGSize? { get }

    /// Moves the window so its top-left origin is at `point`, in the same
    /// coordinate space as `position`. Best-effort: if the underlying
    /// element no longer exists or refuses the change, this silently does
    /// nothing, matching how the Accessibility API itself reports failures
    /// only via a (frequently ignorable) error code.
    func setPosition(_ point: CGPoint)

    /// Resizes the window to `size`, in points. Best-effort, same caveats
    /// as `setPosition`.
    func setSize(_ size: CGSize)

    /// Brings this window to the front and makes its owning application
    /// active, so grabbing a background window to move it also raises it —
    /// matching the KDE Alt+drag behavior this app is modeled on.
    func raise()

    /// The display name of the app that owns this window (matching
    /// `WindowInfo.ownerName`/`kCGWindowOwnerName`), used to check it
    /// against `AppSettings.excludedWindowPatterns`. `nil` if the owning
    /// process could not be resolved.
    var ownerName: String? { get }

    /// Gives this window keyboard/mouse input focus, deliberately *without*
    /// raising it or activating its owning app — see US-3 (focus-follows-
    /// mouse). Best-effort, same caveats as `setPosition`/`setSize`: macOS
    /// has no first-class public API for "focus this window but don't
    /// touch stacking order", since input delivery is normally tied to the
    /// frontmost app's key window. This uses the Accessibility API's
    /// `AXFocused` attribute — the same lever third-party window managers
    /// use for non-mouse-driven focus switching — which for most apps
    /// changes only where input goes, but isn't guaranteed never to affect
    /// stacking for every app; that's a platform limitation, not something
    /// this method can fully control.
    func focus()
}

/// Abstraction over "find the window at a given screen point, via the
/// Accessibility API". Distinct from `WindowUnderMouseFinder`
/// (`WindowListProviding`/`CGWindowListCopyWindowInfo`-based): that one only
/// answers "which window is here" for the read-only debug log, using an API
/// that does not require Accessibility permission. Moving another
/// application's window requires an `AXUIElement` reference to it, which can
/// only be obtained through the Accessibility API — hence a separate lookup.
protocol AXWindowLocating {
    /// Returns a handle to the frontmost window at `point`, or `nil` if
    /// there is none (or Accessibility access has not been granted).
    /// `point` uses the same top-left-origin global screen coordinate space
    /// as `AXWindowHandling.position`.
    func window(at point: CGPoint) -> AXWindowHandling?
}
