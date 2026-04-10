import Foundation
import OSLog

enum VibeWriteLog {
    static let launch = Logger(subsystem: "com.knightspace.vibewrite", category: "launch")
    static let ai = Logger(subsystem: "com.knightspace.vibewrite", category: "ai")
}

@MainActor
enum VibeWriteDebugTrace {
    private static var lines: [String] = []

    static func append(_ line: String) {
        lines.append(line)
        if lines.count > 10_000 {
            lines.removeFirst(lines.count - 10_000)
        }
    }

    static func drain() -> [String] {
        let snapshot = lines
        lines.removeAll(keepingCapacity: true)
        return snapshot
    }
}

extension String {
    func vibewriteLogPreview(maxLength: Int = 120) -> String {
        let collapsed = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        guard collapsed.count > maxLength else {
            return collapsed
        }

        return String(collapsed.prefix(maxLength - 1)) + "…"
    }
}
