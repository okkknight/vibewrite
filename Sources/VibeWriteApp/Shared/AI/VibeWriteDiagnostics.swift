import Foundation
import OSLog

enum VibeWriteLog {
    static let launch = Logger(subsystem: "com.knightspace.vibewrite", category: "launch")
    static let ai = Logger(subsystem: "com.knightspace.vibewrite", category: "ai")
}

enum VibeWriteDebugTrace {
    static func append(_ line: String) {
        _ = line
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
