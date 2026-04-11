import Foundation

public struct ProjectContext: Codable, Hashable, Sendable {
    public var intentSummary: String
    public var styleConstraints: [String]
    public var currentGoal: String
    public var recentDecisions: [String]
    public var workingMemory: [String]
    public var nextFocus: String

    public init(
        intentSummary: String,
        styleConstraints: [String],
        currentGoal: String,
        recentDecisions: [String],
        workingMemory: [String],
        nextFocus: String
    ) {
        self.intentSummary = intentSummary
        self.styleConstraints = styleConstraints
        self.currentGoal = currentGoal
        self.recentDecisions = recentDecisions
        self.workingMemory = workingMemory
        self.nextFocus = nextFocus
    }

    public static func discussion(prompt: String) -> ProjectContext {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = cleanedPrompt.isEmpty ? "当前主题" : "“\(cleanedPrompt)”"

        return ProjectContext(
            intentSummary: "用户想先围绕\(topic)达成写作共识，再开始起稿。",
            styleConstraints: ["克制", "平静", "非鸡汤"],
            currentGoal: "澄清起稿意图",
            recentDecisions: ["先确认内容类型", "先把语气压低"],
            workingMemory: ["主题尚未完全收束", "需要先建立起稿前共识"],
            nextFocus: "完成 3 到 5 个轻量追问"
        )
    }

    public static func collaboration(prompt: String) -> ProjectContext {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = cleanedPrompt.isEmpty ? "当前写作需求" : "“\(cleanedPrompt)”"

        return ProjectContext(
            intentSummary: "围绕\(topic)持续协作，正文会直接写入文档而不是停留在聊天里。",
            styleConstraints: ["克制", "平静", "非鸡汤", "避免说教"],
            currentGoal: cleanedPrompt.isEmpty ? "等待起稿需求" : "开始起稿",
            recentDecisions: cleanedPrompt.isEmpty ? ["先输入一句写作需求"] : ["先生成第一稿", "把正文直接写进文档"],
            workingMemory: cleanedPrompt.isEmpty ? ["当前还没有明确题目"] : ["正文还在生成中", "后续修改会继续围绕当前主线"],
            nextFocus: cleanedPrompt.isEmpty ? "先补一个起稿需求" : "生成第一稿后继续收紧开头"
        )
    }
}

public struct WritingTextSelectionRange: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = max(location, 0)
        self.length = max(length, 0)
    }

    public init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    public var isEmpty: Bool {
        length <= 0
    }

    public var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    public func range(in text: String) -> Range<String.Index>? {
        Range(nsRange, in: text)
    }

    public func substring(in text: String) -> String? {
        guard let range = range(in: text) else {
            return nil
        }

        return String(text[range])
    }
}

public struct ConversationMessage: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public let text: String
    public let timestamp: String

    public init(id: UUID = UUID(), role: MessageRole, text: String, timestamp: String) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

public enum MessageRole: Hashable, Codable, Sendable {
    case user
    case assistant

    public var displayName: String {
        switch self {
        case .user: return "用户"
        case .assistant: return "AI"
        }
    }
}

public enum WritingProjectMode: String, Hashable, Codable, Sendable {
    case discussion
    case collaboration

    public var defaultTitle: String {
        switch self {
        case .discussion: return "新建写作"
        case .collaboration: return "未命名写作"
        }
    }

    public var stageTitle: String {
        switch self {
        case .discussion: return "起稿中"
        case .collaboration: return "正文协作中"
        }
    }

    public var stageDescription: String {
        switch self {
        case .discussion: return "正在生成第一稿"
        case .collaboration: return "围绕灵感持续写作"
        }
    }
}
