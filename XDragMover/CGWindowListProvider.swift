import Foundation
import CoreGraphics

/// Real, system-backed implementation of `WindowListProviding` using
/// `CGWindowListCopyWindowInfo`. This does not require the Accessibility
/// permission (unlike moving/resizing other apps' windows, which will be
/// added in a later milestone).
struct CGWindowListProvider: WindowListProviding {

    func currentWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]] else {
            return []
        }

        return rawList.compactMap { entry in
            guard
                let windowNumber = entry[kCGWindowNumber as String] as? Int,
                let ownerName = entry[kCGWindowOwnerName as String] as? String,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else {
                return nil
            }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            let title = entry[kCGWindowName as String] as? String

            return WindowInfo(
                windowNumber: windowNumber,
                ownerName: ownerName,
                title: title,
                bounds: bounds,
                layer: layer
            )
        }
    }
}
