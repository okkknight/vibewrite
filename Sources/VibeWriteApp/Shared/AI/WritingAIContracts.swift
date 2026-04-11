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
