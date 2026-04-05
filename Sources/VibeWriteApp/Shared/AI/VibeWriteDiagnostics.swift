import Foundation
import OSLog

enum VibeWriteLog {
    static let launch = Logger(subsystem: "com.knightspace.vibewrite", category: "launch")
    static let ai = Logger(subsystem: "com.knightspace.vibewrite", category: "ai")
}

enum VibeWriteDebugTrace {
    static let layoutTraceURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibewrite-layout-trace.log")
    private static let queue = DispatchQueue(label: "com.knightspace.vibewrite.layout-trace")

    static func append(_ line: String) {
        queue.async {
            let stampedLine = "[\(ISO8601DateFormatter().string(from: .now))] \(line)\n"
            do {
                if FileManager.default.fileExists(atPath: layoutTraceURL.path) == false {
                    FileManager.default.createFile(atPath: layoutTraceURL.path, contents: nil)
                }

                let handle = try FileHandle(forWritingTo: layoutTraceURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = stampedLine.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                // Debug tracing should never interfere with runtime behavior.
            }
        }
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

    func vibewriteRawTail(maxLength: Int = 120) -> String {
        guard count > maxLength else {
            return trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let tail = suffix(maxLength)
        return "…" + tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
