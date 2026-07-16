import Foundation

/// Abstraction over "give me the current list of on-screen windows,
/// front-to-back". Kept as a protocol so window-lookup logic can be unit
/// tested with canned data instead of real, environment-dependent system
/// calls.
protocol WindowListProviding {
    /// Returns all currently known windows, ordered front-to-back (the
    /// first element is the frontmost window), matching the ordering
    /// guarantee of `CGWindowListCopyWindowInfo`.
    func currentWindows() -> [WindowInfo]
}
