import Foundation

/// Whether a given app (by its `ownerName`, matching `WindowInfo.ownerName`/
/// `kCGWindowOwnerName`) should be protected from move/resize gestures.
/// Kept as a protocol (mirroring `AXWindowLocating`) so
/// `WindowMoveController`/`WindowResizeController` can be unit tested
/// without real `NSRegularExpression` compilation.
protocol WindowExclusionMatching {
    func isExcluded(ownerName: String) -> Bool
}

/// Real implementation: a list of regex patterns
/// (`AppSettings.excludedWindowPatterns`), matched against `ownerName`. A
/// window is excluded if *any* pattern finds a match anywhere in the name
/// (not required to match the whole string, so a hand-written substring
/// pattern like `Chrome` still works) — auto-generated patterns from the
/// window picker anchor themselves with `^...$` for an exact match, see
/// `exactPattern(forOwnerName:)`.
///
/// Patterns that fail to compile (e.g. a user mid-edit of a regex with an
/// unbalanced paren) are silently skipped rather than crashing or blocking
/// all matching — `SettingsView` separately shows a visible invalid-pattern
/// indicator so this is never a silent failure from the user's perspective.
struct WindowExclusionList: WindowExclusionMatching {
    let patterns: [String]
    private let compiledPatterns: [NSRegularExpression]

    init(patterns: [String]) {
        self.patterns = patterns
        self.compiledPatterns = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }

    func isExcluded(ownerName: String) -> Bool {
        let range = NSRange(ownerName.startIndex..., in: ownerName)
        return compiledPatterns.contains { $0.firstMatch(in: ownerName, range: range) != nil }
    }

    /// The pattern the window picker generates when a user selects an app:
    /// an exact, fully-escaped match on its current `ownerName`, so picking
    /// "Calculator" protects exactly that app, not any app whose name
    /// happens to contain "Calculator" as a substring.
    static func exactPattern(forOwnerName ownerName: String) -> String {
        "^" + NSRegularExpression.escapedPattern(for: ownerName) + "$"
    }
}
