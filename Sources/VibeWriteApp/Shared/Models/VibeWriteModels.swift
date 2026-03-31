import Foundation

struct ProjectContext: Codable, Hashable {
    var intentSummary: String
    var styleConstraints: [String]
    var currentGoal: String
    var recentDecisions: [String]
    var workingMemory: [String]
    var nextFocus: String

    static func discussion(prompt: String) -> ProjectContext {
        ProjectContext(
            intentSummary: "用户想先围绕“\(prompt)”达成写作共识，再开始起稿。",
            styleConstraints: ["克制", "平静", "非鸡汤"],
            currentGoal: "澄清起稿意图",
            recentDecisions: ["先确认内容类型", "先把语气压低"],
            workingMemory: ["主题尚未完全收束", "需要先建立起稿前共识"],
            nextFocus: "完成 3 到 5 个轻量追问"
        )
    }

    static func collaboration(prompt: String) -> ProjectContext {
        ProjectContext(
            intentSummary: "围绕“\(prompt)”持续协作，正文会直接写入文档而不是停留在聊天里。",
            styleConstraints: ["克制", "平静", "非鸡汤", "避免说教"],
            currentGoal: "收紧开头",
            recentDecisions: ["开头不要直白", "情绪不要起太快"],
            workingMemory: ["当前重点是开头和第一段情绪节奏"],
            nextFocus: "继续推进第一段"
        )
    }
}

struct WritingProject: Identifiable, Hashable, Codable {
    let id: UUID
    var automationKey: String { didSet { touch() } }
    var title: String { didSet { touch() } }
    var prompt: String { didSet { touch() } }
    var mode: WritingProjectMode { didSet { touch() } }
    var summary: String { didSet { touch() } }
    var context: ProjectContext { didSet { touch() } }
    var conversation: [ConversationMessage] { didSet { touch() } }
    var documentText: String { didSet { touch() } }
    var suggestionChips: [String] { didSet { touch() } }
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        automationKey: String? = nil,
        title: String,
        prompt: String,
        mode: WritingProjectMode,
        summary: String,
        context: ProjectContext,
        conversation: [ConversationMessage],
        documentText: String,
        suggestionChips: [String],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.automationKey = automationKey ?? id.uuidString.lowercased()
        self.title = title
        self.prompt = prompt
        self.mode = mode
        self.summary = summary
        self.context = context
        self.conversation = conversation
        self.documentText = documentText
        self.suggestionChips = suggestionChips
        self.updatedAt = updatedAt
    }

    static func quickStart(prompt: String, mode: WritingProjectMode, automationKey: String? = nil) -> WritingProject {
        let title = titleFromPrompt(prompt, fallback: mode.defaultTitle)
        let now = Date()

        switch mode {
        case .discussion:
            return WritingProject(
                automationKey: automationKey,
                title: title,
                prompt: prompt,
                mode: mode,
                summary: "先把方向聊清楚，再生成第一稿",
                context: .discussion(prompt: prompt),
                conversation: [
                    ConversationMessage(role: .assistant, text: "你想写什么类型的内容？", timestamp: "AI · 刚刚"),
                    ConversationMessage(role: .user, text: prompt, timestamp: "用户 · 刚刚"),
                    ConversationMessage(role: .assistant, text: "我会先帮你把方向收紧，再开始起稿。", timestamp: "AI · 刚刚")
                ],
                documentText: "",
                suggestionChips: ["明确主题", "确认语气", "开始起稿"],
                updatedAt: now
            )

        case .collaboration:
            return WritingProject(
                automationKey: automationKey,
                title: title,
                prompt: prompt,
                mode: mode,
                summary: "已进入正文协作，正在收紧开头和语气",
                context: .collaboration(prompt: prompt),
                conversation: [
                    ConversationMessage(role: .user, text: prompt, timestamp: "用户 · 刚刚"),
                    ConversationMessage(role: .assistant, text: "我先把开头收紧一点，让情绪慢慢出来。", timestamp: "AI · 刚刚"),
                    ConversationMessage(role: .assistant, text: "要不要我继续往下补下一段，也可以先把第二段压低一点。", timestamp: "AI · 刚刚")
                ],
                documentText: """
                成年人真正感到孤独的时候，未必是在深夜。
                更多时候，是在一个很普通的傍晚，手机亮了又暗，微信里有人说了几句不咸不淡的话，你礼貌地回完，然后突然意识到，自己已经很久没有真正想找谁说话。

                这种孤独并不轰烈，也不尖锐。它不像失去那样有明确的边界，更像是生活在某一刻忽然空了一下，你很清楚它在那里，却又没法把它完整说出来。
                """,
                suggestionChips: ["调整语气", "继续展开", "收紧结尾", "降低解释感"],
                updatedAt: now
            )
        }
    }

    var updatedLabel: String {
        Self.relativeLabel(for: updatedAt)
    }

    mutating func refreshUpdatedAt() {
        updatedAt = .now
    }

    var intentSummary: String {
        get { context.intentSummary }
        set {
            context.intentSummary = newValue
            touch()
        }
    }

    var currentGoal: String {
        get { context.currentGoal }
        set {
            context.currentGoal = newValue
            touch()
        }
    }

    var nextFocus: String {
        get { context.nextFocus }
        set {
            context.nextFocus = newValue
            touch()
        }
    }

    var styleConstraints: [String] {
        get { context.styleConstraints }
        set {
            context.styleConstraints = newValue
            touch()
        }
    }

    var recentDecisions: [String] {
        get { context.recentDecisions }
        set {
            context.recentDecisions = newValue
            touch()
        }
    }

    var workingMemory: [String] {
        get { context.workingMemory }
        set {
            context.workingMemory = newValue
            touch()
        }
    }

    private mutating func touch() {
        updatedAt = .now
    }

    private static func titleFromPrompt(_ prompt: String, fallback: String) -> String {
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return fallback }

        if cleaned.count <= 12 {
            return cleaned
        }

        return String(cleaned.prefix(10)) + "…"
    }

    private static func relativeLabel(for date: Date) -> String {
        let interval = Int(Date().timeIntervalSince(date))
        if interval < 60 {
            return "刚刚"
        }

        let minutes = interval / 60
        if minutes < 60 {
            return "\(minutes) 分钟前"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) 小时前"
        }

        let days = hours / 24
        if days < 30 {
            return "\(days) 天前"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }
}

