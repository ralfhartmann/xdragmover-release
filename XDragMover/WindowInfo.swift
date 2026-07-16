import Foundation
import CoreGraphics

/// A lightweight, testable description of an on-screen window, independent
/// of how it was obtained (real `CGWindowListCopyWindowInfo` call vs. a
/// fake list supplied by a unit test).
struct WindowInfo: Equatable {
    /// The CoreGraphics window number (`kCGWindowNumber`).
    let windowNumber: Int

    /// The name of the owning application/process (`kCGWindowOwnerName`).
    let ownerName: String

    /// The window's title, if any (`kCGWindowName`). Many system windows
    /// and background processes do not expose a title.
    let title: String?

    /// The window's frame in screen coordinates with a top-left origin,
    /// matching the coordinate space used by `kCGWindowBounds`.
    let bounds: CGRect

    /// The window's layer (`kCGWindowLayer`). Normal, front-facing
    /// application windows report `0`; menus, the Dock, and other system
    /// surfaces use other values.
    let layer: Int

    /// A short, human-readable description suitable for the debug log,
    /// e.g. `Finder – "Downloads" (#42)`.
    var debugDescription: String {
        if let title, !title.isEmpty {
            return "\(ownerName) – \"\(title)\" (#\(windowNumber))"
        }
        return "\(ownerName) (#\(windowNumber))"
    }
}
