import CoreGraphics

/// The keyboard modifier(s) required to hold while pressing the mouse to
/// start a window move (US-1) or resize (US-2) — user-configurable, shared
/// by both gestures via `AppSettings.gestureModifier`. Any non-empty
/// combination of the four is allowed except Shift alone (see `isValid`).
struct GestureModifier: OptionSet, Equatable {
    let rawValue: Int

    static let command = GestureModifier(rawValue: 1 << 0)
    static let option = GestureModifier(rawValue: 1 << 1)
    static let control = GestureModifier(rawValue: 1 << 2)
    static let shift = GestureModifier(rawValue: 1 << 3)

    static let defaultValue: GestureModifier = .command

    /// Shift alone is disallowed — it would hijack every plain
    /// shift-click, unlike Command/Option/Control which are rarely held
    /// for a plain click. An empty set is disallowed too, since that would
    /// turn every unmodified click into a move/resize gesture.
    var isValid: Bool {
        self != .shift && !isEmpty
    }

    /// The `CGEventFlags` bits a real event's `flags` must all be present
    /// for `isSatisfied(by:)` to match.
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift) { flags.insert(.maskShift) }
        return flags
    }

    /// Whether a real event's flags include every modifier this set
    /// requires (extra, unrelated flags being held too is fine).
    func isSatisfied(by eventFlags: CGEventFlags) -> Bool {
        eventFlags.contains(cgEventFlags)
    }
}
