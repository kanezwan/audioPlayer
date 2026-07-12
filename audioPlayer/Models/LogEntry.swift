import Foundation

enum LogLevel {
    case info, warning, error
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let level: LogLevel

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let prefix: String
        switch level {
        case .info: prefix = "\u{2139}\u{FE0F}"
        case .warning: prefix = "\u{26A0}\u{FE0F}"
        case .error: prefix = "\u{274C}"
        }
        return "[\(formatter.string(from: timestamp))] \(prefix) \(message)"
    }
}
