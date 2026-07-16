import Foundation
import CoreGraphics

/// Abstraction over "reorder someone else's window to the front of its
/// layer, without activating its owning app" — kept as a protocol (mirroring
/// `AXWindowLocating`/`WindowListProviding`) purely so
/// `FocusFollowsMouseController`'s raise-guard logic can be unit tested
/// with a fake instead of actually shelling out to `yabai`.
protocol WindowOrderRestoring {
    func raiseWithoutActivating(windowID: CGWindowID)
}

/// Best-effort mitigation for apps (confirmed: Firefox) that raise their own
/// window in reaction to receiving real keyboard input after
/// `PrivateWindowFocus` gave them focus without raising — see that file's
/// doc comment and `USER_STORIES.md`'s Non-Functional notes for the full
/// story, including why this can only ever be a reactive correction, not a
/// true prevention: even yabai's own scripting-addition-based window
/// manager has this same open issue with Firefox (fixed upstream in
/// Firefox 97 for the "raises immediately on focus" case; our own testing
/// shows a similar raise can still happen on the first subsequent
/// keystroke).
///
/// Ordering an *other* application's window relative to another (as
/// opposed to raising a window your own process owns) requires bypassing
/// System Integrity Protection's normal restriction on manipulating other
/// processes' windows — something only possible via a WindowServer
/// connection with elevated privilege. There is no way to do this from a
/// normal, unprivileged process; this enum instead shells out to the
/// `yabai` window manager's CLI (`yabai -m window <id> --raise`), which
/// requires yabai to be installed *and* have its scripting addition loaded
/// into Dock.app (`sudo yabai --load-sa`), which itself requires SIP to be
/// partially disabled — see DEVELOPMENT.md's "Optional: yabai-assisted
/// window-order correction" section for the full setup (a manual,
/// user-performed process; this app cannot do it for you).
///
/// If yabai isn't installed or its scripting addition isn't loaded, every
/// call here is a silent no-op — this is purely an optional enhancement on
/// top of `PrivateWindowFocus`/`AXWindowElement.focus()`, never a
/// requirement.
struct YabaiWindowOrder: WindowOrderRestoring {

    /// Common install locations for the `yabai` binary (Homebrew on Apple
    /// Silicon vs. Intel). Re-checked on every call rather than cached, so
    /// installing/uninstalling yabai (or running `--load-sa` for the first
    /// time) takes effect immediately without restarting this app — cheap
    /// enough given this only runs when a self-raise was just detected,
    /// not on any hot path.
    private static var binaryPath: String? {
        let candidates = ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Asks yabai to order `windowID` to the front of its layer — a pure
    /// compositor-level reorder via `SLSOrderWindow`, distinct from
    /// `AXWindowHandling.raise()`'s `kAXRaiseAction`: testing confirmed
    /// `kAXRaiseAction` cannot bring a background app's window above the
    /// currently-active app's windows, while yabai's `--raise` (backed by
    /// its scripting addition) can, and does so *without* activating the
    /// window's owning app — exactly what's needed to undo an unwanted
    /// self-raise without also stealing keyboard focus back away from
    /// whatever window the user is actively typing into.
    ///
    /// Fire-and-forget: doesn't wait for or report the result, since the
    /// only failure modes (yabai missing, service not running, scripting
    /// addition not loaded) are all expected, silent-no-op states rather
    /// than errors a caller could usefully react to.
    func raiseWithoutActivating(windowID: CGWindowID) {
        guard let binaryPath = Self.binaryPath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["-m", "window", String(windowID), "--raise"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
