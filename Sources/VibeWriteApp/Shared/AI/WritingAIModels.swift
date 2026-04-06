import Foundation

protocol WritingAIClient: Sendable {
    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse
    func streamResponse(for request: WritingAIRequest) -> AsyncThrowingStream<WritingAIStreamEvent, Error>
}

enum WritingAIStreamEvent: Sendable, Hashable {
    case textDelta(String)
    case completed(WritingAIResponse)
}

struct WritingAIRequest: Codable, Hashable {
    var action: WritingAIAction
    var project: WritingProjectSnapshot
    var userMessage: String?
    var selectionText: String?
    var selectionRange: WritingTextSelectionRange? = nil
    var kind: WritingAIRequestKind = .prose
}

enum WritingAIRequestKind: String, Codable, Hashable {
    case prose
    case metadata
}

struct WritingProjectSnapshot: Codable, Hashable {
    var id: UUID
    var automationKey: String
    var title: String
    var prompt: String
    var mode: WritingProjectMode
    var localSummary: String
    var globalSynopsis: String = ""
    var context: ProjectContext
    var conversation: [ConversationMessage]
    var documentText: String
    var suggestionChips: [String]
    var updatedAt: Date
}

struct WritingAIResponse: Codable, Hashable {
    var assistantMessage: String
    var documentText: String
    var localSummary: String
    var globalSynopsis: String
    var intentSummary: String
    var styleConstraints: [String]
    var currentGoal: String
    var recentDecisions: [String]
    var workingMemory: [String]
    var nextFocus: String
    var suggestionChips: [String]
    var mode: WritingProjectMode

    var completionMetadata: WritingAICompletionMetadata {
        WritingAICompletionMetadata(
            localSummary: localSummary,
            globalSynopsis: globalSynopsis,
            nextFocus: nextFocus,
            suggestionChips: suggestionChips
        )
    }
}

struct WritingAICompletionMetadata: Codable, Hashable {
    var localSummary: String
    var globalSynopsis: String
    var nextFocus: String
    var suggestionChips: [String]
}

enum WritingAIAction: String, Codable, Hashable {
    case startDraft
    case continueWriting
    case edit
}

struct WritingAIChatMessage: Codable, Hashable {
    enum Role: String, Codable, Hashable {
        case system
        case user
        case assistant
    }

    var role: Role
    var content: String
}

enum WritingAIResponseDecoder {
    static func decode(from rawContent: String) throws -> WritingAIResponse {
        let sanitized = sanitize(rawContent)
        guard let data = sanitized.data(using: .utf8) else {
            throw WritingAIClientError.invalidResponse("AI response could not be converted to UTF-8")
        }

        do {
            return try JSONDecoder.vibeWriteAIResponseDecoder.decode(WritingAIResponse.self, from: data)
        } catch {
            throw WritingAIClientError.invalidResponse("AI response was not valid JSON")
        }
    }

    private static func sanitize(_ rawContent: String) -> String {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let withoutFences = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
            return extractJSONObject(from: withoutFences.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return extractJSONObject(from: trimmed)
    }

    private static func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return text
        }

        return String(text[start...end])
    }
}

enum WritingAICompletionMetadataDecoder {
    static func decode(from rawContent: String) throws -> WritingAICompletionMetadata {
        let sanitized = sanitize(rawContent)
        guard let data = sanitized.data(using: .utf8) else {
            throw WritingAIClientError.invalidResponse("AI completion metadata could not be converted to UTF-8")
        }

        do {
            return try JSONDecoder.vibeWriteAIResponseDecoder.decode(WritingAICompletionMetadata.self, from: data)
        } catch {
            throw WritingAIClientError.invalidResponse("AI completion metadata was not valid JSON")
        }
    }

    private static func sanitize(_ rawContent: String) -> String {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let withoutFences = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
            return extractJSONObject(from: withoutFences.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return extractJSONObject(from: trimmed)
    }

    private static func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return text
        }

        return String(text[start...end])
    }
}

enum WritingAIClientError: LocalizedError {
    case missingConfiguration
    case invalidConfiguration(String)
    case requestFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "缺少 MiniMax 配置，请检查本地 bundle 或 xcconfig。"
        case .invalidConfiguration(let message):
            return message
        case .requestFailed(let message):
            return message
        case .invalidResponse(let message):
            return message
        }
    }
}

