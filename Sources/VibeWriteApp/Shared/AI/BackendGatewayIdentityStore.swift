import Foundation

struct BackendGatewayIdentityStoreSnapshot: Codable, Hashable {
    var schemaVersion: Int
    var installationId: String
    var deviceToken: String?
}

actor BackendGatewayIdentityStore {
    private let storageURL: URL
    private let fileManager: FileManager
    private var snapshot: BackendGatewayIdentityStoreSnapshot

    init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        let loadedSnapshot = Self.loadSnapshot(
            from: self.storageURL,
            fileManager: fileManager
        )
        self.snapshot = loadedSnapshot ?? Self.makeFreshSnapshot()

        if loadedSnapshot == nil {
            Self.persistSnapshot(
                self.snapshot,
                to: self.storageURL,
                fileManager: fileManager
            )
        }
    }

    static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return supportDirectory
            .appendingPathComponent("VibeWrite", isDirectory: true)
            .appendingPathComponent("backend-gateway-identity.json")
    }

    func snapshotValue() -> BackendGatewayIdentityStoreSnapshot {
        snapshot
    }

    func installationId() -> String {
        snapshot.installationId
    }

    func deviceToken() -> String? {
        snapshot.deviceToken
    }

    func updateDeviceToken(_ token: String?) {
        snapshot.deviceToken = Self.normalizedToken(token)
        Self.persistSnapshot(snapshot, to: storageURL, fileManager: fileManager)
    }

    func clearDeviceToken() {
        updateDeviceToken(nil)
    }

    private static func loadSnapshot(
        from storageURL: URL,
        fileManager: FileManager
    ) -> BackendGatewayIdentityStoreSnapshot? {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let snapshot = try JSONDecoder.vibeWriteBackendGatewayIdentityDecoder.decode(BackendGatewayIdentityStoreSnapshot.self, from: data)
            guard snapshot.schemaVersion == 1 else {
                return nil
            }

            let installationId = snapshot.installationId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !installationId.isEmpty else {
                return nil
            }

            return BackendGatewayIdentityStoreSnapshot(
                schemaVersion: 1,
                installationId: installationId,
                deviceToken: normalizedToken(snapshot.deviceToken)
            )
        } catch {
            return nil
        }
    }

    private static func makeFreshSnapshot() -> BackendGatewayIdentityStoreSnapshot {
        BackendGatewayIdentityStoreSnapshot(
            schemaVersion: 1,
            installationId: UUID().uuidString.lowercased(),
            deviceToken: nil
        )
    }

    private static func persistSnapshot(
        _ snapshot: BackendGatewayIdentityStoreSnapshot,
        to storageURL: URL,
        fileManager: FileManager
    ) {
        do {
            try ensureStorageDirectoryExists(for: storageURL, fileManager: fileManager)
            let data = try JSONEncoder.vibeWriteBackendGatewayIdentityEncoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }

    private static func ensureStorageDirectoryExists(
        for storageURL: URL,
        fileManager: FileManager
    ) throws {
        let parentDirectory = storageURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: parentDirectory.path) {
            return
        }

        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
    }

    private static func normalizedToken(_ token: String?) -> String? {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }
}

private extension JSONEncoder {
    static var vibeWriteBackendGatewayIdentityEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var vibeWriteBackendGatewayIdentityDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
