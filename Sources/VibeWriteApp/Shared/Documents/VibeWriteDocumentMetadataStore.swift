import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum VibeWriteDocumentMetadataPolicy {
    static let schemaVersion = 2
    static let collaborationStoreSchemaVersion = 3
    static let conversationRoundLimit = 20
    static let conversationMessageLimit = conversationRoundLimit * 2
    static let xattrKey = "com.vibewrite.document-identity"
}

struct VibeWriteDocumentMetadataRecord: Codable, Hashable {
    var schemaVersion: Int
    var documentID: UUID
    var automationKey: String
    var title: String
    var prompt: String
    var mode: WritingProjectMode
    var localSummary: String
    var globalSynopsis: String
    var context: ProjectContext
    var conversation: [ConversationMessage]
    var revisionHistory: [WritingProjectRevision]
    var suggestionChips: [String]
    var updatedAt: Date
}

struct VibeWriteDocumentMetadataStoreSnapshot: Codable, Hashable {
    var schemaVersion: Int
    var records: [VibeWriteDocumentMetadataRecord]
}

struct VibeWriteDocumentMetadataStore {
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
            .appendingPathComponent("document-collaboration-store.json")
    }

    func load() -> VibeWriteDocumentMetadataStoreSnapshot? {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let snapshot = try JSONDecoder.vibeWriteDocumentMetadataDecoder.decode(VibeWriteDocumentMetadataStoreSnapshot.self, from: data)
            guard snapshot.schemaVersion == VibeWriteDocumentMetadataPolicy.collaborationStoreSchemaVersion else {
                return nil
            }

            return snapshot
        } catch {
            return nil
        }
    }

    func loadRecord(documentID: UUID) -> VibeWriteDocumentMetadataRecord? {
        load()?.records.first(where: { $0.documentID == documentID && $0.schemaVersion == VibeWriteDocumentMetadataPolicy.collaborationStoreSchemaVersion })
    }

    func save(project: WritingProject, documentID: UUID? = nil) {
        let record = VibeWriteDocumentMetadataRecord(
            schemaVersion: VibeWriteDocumentMetadataPolicy.collaborationStoreSchemaVersion,
            documentID: documentID ?? project.id,
            automationKey: project.automationKey,
            title: project.title,
            prompt: project.prompt,
            mode: project.mode,
            localSummary: project.localSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            globalSynopsis: project.globalSynopsis.trimmingCharacters(in: .whitespacesAndNewlines),
            context: project.context,
            conversation: Array(project.conversation.suffix(VibeWriteDocumentMetadataPolicy.conversationMessageLimit)),
            revisionHistory: project.revisionHistory,
            suggestionChips: normalizedSuggestionChips(project.suggestionChips),
            updatedAt: project.updatedAt
        )

        save(record: record)
    }

    func save(record: VibeWriteDocumentMetadataRecord) {
        var snapshot = load() ?? VibeWriteDocumentMetadataStoreSnapshot(
            schemaVersion: VibeWriteDocumentMetadataPolicy.collaborationStoreSchemaVersion,
            records: []
        )

        let normalizedRecord = normalize(record)
        snapshot.records.removeAll { $0.documentID == normalizedRecord.documentID }
        snapshot.records.append(normalizedRecord)
        snapshot.records.sort { $0.updatedAt > $1.updatedAt }
        snapshot.schemaVersion = VibeWriteDocumentMetadataPolicy.collaborationStoreSchemaVersion

        do {
            try ensureStorageDirectoryExists()
            let data = try JSONEncoder.vibeWriteDocumentMetadataEncoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }

    func clear() {
        do {
            try ensureStorageDirectoryExists()
            let emptySnapshot = VibeWriteDocumentMetadataStoreSnapshot(
                schemaVersion: VibeWriteDocumentMetadataPolicy.collaborationStoreSchemaVersion,
                records: []
            )
            let data = try JSONEncoder.vibeWriteDocumentMetadataEncoder.encode(emptySnapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }

    func delete(documentID: UUID) {
        guard var snapshot = load() else {
            return
        }

        snapshot.records.removeAll { $0.documentID == documentID }
        do {
            try ensureStorageDirectoryExists()
            let data = try JSONEncoder.vibeWriteDocumentMetadataEncoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }

    private func normalize(_ record: VibeWriteDocumentMetadataRecord) -> VibeWriteDocumentMetadataRecord {
        VibeWriteDocumentMetadataRecord(
            schemaVersion: VibeWriteDocumentMetadataPolicy.collaborationStoreSchemaVersion,
            documentID: record.documentID,
            automationKey: record.automationKey.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty(record.documentID.uuidString.lowercased()) ?? record.documentID.uuidString.lowercased(),
            title: record.title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: record.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: record.mode,
            localSummary: record.localSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            globalSynopsis: record.globalSynopsis.trimmingCharacters(in: .whitespacesAndNewlines),
            context: record.context,
            conversation: Array(record.conversation.suffix(VibeWriteDocumentMetadataPolicy.conversationMessageLimit)),
            revisionHistory: record.revisionHistory,
            suggestionChips: normalizedSuggestionChips(record.suggestionChips),
            updatedAt: record.updatedAt
        )
    }

    private func ensureStorageDirectoryExists() throws {
        let parentDirectory = storageURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: parentDirectory.path) {
            return
        }

        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
    }

    private func normalizedSuggestionChips(_ chips: [String]) -> [String] {
        var seen = Set<String>()
        return chips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

struct VibeWriteDocumentIdentityStore {
    static let attributeName = VibeWriteDocumentMetadataPolicy.xattrKey

    func readDocumentID(from url: URL) -> VibeWriteDocumentIdentityMarker? {
        guard let data = readAttributeData(from: url) else {
            return nil
        }

        guard let marker = try? JSONDecoder.vibeWriteDocumentIdentityDecoder.decode(VibeWriteDocumentIdentityMarker.self, from: data),
              marker.schemaVersion == VibeWriteDocumentMetadataPolicy.schemaVersion else {
            return nil
        }

        return marker
    }

    @discardableResult
    func writeDocumentID(_ marker: VibeWriteDocumentIdentityMarker, to url: URL) -> Bool {
        guard let data = try? JSONEncoder.vibeWriteDocumentIdentityEncoder.encode(marker) else {
            return false
        }

        return writeAttributeData(data, to: url)
    }

    private func readAttributeData(from url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else {
                return nil
            }

            let size = getxattr(path, Self.attributeName, nil, 0, 0, 0)
            guard size > 0 else {
                return nil
            }

            var data = Data(count: size)
            let readSize = data.withUnsafeMutableBytes { buffer -> ssize_t in
                guard let baseAddress = buffer.baseAddress else {
                    return -1
                }

                return getxattr(path, Self.attributeName, baseAddress, buffer.count, 0, 0)
            }

            guard readSize > 0 else {
                return nil
            }

            data.count = readSize
            return data
        }
    }

    private func writeAttributeData(_ data: Data, to url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else {
                return false
            }

            return data.withUnsafeBytes { buffer -> Bool in
                guard let baseAddress = buffer.baseAddress else {
                    return false
                }

                return setxattr(path, Self.attributeName, baseAddress, buffer.count, 0, 0) == 0
            }
        }
    }
}

extension VibeWriteDocumentMetadataRecord {
    func makeProject(documentText: String, fallbackTitle: String? = nil, fallbackAutomationKey: String? = nil) -> WritingProject {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanedTitle.ifEmpty(fallbackTitle) ?? mode.defaultTitle
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAutomationKey = automationKey.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty(fallbackAutomationKey) ?? documentID.uuidString.lowercased()
        let defaultSummary = VibeWriteMarkdownDocument.defaultSummary(prompt: cleanedPrompt, body: documentText, mode: mode)
        let cleanedLocalSummary = localSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLocalSummary = cleanedLocalSummary.ifEmpty(defaultSummary) ?? defaultSummary
        let cleanedGlobalSynopsis = globalSynopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedGlobalSynopsis = cleanedGlobalSynopsis.ifEmpty(resolvedLocalSummary) ?? resolvedLocalSummary

        return WritingProject(
            id: documentID,
            automationKey: resolvedAutomationKey,
            title: resolvedTitle,
            prompt: cleanedPrompt,
            mode: mode,
            localSummary: resolvedLocalSummary,
            globalSynopsis: resolvedGlobalSynopsis,
            context: context,
            conversation: Array(conversation.suffix(VibeWriteDocumentMetadataPolicy.conversationMessageLimit)),
            documentText: documentText,
            suggestionChips: normalizedSuggestionChips(suggestionChips),
            revisionHistory: revisionHistory,
            updatedAt: updatedAt
        )
    }

    private func normalizedSuggestionChips(_ chips: [String]) -> [String] {
        var seen = Set<String>()
        return chips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

extension WritingProject {
    func forkedSaveAsCopy() -> WritingProject {
        let newID = UUID()
        return WritingProject(
            id: newID,
            automationKey: newID.uuidString.lowercased(),
            title: title,
            prompt: prompt,
            mode: mode,
            localSummary: localSummary,
            globalSynopsis: globalSynopsis,
            context: context,
            conversation: conversation,
            documentText: documentText,
            suggestionChips: suggestionChips,
            revisionHistory: revisionHistory,
            updatedAt: .now
        )
    }
}

private extension JSONEncoder {
    static var vibeWriteDocumentMetadataEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var vibeWriteDocumentIdentityEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var vibeWriteDocumentMetadataDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var vibeWriteDocumentIdentityDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    func ifEmpty(_ fallback: String?) -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
