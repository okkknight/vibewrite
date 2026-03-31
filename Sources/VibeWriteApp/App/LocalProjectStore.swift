import Foundation

struct LocalProjectStoreSnapshot: Codable {
    var schemaVersion: Int
    var projects: [WritingProject]
    var lastOpenedProjectID: UUID?
}

struct LocalProjectStore {
    let storageURL: URL
    let fileManager: FileManager

    init(storageURL: URL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        self.fileManager = fileManager
    }

    static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return supportDirectory
            .appendingPathComponent("VibeWrite", isDirectory: true)
            .appendingPathComponent("local-project-store.json")
    }

    func load() -> LocalProjectStoreSnapshot? {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: storageURL)
            return try JSONDecoder.vibeWriteSnapshotDecoder.decode(LocalProjectStoreSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    func save(projects: [WritingProject], lastOpenedProjectID: UUID?) {
        let snapshot = LocalProjectStoreSnapshot(
            schemaVersion: 1,
            projects: projects,
            lastOpenedProjectID: lastOpenedProjectID
        )

        do {
            try ensureStorageDirectoryExists()
            let data = try JSONEncoder.vibeWriteSnapshotEncoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }

    private func ensureStorageDirectoryExists() throws {
        let parentDirectory = storageURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: parentDirectory.path) {
            return
        }

        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
    }
}

private extension JSONEncoder {
    static var vibeWriteSnapshotEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var vibeWriteSnapshotDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
