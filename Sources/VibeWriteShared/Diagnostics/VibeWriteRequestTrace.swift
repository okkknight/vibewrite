import Foundation

public enum VibeWriteRequestTrace {
    private static let queue = DispatchQueue(label: "com.knightspace.vibewrite.request-trace")

    public static func append(_ message: String) {
        queue.sync {
            do {
                let data = "\(timestampString()) \(message)\n".data(using: .utf8) ?? Data()
                guard !data.isEmpty else { return }
                let fileManager = FileManager.default
                let fileURL = try traceFileURL(fileManager: fileManager)
                try ensureParentDirectoryExists(for: fileURL, fileManager: fileManager)

                if !fileManager.fileExists(atPath: fileURL.path) {
                    fileManager.createFile(atPath: fileURL.path, contents: nil)
                }

                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // This trace is best-effort only. Never block the write flow.
            }
        }
    }

    static func traceFileURL(fileManager: FileManager = .default) throws -> URL {
        guard let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        return supportDirectory
            .appendingPathComponent("VibeWrite", isDirectory: true)
            .appendingPathComponent("diagnostics", isDirectory: true)
            .appendingPathComponent("backend-gateway-request-trace.log", isDirectory: false)
    }

    private static func timestampString() -> String {
        String(Int(Date().timeIntervalSince1970 * 1_000))
    }

    private static func ensureParentDirectoryExists(for fileURL: URL, fileManager: FileManager) throws {
        let parentDirectory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectory.path) {
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }
    }
}
