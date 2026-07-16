import Foundation
import ApplicationServices

/// Abstraction over the system Accessibility trust check, so permission
/// logic can be unit tested without actually depending on (or changing)
/// the real Accessibility trust state of the test runner process.
protocol AccessibilityTrustChecking {
    /// Returns whether the current process is trusted for Accessibility
    /// (Automation) access. If `promptIfNeeded` is `true` and the process
    /// is not yet trusted, the system prompts the user to grant access in
    /// System Settings.
    func isProcessTrusted(promptIfNeeded: Bool) -> Bool
}

/// Real implementation backed by `AXIsProcessTrustedWithOptions`.
struct SystemAccessibilityTrustChecker: AccessibilityTrustChecking {
    func isProcessTrusted(promptIfNeeded: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: [String: Bool] = [promptKey: promptIfNeeded]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

/// Requests and tracks the Accessibility permission that XDragMover
/// needs for its window move/resize/focus-follows-mouse features (see
/// README.md, "How It Works").
///
/// Since macOS only lets an app *ask* the user to open System Settings —
/// it does not report back synchronously once access is granted — this
/// manager polls `isProcessTrusted` at a low frequency after a denied/
/// pending request, so the UI (the debug window's status indicator) can
/// update automatically once the user flips the switch in System Settings.
@MainActor
final class AccessibilityPermissionManager: ObservableObject {

    /// Whether the process currently has Accessibility access.
    @Published private(set) var isTrusted: Bool {
        didSet {
            guard isTrusted != oldValue else { return }
            onTrustedChange?(isTrusted)
        }
    }

    /// Fired whenever `isTrusted` actually changes (including the
    /// false→true transition after the user grants access in System
    /// Settings, whether that happens via the polling `refresh()` timer or
    /// mid-`requestAccessIfNeeded()`). `AppDelegate` uses this to retry
    /// starting the event taps once permission becomes available — they
    /// only ever attempted to start once, at launch, so granting access a
    /// moment after that (a very common race: the system prompt itself
    /// takes a moment to click through) left move/resize/focus-follows-
    /// mouse silently non-functional for the rest of that run even though
    /// the debug window's own status indicator correctly showed "granted".
    var onTrustedChange: ((Bool) -> Void)?

    private let checker: AccessibilityTrustChecking
    private let pollingInterval: TimeInterval
    private var pollTimer: Timer?

    init(
        checker: AccessibilityTrustChecking = SystemAccessibilityTrustChecker(),
        pollingInterval: TimeInterval = 1.0
    ) {
        self.checker = checker
        self.pollingInterval = pollingInterval
        self.isTrusted = checker.isProcessTrusted(promptIfNeeded: false)
    }

    /// Re-checks trust and, only if not already trusted, asks the system to
    /// show the "XDragMover would like to control this computer" prompt
    /// and starts polling for the user granting access afterwards.
    ///
    /// This always checks with `promptIfNeeded: false` first. Skipping that
    /// check and calling straight into `promptIfNeeded: true` would ask the
    /// checker to prompt unconditionally on every launch — in practice this
    /// was showing (or attempting to show) the system prompt again each time
    /// the app started, even once access had already been granted.
    func requestAccessIfNeeded() {
        if checker.isProcessTrusted(promptIfNeeded: false) {
            isTrusted = true
            stopPolling()
            return
        }
        isTrusted = checker.isProcessTrusted(promptIfNeeded: true)
        if isTrusted {
            stopPolling()
        } else {
            startPolling()
        }
    }

    /// Re-checks trust without prompting. Exposed for tests and for the
    /// polling timer.
    func refresh() {
        let trusted = checker.isProcessTrusted(promptIfNeeded: false)
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        if trusted {
            stopPolling()
        }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    deinit {
        pollTimer?.invalidate()
    }
}
