import Foundation
import ApplicationServices

/// Resolves which app's Dock icon (if any) is at a given screen point.
/// Kept as a protocol (mirroring `AXWindowLocating`) so
/// `MiddleClickDockController` can be unit tested without real AX calls.
protocol DockIconResolving {
    func appURL(at point: CGPoint) -> URL?
}

/// Real implementation, backed by `AXUIElementCopyElementAtPosition` on
/// the system-wide accessibility element — the same technique
/// `SystemAXWindowLocator` uses for window hit-testing, confirmed live to
/// also work directly on Dock icons: the OS performs the actual
/// hit-testing, so no manual `AXList`-walking/frame-comparison is needed
/// (that approach was tried and found unreliable — Dock item positions
/// can shift between caching them and comparing against a click point).
struct SystemDockIconResolver: DockIconResolving {
    private let systemWideElement: AXUIElement

    init() {
        self.systemWideElement = AXUIElementCreateSystemWide()
    }

    /// `nil` unless `point` is over an actual app icon — separators, the
    /// Trash, and minimized-window tiles all have a different `AXSubrole`
    /// and are deliberately excluded.
    func appURL(at point: CGPoint) -> URL? {
        var elementRef: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWideElement, Float(point.x), Float(point.y), &elementRef
        )
        guard result == .success, let element = elementRef else { return nil }
        guard Self.attribute(element, kAXRoleAttribute as String) as? String == "AXDockItem",
              Self.attribute(element, kAXSubroleAttribute as String) as? String == "AXApplicationDockItem"
        else { return nil }
        return Self.attribute(element, "AXURL") as? URL
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