private extension JSONDecoder {
    static var vibeWriteAIResponseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension WritingProject {
    var aiSnapshot: WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: id,
            automationKey: automationKey,
            title: title,
            prompt: prompt,
            mode: mode,
            localSummary: localSummary,
            globalSynopsis: globalSynopsis,
            context: context,
            conversation: conversation,
            documentText: documentText,
            suggestionChips: suggestionChips,
            updatedAt: updatedAt
        )
    }

    mutating func apply(aiResponse response: WritingAIResponse, documentText: String) {
        if mode != response.mode {
            mode = response.mode
        }

        self.documentText = documentText
        localSummary = response.localSummary
        globalSynopsis = response.globalSynopsis
        intentSummary = response.intentSummary
        styleConstraints = response.styleConstraints
        currentGoal = response.currentGoal
        recentDecisions = response.recentDecisions
        workingMemory = response.workingMemory
        nextFocus = response.nextFocus
        suggestionChips = response.suggestionChips
        conversation.append(
            ConversationMessage(
                role: .assistant,
                text: response.assistantMessage,
                timestamp: "AI · 刚刚"
            )
        )
        refreshUpdatedAt()
    }

    mutating func applyWritingProseResponse(_ response: WritingAIResponse, documentText: String) {
        if mode != response.mode {
            mode = response.mode
        }

        self.documentText = documentText
        conversation.append(
            ConversationMessage(
                role: .assistant,
                text: response.assistantMessage,
                timestamp: "AI · 刚刚"
            )
        )
        refreshUpdatedAt()
    }

    mutating func applyWritingMetadata(_ metadata: WritingAICompletionMetadata) {
        localSummary = metadata.localSummary
        globalSynopsis = metadata.globalSynopsis
        nextFocus = metadata.nextFocus
        suggestionChips = metadata.suggestionChips
        refreshUpdatedAt()
    }

    mutating func applyEditingResponse(_ response: WritingAIResponse, documentText: String) {
        let existingSuggestionChips = suggestionChips
        let shouldPreserveExistingSuggestionChips = hasRenderableSuggestionChips(existingSuggestionChips)

        apply(aiResponse: response, documentText: documentText)

        if shouldPreserveExistingSuggestionChips {
            suggestionChips = existingSuggestionChips
            refreshUpdatedAt()
        }
    }

    func responseMetadata() -> WritingAICompletionMetadata {
        WritingAICompletionMetadata(
            localSummary: responseValue(localSummary: localSummary),
            globalSynopsis: responseValue(globalSynopsis: globalSynopsis),
            nextFocus: responseValue(nextFocus: context.nextFocus),
            suggestionChips: normalizedResponseSuggestionChips(suggestionChips)
        )
    }

    mutating func appendUserMessage(_ text: String) {
        conversation.append(
            ConversationMessage(
                role: .user,
                text: text,
                timestamp: "用户 · 刚刚"
            )
        )
        refreshUpdatedAt()
    }

    private func responseValue(localSummary value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func responseValue(globalSynopsis value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func responseValue(nextFocus value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedResponseSuggestionChips(_ chips: [String]) -> [String] {
        var seen = Set<String>()
        return chips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private func hasRenderableSuggestionChips(_ chips: [String]) -> Bool {
        chips.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

extension WritingAIResponse {
    func snapshotByApplyingDocumentText(
        _ documentText: String,
        to base: WritingProjectSnapshot
    ) -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: base.id,
            automationKey: base.automationKey,
            title: base.title,
            prompt: base.prompt,
            mode: mode,
            localSummary: localSummary,
            globalSynopsis: globalSynopsis,
            context: ProjectContext(
                intentSummary: intentSummary,
                styleConstraints: styleConstraints,
                currentGoal: currentGoal,
                recentDecisions: recentDecisions,
                workingMemory: workingMemory,
                nextFocus: nextFocus
            ),
            conversation: base.conversation,
            documentText: documentText,
            suggestionChips: suggestionChips,
            updatedAt: base.updatedAt
        )
    }
}

extension WritingAIClient {
    func streamResponse(for request: WritingAIRequest) -> AsyncThrowingStream<WritingAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await generateResponse(for: request)
                    continuation.yield(.textDelta(response.documentText))
                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        var finalResponse: WritingAIResponse?

        for try await event in streamResponse(for: request) {
            if case .completed(let response) = event {
                finalResponse = response
            }
        }

        guard let finalResponse else {
            throw WritingAIClientError.invalidResponse("AI stream did not produce a final response.")
        }

        return finalResponse
    }
}
