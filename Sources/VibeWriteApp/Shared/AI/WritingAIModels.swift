import Foundation

protocol WritingAIClient: Sendable {
    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse
}

struct WritingAIRequest: Codable, Hashable {
    var action: WritingAIAction
    var project: WritingProjectSnapshot
    var userMessage: String?
    var selectionText: String?
}

struct WritingProjectSnapshot: Codable, Hashable {
    var id: UUID
    var automationKey: String
    var title: String
    var prompt: String
    var mode: WritingProjectMode
    var summary: String
    var context: ProjectContext
    var conversation: [ConversationMessage]
    var documentText: String
    var suggestionChips: [String]
    var updatedAt: Date
}

struct WritingAIResponse: Codable, Hashable {
    var assistantMessage: String
    var documentText: String
    var summary: String
    var intentSummary: String
    var styleConstraints: [String]
    var currentGoal: String
    var recentDecisions: [String]
    var workingMemory: [String]
    var nextFocus: String
    var suggestionChips: [String]
    var mode: WritingProjectMode
}

enum WritingAIAction: String, Codable, Hashable {
    case startDraft
    case submitMessage
    case selectionModify
    case expand
    case shorten
    case polish
    case continueWriting
    case proactiveSuggestion
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

enum WritingAIClientError: LocalizedError {
    case missingConfiguration
    case requestFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "缺少 MiniMax 配置。"
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
            summary: summary,
            context: context,
            conversation: conversation,
            documentText: documentText,
            suggestionChips: suggestionChips,
            updatedAt: updatedAt
        )
    }

    mutating func apply(aiResponse response: WritingAIResponse) {
        if mode != response.mode {
            mode = response.mode
        }

        documentText = response.documentText
        summary = response.summary
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
}
