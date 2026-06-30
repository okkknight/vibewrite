import Foundation
import Vapor

struct BackendPersistenceConfiguration: Sendable, Equatable {
    enum Storage: Sendable, Equatable {
        case sqlite(filePath: String)
        case postgres(databaseURL: String)
    }

    let storage: Storage

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) throws -> BackendPersistenceConfiguration {
        let explicitMode = resolvedString(for: "VIBEWRITE_BACKEND_PERSISTENCE", in: environment)?.lowercased()

        switch explicitMode {
        case "postgres", "postgresql":
            guard let databaseURL = resolvedString(for: "DATABASE_URL", in: environment) else {
                throw Abort(.internalServerError, reason: "Missing DATABASE_URL.")
            }
            return BackendPersistenceConfiguration(storage: .postgres(databaseURL: databaseURL))
        case "sqlite", nil, "":
            if explicitMode == nil,
               let databaseURL = resolvedString(for: "DATABASE_URL", in: environment) {
                return BackendPersistenceConfiguration(storage: .postgres(databaseURL: databaseURL))
            }

            let sqlitePath = resolvedSQLitePath(environment: environment, workingDirectoryURL: workingDirectoryURL)
            return BackendPersistenceConfiguration(storage: .sqlite(filePath: sqlitePath))
        default:
            throw Abort(.internalServerError, reason: "Unsupported VIBEWRITE_BACKEND_PERSISTENCE value: \(explicitMode ?? "").")
        }
    }

    static func hasExplicitPersistentConfiguration(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        resolvedString(for: "VIBEWRITE_BACKEND_PERSISTENCE", in: environment) != nil
            || resolvedString(for: "VIBEWRITE_BACKEND_SQLITE_PATH", in: environment) != nil
            || resolvedString(for: "DATABASE_URL", in: environment) != nil
    }

    private static func resolvedSQLitePath(
        environment: [String: String],
        workingDirectoryURL: URL
    ) -> String {
        if let explicitPath = resolvedString(for: "VIBEWRITE_BACKEND_SQLITE_PATH", in: environment) {
            let explicitURL = URL(fileURLWithPath: explicitPath, relativeTo: workingDirectoryURL)
            return explicitURL.standardizedFileURL.path
        }

        return workingDirectoryURL
            .appendingPathComponent("vibewrite.sqlite", isDirectory: false)
            .standardizedFileURL.path
    }

    private static func resolvedString(for key: String, in environment: [String: String]) -> String? {
        guard let rawValue = environment[key] else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
