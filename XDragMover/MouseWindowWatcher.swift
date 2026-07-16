import Foundation
import AppKit

/// Polls the current mouse location at a fixed interval and logs the
/// window under the cursor to `DebugLogger` whenever it changes.
///
/// This is a deliberately simple placeholder for this early milestone
/// (see README.md "Status"): the full feature set (⌘+drag move/resize,
/// two-stage focus-follows-mouse) will replace/extend this with a
/// `CGEventTap`-based global event monitor. For now this only needs to
/// answer "which window is currently under the mouse?" for the debug
/// window, which does not require Accessibility permission.
@MainActor
final class MouseWindowWatcher {

    private let finder: WindowUnderMouseFinder
    private let logger: DebugLogger
    private let interval: TimeInterval
    private var timer: Timer?

    /// The window number last written to the log, or `nil` if either
    /// nothing has been reported yet or the last report was "no window".
    private var lastReportedWindowNumber: Int?
    /// Distinguishes "never reported" from "reported nil" so the very
    /// first tick always produces a log line.
    private var hasReportedOnce = false

    // `logger` has no default value here on purpose: a default of
    // `.shared` would reference the @MainActor-isolated `DebugLogger.shared`
    // from the nonisolated context Swift evaluates default argument
    // expressions in — a warning today ("main actor-isolated static
    // property 'shared' can not be referenced from a nonisolated context"),
    // and a hard error under the Swift 6 language mode. Callers pass
    // `DebugLogger.shared` explicitly instead (see AppDelegate).
    init(
        finder: WindowUnderMouseFinder = WindowUnderMouseFinder(),
        logger: DebugLogger,
        interval: TimeInterval = 0.2
    ) {
        self.finder = finder
        self.logger = logger
        self.interval = interval
    }

    /// Starts polling. Safe to call multiple times; restarts the timer.
    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
    }

    /// Stops polling.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Converts `NSEvent.mouseLocation` (bottom-left origin, per-screen)
    /// into the top-left-origin, global coordinate space used by
    /// `kCGWindowBounds`, then looks up and reports the window at that
    /// point.
    func tick() {
        guard let screenHeight = NSScreen.screens.first?.frame.height else { return }
        let cocoaPoint = NSEvent.mouseLocation
        let quartzPoint = CGPoint(x: cocoaPoint.x, y: screenHeight - cocoaPoint.y)
        report(finder.window(at: quartzPoint))
    }

    /// Logs `window`, but only if it differs from the previously reported
    /// one, to avoid flooding the debug log while the mouse sits still
    /// over the same window. Exposed (not `private`) so it can be driven
    /// directly from unit tests without any real screen/mouse state.
    func report(_ window: WindowInfo?) {
        guard !hasReportedOnce || window?.windowNumber != lastReportedWindowNumber else { return }
        hasReportedOnce = true
        lastReportedWindowNumber = window?.windowNumber
        if let window {
            logger.log("Window under mouse: \(window.debugDescription)")
        } else {
            logger.log("Window under mouse: none")
        }
    }

    deinit {
        timer?.invalidate()
    }
}
