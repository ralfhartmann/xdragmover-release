import Foundation
import Combine

/// Central, in-memory log used to feed the debug window described in the README
/// ("it opens a debug window in which debug output is shown").
///
/// The logger is intentionally simple (an in-memory ring buffer of `LogEntry`
/// values) so it can be exercised directly from unit tests without any UI,
/// Accessibility permission, or system APIs involved.
@MainActor
final class DebugLogger: ObservableObject {

    /// Shared instance used by the running app.
    static let shared = DebugLogger()

    /// All log entries currently retained, oldest first.
    @Published private(set) var entries: [LogEntry] = []

    /// Maximum number of entries retained; oldest entries are dropped first.
    let maxEntries: Int

    init(maxEntries: Int = 500) {
        precondition(maxEntries > 0, "maxEntries must be positive")
        self.maxEntries = maxEntries
    }

    /// Appends a new, timestamped log entry.
    func log(_ message: String) {
        entries.append(LogEntry(timestamp: Date(), message: message))
        trimIfNeeded()
    }

    /// Removes all log entries.
    func clear() {
        entries.removeAll()
    }

    private func trimIfNeeded() {
        guard entries.count > maxEntries else { return }
        entries.removeFirst(entries.count - maxEntries)
    }
}
