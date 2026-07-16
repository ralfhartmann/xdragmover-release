import Foundation
import ApplicationServices
import AppKit

/// Real `AXWindowHandling` implementation, backed by a live `AXUIElement`
/// window reference obtained from `SystemAXWindowLocator`.
final class AXWindowElement: AXWindowHandling {

    private let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    var position: CGPoint? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
            let axValue = value
        else {
            return nil
        }
        var point = CGPoint.zero
        // swiftlint:disable:next force_cast — AXValueGetValue requires the
        // caller to already know the underlying value's type; we asked for
        // kAXPositionAttribute, which is always an AXValue wrapping a CGPoint.
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    var size: CGSize? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
            let axValue = value
        else {
            return nil
        }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast — see the equivalent comment on
        // `position`: kAXSizeAttribute is always an AXValue wrapping a CGSize.
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    func setPosition(_ point: CGPoint) {
        var mutablePoint = point
        guard let axValue = AXValueCreate(.cgPoint, &mutablePoint) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue)
    }

    func setSize(_ size: CGSize) {
        var mutableSize = size
        guard let axValue = AXValueCreate(.cgSize, &mutableSize) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axValue)
    }

    var ownerName: String? {
        var pidValue: pid_t = 0
        guard AXUIElementGetPid(element, &pidValue) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pidValue)?.localizedName
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)

        var pidValue: pid_t = 0
        guard AXUIElementGetPid(element, &pidValue) == .success else { return }
        NSRunningApplication(processIdentifier: pidValue)?.activate()
    }

    func focus() {
        var pidValue: pid_t = 0
        if AXUIElementGetPid(element, &pidValue) == .success,
           PrivateWindowFocus.focusWithoutRaise(element, pid: pidValue) {
            return
        }
        // Fallback if the private WindowServer path is unavailable (see
        // PrivateWindowFocus's doc comment) — confirmed by testing to not
        // actually redirect keyboard input away from the frontmost app, but
        // still the best public-API-only option available.
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}
