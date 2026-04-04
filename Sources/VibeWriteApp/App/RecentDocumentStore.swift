import Foundation

struct RecentDocumentEntry: Codable, Hashable, Identifiable {
    var id: String { url.absoluteString }
    var url: URL
    var title: String
    var lastOpenedAt: Date

    var displayName: String {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : cleanedTitle
    }
}

struct RecentDocumentStoreSnapshot: Codable {
    var schemaVersion: Int
    var entries: [RecentDocumentEntry]
}

struct RecentDocumentStore {
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
            .appendingPathComponent("recent-documents.json")
    }

    func load() -> [RecentDocumentEntry] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let snapshot = try JSONDecoder.vibeWriteRecentDocumentDecoder.decode(RecentDocumentStoreSnapshot.self, from: data)
            return snapshot.entries
        } catch {
            return []
        }
    }

    func save(entries: [RecentDocumentEntry]) {
        let deduplicatedEntries = deduplicate(entries: entries)
        let snapshot = RecentDocumentStoreSnapshot(
            schemaVersion: 1,
            entries: deduplicatedEntries
        )

        do {
            try ensureStorageDirectoryExists()
            let data = try JSONEncoder.vibeWriteRecentDocumentEncoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }

    func clear() {
        save(entries: [])
    }

    private func ensureStorageDirectoryExists() throws {
        let parentDirectory = storageURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: parentDirectory.path) {
            return
        }

        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
    }

    private func deduplicate(entries: [RecentDocumentEntry]) -> [RecentDocumentEntry] {
        var seen = Set<String>()
        return entries
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .filter { seen.insert($0.url.absoluteString).inserted }
            .prefix(10)
            .map { $0 }
    }
}

private extension JSONEncoder {
    static var vibeWriteRecentDocumentEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var vibeWriteRecentDocumentDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
