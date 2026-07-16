import Foundation
import ApplicationServices

/// Real `AXWindowLocating` implementation, backed by
/// `AXUIElementCopyElementAtPosition` on the system-wide accessibility
/// element. Requires Accessibility permission to return anything other than
/// `nil` (see `AccessibilityPermissionManager`).
struct SystemAXWindowLocator: AXWindowLocating {

    private let systemWideElement: AXUIElement

    init() {
        self.systemWideElement = AXUIElementCreateSystemWide()
    }

    func window(at point: CGPoint) -> AXWindowHandling? {
        var elementRef: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &elementRef
        )
        guard result == .success, let element = elementRef else { return nil }
        guard let windowElement = Self.resolveWindow(from: element) else { return nil }
        return AXWindowElement(windowElement)
    }

    /// `AXUIElementCopyElementAtPosition` returns whatever UI element is
    /// directly under the point — often a button, text field, or other
    /// control nested inside the window, not the window itself. This walks
    /// up until it finds the enclosing window:
    /// 1. if the element itself already has the "Window" role, use it;
    /// 2. otherwise, most elements expose the window they belong to via
    ///    `kAXWindowAttribute` — use that if present;
    /// 3. as a last resort (some elements expose neither), walk up the
    ///    `kAXParentAttribute` chain looking for a "Window"-role ancestor.
    static func resolveWindow(from element: AXUIElement) -> AXUIElement? {
        if role(of: element) == kAXWindowRole as String {
            return element
        }

        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
           let windowRef {
            // swiftlint:disable:next force_cast — kAXWindowAttribute is
            // always an AXUIElement when present.
            return (windowRef as! AXUIElement)
        }

        var current = element
        while true {
            var parentRef: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef) == .success,
                let parentRef
            else {
                return nil
            }
            // swiftlint:disable:next force_cast — kAXParentAttribute is
            // always an AXUIElement when present.
            let parent = parentRef as! AXUIElement
            if role(of: parent) == kAXWindowRole as String {
                return parent
            }
            current = parent
        }
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
