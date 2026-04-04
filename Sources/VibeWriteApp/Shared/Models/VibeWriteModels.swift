import Foundation

struct ProjectContext: Codable, Hashable {
    var intentSummary: String
    var styleConstraints: [String]
    var currentGoal: String
    var recentDecisions: [String]
    var workingMemory: [String]
    var nextFocus: String

    static func discussion(prompt: String) -> ProjectContext {
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

    static func collaboration(prompt: String) -> ProjectContext {
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

struct WritingTextSelectionRange: Codable, Hashable {
    var location: Int
    var length: Int

    init(location: Int, length: Int) {
        self.location = max(location, 0)
        self.length = max(length, 0)
    }

    init(_ range: NSRange) {
        self.init(location: range.location, length: range.length)
    }

    var isEmpty: Bool {
        length <= 0
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    func range(in text: String) -> Range<String.Index>? {
        Range(nsRange, in: text)
    }

    func substring(in text: String) -> String? {
        guard let range = range(in: text) else {
            return nil
        }

        return String(text[range])
    }
}

struct WritingProject: Identifiable, Hashable, Codable {
    let id: UUID
    var automationKey: String { didSet { touch() } }
    var title: String { didSet { touch() } }
    var prompt: String { didSet { touch() } }
    var mode: WritingProjectMode { didSet { touch() } }
    var summary: String { didSet { touch() } }
    var continuationSummary: String { didSet { touch() } }
    var context: ProjectContext { didSet { touch() } }
    var conversation: [ConversationMessage] { didSet { touch() } }
    var documentText: String { didSet { touch() } }
    var suggestionChips: [String] { didSet { touch() } }
    var revisionHistory: [WritingProjectRevision] { didSet { touch() } }
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        automationKey: String? = nil,
        title: String,
        prompt: String,
        mode: WritingProjectMode,
        summary: String,
        continuationSummary: String = "",
        context: ProjectContext,
        conversation: [ConversationMessage],
        documentText: String,
        suggestionChips: [String],
        revisionHistory: [WritingProjectRevision] = [],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.automationKey = automationKey ?? id.uuidString.lowercased()
        self.title = title
        self.prompt = prompt
        self.mode = mode
        self.summary = summary
        self.continuationSummary = Self.normalizedContinuationSummary(continuationSummary, fallback: summary)
        self.context = context
        self.conversation = conversation
        self.documentText = documentText
        self.suggestionChips = suggestionChips
        self.revisionHistory = revisionHistory
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case automationKey
        case title
        case prompt
        case mode
        case summary
        case continuationSummary
        case context
        case conversation
        case documentText
        case suggestionChips
        case revisionHistory
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        automationKey = try container.decode(String.self, forKey: .automationKey)
        title = try container.decode(String.self, forKey: .title)
        prompt = try container.decode(String.self, forKey: .prompt)
        mode = try container.decode(WritingProjectMode.self, forKey: .mode)
        summary = try container.decode(String.self, forKey: .summary)
        continuationSummary = try container.decode(String.self, forKey: .continuationSummary)
        context = try container.decode(ProjectContext.self, forKey: .context)
        conversation = try container.decode([ConversationMessage].self, forKey: .conversation)
        documentText = try container.decode(String.self, forKey: .documentText)
        suggestionChips = try container.decode([String].self, forKey: .suggestionChips)
        revisionHistory = try container.decodeIfPresent([WritingProjectRevision].self, forKey: .revisionHistory) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(automationKey, forKey: .automationKey)
        try container.encode(title, forKey: .title)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(mode, forKey: .mode)
        try container.encode(summary, forKey: .summary)
        try container.encode(continuationSummary, forKey: .continuationSummary)
        try container.encode(context, forKey: .context)
        try container.encode(conversation, forKey: .conversation)
        try container.encode(documentText, forKey: .documentText)
        try container.encode(suggestionChips, forKey: .suggestionChips)
        try container.encode(revisionHistory, forKey: .revisionHistory)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    static func quickStart(prompt: String, mode: WritingProjectMode, automationKey: String? = nil) -> WritingProject {
        entryShell(prompt: prompt, mode: mode, automationKey: automationKey)
    }

    static func entryShell(prompt: String = "", mode: WritingProjectMode, automationKey: String? = nil) -> WritingProject {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = titleFromPrompt(cleanedPrompt, fallback: mode.defaultTitle)
        let now = Date()

        switch mode {
        case .discussion:
            let conversation: [ConversationMessage] = cleanedPrompt.isEmpty
                ? [
                    ConversationMessage(role: .assistant, text: "你想写什么类型的内容？", timestamp: "AI · 刚刚")
                ]
                : [
                    ConversationMessage(role: .assistant, text: "你想写什么类型的内容？", timestamp: "AI · 刚刚"),
                    ConversationMessage(role: .user, text: cleanedPrompt, timestamp: "用户 · 刚刚")
                ]

            return WritingProject(
                automationKey: automationKey,
                title: title,
                prompt: cleanedPrompt,
                mode: mode,
                summary: cleanedPrompt.isEmpty ? "先聊清楚方向，再生成第一稿" : "先把方向聊清楚，再生成第一稿",
                continuationSummary: cleanedPrompt.isEmpty ? "先聊清楚方向，再生成第一稿" : "先把方向聊清楚，再生成第一稿",
                context: .discussion(prompt: cleanedPrompt),
                conversation: conversation,
                documentText: "",
                suggestionChips: cleanedPrompt.isEmpty ? ["开始起稿", "确认方向", "确认语气"] : ["开始起稿", "确认方向", "确认语气"],
                revisionHistory: [],
                updatedAt: now
            )

        case .collaboration:
            let conversation: [ConversationMessage] = cleanedPrompt.isEmpty
                ? []
                : [
                    ConversationMessage(role: .user, text: cleanedPrompt, timestamp: "用户 · 刚刚")
                ]

            return WritingProject(
                automationKey: automationKey,
                title: title,
                prompt: cleanedPrompt,
                mode: mode,
                summary: cleanedPrompt.isEmpty ? "等待起稿输入" : "正在生成第一稿",
                continuationSummary: cleanedPrompt.isEmpty ? "等待起稿输入" : "正在生成第一稿",
                context: .collaboration(prompt: cleanedPrompt),
                conversation: conversation,
                documentText: "",
                suggestionChips: cleanedPrompt.isEmpty ? ["开始起稿"] : ["继续写", "编辑这段", "补一段"],
                revisionHistory: [],
                updatedAt: now
            )
        }
    }

    mutating func apply(snapshot: WritingProjectSnapshot) {
        automationKey = snapshot.automationKey
        title = snapshot.title
        prompt = snapshot.prompt
        mode = snapshot.mode
        summary = snapshot.summary
        continuationSummary = snapshot.continuationSummary
        context = snapshot.context
        conversation = snapshot.conversation
        documentText = snapshot.documentText
        suggestionChips = snapshot.suggestionChips
        updatedAt = snapshot.updatedAt
    }

    mutating func recordRevision(
        patch: WritingEditPatch,
        before: WritingProjectSnapshot,
        after: WritingProjectSnapshot
    ) {
        revisionHistory.append(
            WritingProjectRevision(
                patch: patch,
                before: before,
                after: after
            )
        )
        touch()
    }

    mutating func undoLastRevision() -> WritingProjectRevision? {
        guard let revision = revisionHistory.popLast() else {
            return nil
        }

        apply(snapshot: revision.before)
        touch()
        return revision
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

    private static func normalizedContinuationSummary(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
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
        case .discussion: return "起稿中"
        case .collaboration: return "正文协作中"
        }
    }

    var stageDescription: String {
        switch self {
        case .discussion: return "正在生成第一稿"
        case .collaboration: return "围绕灵感持续写作"
        }
    }
}

enum ProjectShellLayoutMode: Hashable, Codable {
    case wide
    case compact

    static let compactThreshold: Double = 1080

    init(windowWidth: Double, forceCompact: Bool = false) {
        if forceCompact {
            self = .compact
        } else {
            self = windowWidth < Self.compactThreshold ? .compact : .wide
        }
    }

    var isCompact: Bool {
        self == .compact
    }

    var isWide: Bool {
        self == .wide
    }
}

enum WorkspaceFixtures {
    // Test/demo fixture only. The app should not bootstrap these projects at startup.
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
                suggestionChips: ["继续写", "编辑这段", "补一段"],
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
                suggestionChips: ["继续写", "编辑这段", "补一段"],
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
                suggestionChips: ["开始起稿", "确认方向", "确认语气"],
                updatedAt: now.addingTimeInterval(-90000)
            )
        ]
    }

    // Test/demo fixture only. Keep the content out of the normal startup path.
    static let inspirationPrompts: [String] = [
        "写一篇关于成年人孤独感的公众号文章",
        "写一个雨夜重逢的小说场景",
        "把这段日记整理成更克制的随笔"
    ]
}
