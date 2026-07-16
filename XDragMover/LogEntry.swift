import Foundation

/// A single line in the debug log window.
struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let message: String

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// A single, ready-to-display line combining timestamp and message,
    /// e.g. "14:32:07.512  Window under mouse: Finder – \"Downloads\" (#42)".
    var formatted: String {
        "\(Self.formatter.string(from: timestamp))  \(message)"
    }
}
