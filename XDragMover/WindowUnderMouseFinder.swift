import Foundation
import CoreGraphics

/// Determines which on-screen window, if any, is currently under a given
/// point. This is pure, side-effect-free logic on top of a
/// `WindowListProviding`, which makes it straightforward to unit test with
/// fabricated window lists (see `WindowUnderMouseFinderTests`).
struct WindowUnderMouseFinder {

    /// Only windows at this CoreGraphics layer are considered "normal"
    /// application windows. Menus, the Dock, and other system chrome use
    /// other layers and are ignored so they never get reported as the
    /// "window under the mouse".
    static let normalWindowLayer = 0

    let provider: WindowListProviding

    init(provider: WindowListProviding = CGWindowListProvider()) {
        self.provider = provider
    }

    /// Returns the frontmost normal window whose bounds contain `point`,
    /// or `nil` if none does. `point` must be in the same top-left-origin
    /// screen coordinate space as `WindowInfo.bounds`
    /// (i.e. `kCGWindowBounds`, not `NSEvent.mouseLocation`'s bottom-left
    /// origin space — see `MouseWindowWatcher` for the conversion).
    func window(at point: CGPoint) -> WindowInfo? {
        provider.currentWindows().first { window in
            window.layer == Self.normalWindowLayer && window.bounds.contains(point)
        }
    }
}