struct ConversationMessage: Identifiable, Hashable, Codable {
    let id: UUID
    let role: MessageRole
    let text: String
    let timestamp: String

    init(id: UUID = UUID(), role: MessageRole, text: String, timestamp: String) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

enum MessageRole: Hashable, Codable {
    case user
    case assistant

    var displayName: String {
        switch self {
        case .user: return "用户"
        case .assistant: return "AI"
        }
    }
}

enum WritingProjectMode: String, Hashable, Codable {
    case discussion
    case collaboration

    var defaultTitle: String {
        switch self {
        case .discussion: return "新建写作"
        case .collaboration: return "未命名写作"
        }
    }

    var stageTitle: String {
        switch self {
        case .discussion: return "讨论起稿中"
        case .collaboration: return "正文协作中"
        }
    }

    var stageDescription: String {
        switch self {
        case .discussion: return "先聊清楚，再生成第一稿"
        case .collaboration: return "围绕当前正文持续导演"
        }
    }
}

enum WorkspaceFixtures {
    static func bootstrapProjects(now: Date = .now) -> [WritingProject] {
        [
            WritingProject(
                automationKey: "project-001",
                title: "成年人孤独感",
                prompt: "写一篇关于成年人孤独感的公众号文章",
                mode: .collaboration,
                summary: "语气克制的长文随笔，当前在收紧开头",
                context: ProjectContext(
                    intentSummary: "围绕成年人孤独感，写一篇平静、克制、不说教的长文。",
                    styleConstraints: ["克制", "平静", "非鸡汤"],
                    currentGoal: "收紧开头",
                    recentDecisions: ["开头不要直接下结论", "语气保持安静"],
                    workingMemory: ["当前重点是开头和第一段情绪节奏"],
                    nextFocus: "继续推进第一段"
                ),
                conversation: [
                    ConversationMessage(role: .user, text: "写一篇关于成年人孤独感的公众号文章，不要鸡汤，要更克制一点。", timestamp: "用户 · 2 小时前"),
                    ConversationMessage(role: .assistant, text: "我先把开头收紧，并让情绪慢一点出来。", timestamp: "AI · 2 小时前")
                ],
                documentText: "成年人真正感到孤独的时候，未必是在深夜。\n更多时候，是在一个很普通的傍晚……",
                suggestionChips: ["调整语气", "继续展开", "收紧结尾"],
                updatedAt: now.addingTimeInterval(-7200)
            ),
            WritingProject(
                automationKey: "project-002",
                title: "雨夜重逢",
                prompt: "写一个雨夜重逢的小说场景",
                mode: .collaboration,
                summary: "小说场景，已写到重逢后的第一段对话",
                context: ProjectContext(
                    intentSummary: "写一段雨夜重逢的小说场景，重点是情绪和停顿感。",
                    styleConstraints: ["含蓄", "有画面感", "少解释"],
                    currentGoal: "推进对话",
                    recentDecisions: ["避免直接交代缘由", "对话要短"],
                    workingMemory: ["这一段要先建立空间，再露出情绪"],
                    nextFocus: "补出角色回避后的反应"
                ),
                conversation: [
                    ConversationMessage(role: .user, text: "写一个雨夜重逢的小说场景。", timestamp: "用户 · 昨天"),
                    ConversationMessage(role: .assistant, text: "我会先把场景铺开，再让人物慢慢碰面。", timestamp: "AI · 昨天")
                ],
                documentText: "雨声落得很轻，像有人在窗外慢慢敲着什么。\n她站在门口的时候，外套上还沾着一点潮气。",
                suggestionChips: ["继续展开", "压低情绪", "补一段对白"],
                updatedAt: now.addingTimeInterval(-86400)
            ),
            WritingProject(
                automationKey: "project-003",
                title: "克制随笔",
                prompt: "把这段日记整理成更克制的随笔",
                mode: .discussion,
                summary: "先讨论语气边界，再决定起稿方向",
                context: ProjectContext(
                    intentSummary: "用户希望把日记整理成更克制的随笔，避免过度抒情。",
                    styleConstraints: ["克制", "自然", "避免抒情过满"],
                    currentGoal: "澄清表达边界",
                    recentDecisions: ["先讨论风格，再起稿"],
                    workingMemory: ["目前还没有正文，需要先完成意图澄清"],
                    nextFocus: "确认文章气质和保留信息"
                ),
                conversation: [
                    ConversationMessage(role: .assistant, text: "你希望这篇随笔更像记录，还是更像整理后的表达？", timestamp: "AI · 昨天"),
                    ConversationMessage(role: .user, text: "更像整理后的表达，但不要太满。", timestamp: "用户 · 昨天")
                ],
                documentText: "",
                suggestionChips: ["明确语气", "确认保留内容", "开始起稿"],
                updatedAt: now.addingTimeInterval(-90000)
            )
        ]
    }

    static let inspirationPrompts: [String] = [
        "写一篇关于成年人孤独感的公众号文章",
        "写一个雨夜重逢的小说场景",
        "把这段日记整理成更克制的随笔"
    ]
}
