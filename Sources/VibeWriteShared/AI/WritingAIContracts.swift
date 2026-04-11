import Foundation

public protocol WritingAIClient: Sendable {
    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse
    func streamResponse(for request: WritingAIRequest) -> AsyncThrowingStream<WritingAIStreamEvent, Error>
}

public enum WritingAIStreamEvent: Sendable, Hashable {
    case textDelta(String)
    case completed(WritingAIResponse)
}

public struct WritingAIRequest: Codable, Hashable, Sendable {
    public var action: WritingAIAction
    public var project: WritingProjectSnapshot
    public var userMessage: String?
    public var selectionText: String?
    public var selectionRange: WritingTextSelectionRange? = nil
    public var kind: WritingAIRequestKind = .prose

    public init(
        action: WritingAIAction,
        project: WritingProjectSnapshot,
        userMessage: String?,
        selectionText: String?,
        selectionRange: WritingTextSelectionRange? = nil,
        kind: WritingAIRequestKind = .prose
    ) {
        self.action = action
        self.project = project
        self.userMessage = userMessage
        self.selectionText = selectionText
        self.selectionRange = selectionRange
        self.kind = kind
    }
}

public enum WritingAIRequestKind: String, Codable, Hashable, Sendable {
    case prose
    case metadata
}

public struct WritingProjectSnapshot: Codable, Hashable, Sendable {
    public var id: UUID
    public var automationKey: String
    public var title: String
    public var prompt: String
    public var mode: WritingProjectMode
    public var localSummary: String
    public var globalSynopsis: String = ""
    public var context: ProjectContext
    public var conversation: [ConversationMessage]
    public var documentText: String
    public var suggestionChips: [String]
    public var updatedAt: Date

    public init(
        id: UUID,
        automationKey: String,
        title: String,
        prompt: String,
        mode: WritingProjectMode,
        localSummary: String,
        globalSynopsis: String = "",
        context: ProjectContext,
        conversation: [ConversationMessage],
        documentText: String,
        suggestionChips: [String],
        updatedAt: Date
    ) {
        self.id = id
        self.automationKey = automationKey
        self.title = title
        self.prompt = prompt
        self.mode = mode
        self.localSummary = localSummary
        self.globalSynopsis = globalSynopsis
        self.context = context
        self.conversation = conversation
        self.documentText = documentText
        self.suggestionChips = suggestionChips
        self.updatedAt = updatedAt
    }
}

public struct WritingAIResponse: Codable, Hashable, Sendable {
    public var assistantMessage: String
    public var documentText: String
    public var localSummary: String
    public var globalSynopsis: String
    public var intentSummary: String
    public var styleConstraints: [String]
    public var currentGoal: String
    public var recentDecisions: [String]
    public var workingMemory: [String]
    public var nextFocus: String
    public var suggestionChips: [String]
    public var mode: WritingProjectMode

    public init(
        assistantMessage: String,
        documentText: String,
        localSummary: String,
        globalSynopsis: String,
        intentSummary: String,
        styleConstraints: [String],
        currentGoal: String,
        recentDecisions: [String],
        workingMemory: [String],
        nextFocus: String,
        suggestionChips: [String],
        mode: WritingProjectMode
    ) {
        self.assistantMessage = assistantMessage
        self.documentText = documentText
        self.localSummary = localSummary
        self.globalSynopsis = globalSynopsis
        self.intentSummary = intentSummary
        self.styleConstraints = styleConstraints
        self.currentGoal = currentGoal
        self.recentDecisions = recentDecisions
        self.workingMemory = workingMemory
        self.nextFocus = nextFocus
        self.suggestionChips = suggestionChips
        self.mode = mode
    }

    public var completionMetadata: WritingAICompletionMetadata {
        WritingAICompletionMetadata(
            localSummary: localSummary,
            globalSynopsis: globalSynopsis,
            nextFocus: nextFocus,
            suggestionChips: suggestionChips
        )
    }
}

public struct WritingAICompletionMetadata: Codable, Hashable, Sendable {
    public var localSummary: String
    public var globalSynopsis: String
    public var nextFocus: String
    public var suggestionChips: [String]

    public init(
        localSummary: String,
        globalSynopsis: String,
        nextFocus: String,
        suggestionChips: [String]
    ) {
        self.localSummary = localSummary
        self.globalSynopsis = globalSynopsis
        self.nextFocus = nextFocus
        self.suggestionChips = suggestionChips
    }
}

public enum WritingAIAction: String, Codable, Hashable, Sendable {
    case startDraft
    case continueWriting
    case edit
}

public struct WritingAIChatMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Hashable, Sendable {
        case system
        case user
        case assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}
