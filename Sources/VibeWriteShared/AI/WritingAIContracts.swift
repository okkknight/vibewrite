import Foundation

public protocol WritingAIClient: Sendable {
    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse
    func streamResponse(for request: WritingAIRequest) -> AsyncThrowingStream<WritingAIStreamEvent, Error>
}

public enum WritingAIStreamEvent: Sendable, Hashable {
    case textDelta(String)
    case completed(WritingAIResponse)
}

extension WritingAIStreamEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case textDelta
        case response
    }

    private enum EventType: String, Codable {
        case textDelta
        case completed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .textDelta(let value):
            try container.encode(EventType.textDelta, forKey: .type)
            try container.encode(value, forKey: .textDelta)
        case .completed(let response):
            try container.encode(EventType.completed, forKey: .type)
            try container.encode(response, forKey: .response)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventType = try container.decode(EventType.self, forKey: .type)
        switch eventType {
        case .textDelta:
            self = .textDelta(try container.decode(String.self, forKey: .textDelta))
        case .completed:
            self = .completed(try container.decode(WritingAIResponse.self, forKey: .response))
        }
    }
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

public struct WritingGatewaySessionContext: Codable, Hashable, Sendable {
    public var title: String
    public var prompt: String
    public var mode: WritingProjectMode
    public var localSummary: String
    public var globalSynopsis: String
    public var context: ProjectContext
    public var suggestionChips: [String]

    public init(
        title: String,
        prompt: String,
        mode: WritingProjectMode,
        localSummary: String,
        globalSynopsis: String,
        context: ProjectContext,
        suggestionChips: [String]
    ) {
        self.title = title
        self.prompt = prompt
        self.mode = mode
        self.localSummary = localSummary
        self.globalSynopsis = globalSynopsis
        self.context = context
        self.suggestionChips = suggestionChips
    }
}

public struct WritingGatewayTailWindow: Codable, Hashable, Sendable {
    public var tailText: String
    public var totalCharacterCount: Int
    public var tailCharacterCount: Int
    public var isTruncated: Bool

    public init(
        tailText: String,
        totalCharacterCount: Int,
        tailCharacterCount: Int,
        isTruncated: Bool
    ) {
        self.tailText = tailText
        self.totalCharacterCount = max(totalCharacterCount, 0)
        self.tailCharacterCount = max(tailCharacterCount, 0)
        self.isTruncated = isTruncated
    }
}

public enum WritingGatewayEditWindowStrategy: String, Codable, Hashable, Sendable {
    case focused
    case expanded
}

public struct WritingGatewayEditWindow: Codable, Hashable, Sendable {
    public var beforeContextText: String
    public var selectionText: String
    public var afterContextText: String
    public var totalCharacterCount: Int
    public var windowCharacterCount: Int
    public var strategy: WritingGatewayEditWindowStrategy

    public init(
        beforeContextText: String,
        selectionText: String,
        afterContextText: String,
        totalCharacterCount: Int,
        windowCharacterCount: Int,
        strategy: WritingGatewayEditWindowStrategy
    ) {
        self.beforeContextText = beforeContextText
        self.selectionText = selectionText
        self.afterContextText = afterContextText
        self.totalCharacterCount = max(totalCharacterCount, 0)
        self.windowCharacterCount = max(windowCharacterCount, 0)
        self.strategy = strategy
    }

    public var windowText: String {
        beforeContextText + selectionText + afterContextText
    }

    public var localSelectionRange: WritingTextSelectionRange {
        WritingTextSelectionRange(
            location: beforeContextText.utf16.count,
            length: selectionText.utf16.count
        )
    }
}

public struct WritingGatewayWriteEnvelope: Codable, Hashable, Sendable {
    public var installationId: String
    public var deviceToken: String
    public var requestId: String
    public var action: WritingAIAction
    public var kind: WritingAIRequestKind
    public var startProject: WritingProjectSnapshot?
    public var sessionContext: WritingGatewaySessionContext?
    public var continueWindow: WritingGatewayTailWindow?
    public var editWindow: WritingGatewayEditWindow?
    public var userMessage: String?

    public init(
        installationId: String,
        deviceToken: String,
        requestId: String,
        action: WritingAIAction,
        kind: WritingAIRequestKind,
        startProject: WritingProjectSnapshot? = nil,
        sessionContext: WritingGatewaySessionContext? = nil,
        continueWindow: WritingGatewayTailWindow? = nil,
        editWindow: WritingGatewayEditWindow? = nil,
        userMessage: String? = nil
    ) {
        self.installationId = installationId
        self.deviceToken = deviceToken
        self.requestId = requestId
        self.action = action
        self.kind = kind
        self.startProject = startProject
        self.sessionContext = sessionContext
        self.continueWindow = continueWindow
        self.editWindow = editWindow
        self.userMessage = userMessage
    }
}

public struct WritingGatewayResponse: Codable, Hashable, Sendable {
    public var assistantMessage: String
    public var documentText: String?
    public var appendedText: String?
    public var replacementText: String?
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
        documentText: String? = nil,
        appendedText: String? = nil,
        replacementText: String? = nil,
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
        self.appendedText = appendedText
        self.replacementText = replacementText
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
}

public enum WritingGatewayStreamEvent: Sendable, Hashable {
    case textDelta(String)
    case completed(WritingGatewayResponse)
}

extension WritingGatewayStreamEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case textDelta
        case response
    }

    private enum EventType: String, Codable {
        case textDelta
        case completed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .textDelta(let value):
            try container.encode(EventType.textDelta, forKey: .type)
            try container.encode(value, forKey: .textDelta)
        case .completed(let response):
            try container.encode(EventType.completed, forKey: .type)
            try container.encode(response, forKey: .response)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventType = try container.decode(EventType.self, forKey: .type)
        switch eventType {
        case .textDelta:
            self = .textDelta(try container.decode(String.self, forKey: .textDelta))
        case .completed:
            self = .completed(try container.decode(WritingGatewayResponse.self, forKey: .response))
        }
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
