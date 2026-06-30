import Foundation
import XCTVapor
@testable import VibeWriteBackend

final class BackendSQLitePersistenceTests: XCTestCase {
    func testProductionConfigureDefaultsToSQLiteWithoutDatabaseURL() async throws {
        let sqlitePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        try await withEnvironmentOverrides(
            [
                "VIBEWRITE_BACKEND_SQLITE_PATH": sqlitePath.path,
                "ADMIN_SECRET_ENCRYPTION_KEY": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            ],
            removing: ["DATABASE_URL"]
        ) {
            let app = try await Application.make(.production)
            defer {
                Task {
                    try? await app.asyncShutdown()
                }
            }

            let bootstrapper = try configure(
                app,
                adminUsername: "admin",
                adminPassword: "password"
            )

            XCTAssertNotNil(bootstrapper)
            try await bootstrapper?.prepare()

            let response = try await app.performTest(
                request: TestingHTTPRequest(
                    method: .GET,
                    url: .init(path: "v3/health"),
                    headers: [:],
                    body: ByteBufferAllocator().buffer(capacity: 0)
                )
            )
            XCTAssertEqual(response.status, .ok)

            XCTAssertTrue(FileManager.default.fileExists(atPath: sqlitePath.path))
        }
    }

    private func withEnvironmentOverrides(
        _ values: [String: String],
        removing keysToRemove: [String] = [],
        perform work: () async throws -> Void
    ) async throws {
        let touchedKeys = Set(values.keys).union(keysToRemove)
        let originalValues = touchedKeys.reduce(into: [String: String?]()) { partial, key in
            partial[key] = ProcessInfo.processInfo.environment[key]
        }

        for key in keysToRemove {
            unsetenv(key)
        }

        for (key, value) in values {
            setenv(key, value, 1)
        }

        defer {
            for key in touchedKeys {
                if let originalValue = originalValues[key] ?? nil {
                    setenv(key, originalValue, 1)
                } else {
                    unsetenv(key)
                }
            }
        }

        try await work()
    }
}
