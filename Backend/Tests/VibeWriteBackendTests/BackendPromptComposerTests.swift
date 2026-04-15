import XCTest
@testable import VibeWriteBackend
import VibeWriteShared

final class BackendPromptComposerTests: XCTestCase {
    func testProseMessagesUseSeededRulesAndVisibleUserMessage() throws {
        let composer = BackendPromptComposer()
        let snapshot = AdminSystemPromptSeed.makeSnapshot(clock: BackendPromptComposerClock(date: Date(timeIntervalSince1970: 1_710_000_000)))
        let configuration = makeConfiguration(metadataRoute: .current)
        let prompt = "写一篇关于成年人孤独感的公众号文章"
        let request = makeRequest(
            action: .startDraft,
            project: makeSnapshot(
                title: "开头测试",
                prompt: prompt,
                documentText: "",
                mode: .discussion
            ),
            userMessage: prompt,
            selectionText: nil
        )

        let messages = try composer.proseMessages(
            for: request,
            systemPromptSnapshot: snapshot,
            configuration: configuration
        )

        XCTAssertEqual(messages.count, 2)

        let systemPrompt = messages[0].content
        let userPrompt = messages[1].content

        XCTAssertTrue(systemPrompt.contains("You are VibeWrite, a calm macOS writing collaborator."))
        XCTAssertFalse(systemPrompt.contains("Prose rules"))
        XCTAssertTrue(systemPrompt.contains("Output only prose text for the requested action."))
        XCTAssertTrue(systemPrompt.contains("Write only the opening prose for the first draft."))
        XCTAssertTrue(systemPrompt.contains("Provider: minimax"))
        XCTAssertTrue(systemPrompt.contains("Model: MiniMax-M2.5-highspeed"))
        XCTAssertTrue(userPrompt.contains("Action: startDraft"))
        XCTAssertTrue(userPrompt.contains("Project title: 开头测试"))
        XCTAssertTrue(userPrompt.contains("User message: \(prompt)"))
        XCTAssertFalse(userPrompt.contains("Selection:"))
        XCTAssertEqual(userPrompt.components(separatedBy: prompt).count - 1, 1)
    }

    func testContinueMessagesUseDocumentTailAndContextRules() throws {
        let composer = BackendPromptComposer()
        let snapshot = AdminSystemPromptSeed.makeSnapshot(clock: BackendPromptComposerClock(date: Date(timeIntervalSince1970: 1_710_000_000)))
        let configuration = makeConfiguration(metadataRoute: .current)
        let documentText = """
        前文第一段，用来填充上下文。

        前文第二段，继续铺陈背景。

        尾部第一段需要把节奏慢下来，并留下余味。

        尾部第二段要真正作为继续写的起点。
        """
        let request = makeRequest(
            action: .continueWriting,
            project: makeSnapshot(
                title: "续写测试",
                prompt: "写一篇关于成年人孤独感的公众号文章",
                documentText: documentText,
                mode: .collaboration,
                globalSynopsis: "给模型看的全局摘要要更短、更偏状态",
                context: ProjectContext(
                    intentSummary: "当前要把结尾收紧，并保持人物气口一致。",
                    styleConstraints: ["克制", "平静", "非鸡汤"],
                    currentGoal: "继续推进结尾",
                    recentDecisions: ["不重写前文", "保留余味"],
                    workingMemory: ["人物已经进入收束阶段", "后面只需要再往前推一点"],
                    nextFocus: "补一段收束"
                ),
                suggestionChips: ["继续写", "编辑这段", "补一段"]
            ),
            userMessage: "继续往下写",
            selectionText: nil
        )

        let messages = try composer.proseMessages(
            for: request,
            systemPromptSnapshot: snapshot,
            configuration: configuration
        )

        let systemPrompt = messages[0].content
        let userPrompt = messages[1].content

        XCTAssertFalse(systemPrompt.contains("Prose rules"))
        XCTAssertTrue(systemPrompt.contains("Advance the passage only a little; do not turn this into a full ending or a fully closed paragraph."))
        XCTAssertTrue(systemPrompt.contains("Provider: minimax"))
        XCTAssertTrue(systemPrompt.contains("Model: MiniMax-M2.5-highspeed"))
        XCTAssertTrue(userPrompt.contains("Global synopsis:"))
        XCTAssertTrue(userPrompt.contains("Document tail:"))
        XCTAssertTrue(userPrompt.contains("尾部第二段要真正作为继续写的起点。"))
        XCTAssertFalse(userPrompt.contains("Current document:"))
        XCTAssertFalse(userPrompt.contains("Selection:"))
    }

    func testMetadataMessagesUseRouteSpecificRules() throws {
        let composer = BackendPromptComposer()
        let snapshot = AdminSystemPromptSeed.makeSnapshot(clock: BackendPromptComposerClock(date: Date(timeIntervalSince1970: 1_710_000_000)))
        let request = makeRequest(
            action: .startDraft,
            project: makeSnapshot(
                title: "元数据测试",
                prompt: "写一篇关于成年人孤独感的公众号文章",
                documentText: "前文第一段。\n\n前文第二段。",
                mode: .collaboration,
                globalSynopsis: "给模型看的全局摘要要更短、更偏状态",
                context: ProjectContext(
                    intentSummary: "当前要把结尾收紧，并保持人物气口一致。",
                    styleConstraints: ["克制", "平静", "非鸡汤"],
                    currentGoal: "继续推进结尾",
                    recentDecisions: ["不重写前文", "保留余味"],
                    workingMemory: ["人物已经进入收束阶段", "后面只需要再往前推一点"],
                    nextFocus: "补一段收束"
                ),
                suggestionChips: ["继续写", "编辑这段", "补一段"]
            ),
            userMessage: "继续往下写",
            selectionText: nil,
            kind: .metadata
        )

        let currentRouteMessages = try composer.metadataMessages(
            for: request,
            systemPromptSnapshot: snapshot,
            configuration: makeConfiguration(metadataRoute: .current)
        )
        let textRouteMessages = try composer.metadataMessages(
            for: request,
            systemPromptSnapshot: snapshot,
            configuration: makeConfiguration(metadataRoute: .text01JsonSchema)
        )

        let currentSystemPrompt = currentRouteMessages[0].content
        let currentUserPrompt = currentRouteMessages[1].content
        let textSystemPrompt = textRouteMessages[0].content
        let textUserPrompt = textRouteMessages[1].content

        XCTAssertFalse(currentSystemPrompt.contains("Metadata rules"))
        XCTAssertTrue(currentSystemPrompt.contains("Use the provided emit_metadata tool to return the metadata for the completed prose."))
        XCTAssertTrue(currentSystemPrompt.contains("Do not output prose, markdown fences, or commentary."))
        XCTAssertTrue(currentSystemPrompt.contains("Provider: minimax"))
        XCTAssertTrue(currentSystemPrompt.contains("Model: MiniMax-M2.5-highspeed"))
        XCTAssertTrue(currentUserPrompt.contains("Action: startDraft metadata"))
        XCTAssertTrue(currentUserPrompt.contains("Completed prose:"))
        XCTAssertTrue(currentUserPrompt.contains("Current global synopsis:"))
        XCTAssertTrue(currentUserPrompt.contains("Return localSummary, globalSynopsis, nextFocus, and suggestionChips as a single emit_metadata tool call."))

        XCTAssertFalse(textSystemPrompt.contains("Metadata rules"))
        XCTAssertTrue(textSystemPrompt.contains("Return only the metadata for the completed prose."))
        XCTAssertTrue(textSystemPrompt.contains("Provider: minimax"))
        XCTAssertTrue(textSystemPrompt.contains("Model: MiniMax-Text-01"))
        XCTAssertTrue(textSystemPrompt.contains("Do not output prose, markdown fences, tool calls, or commentary."))
        XCTAssertTrue(textUserPrompt.contains("Return localSummary, globalSynopsis, nextFocus, and suggestionChips only."))
        XCTAssertFalse(textSystemPrompt.contains("emit_metadata"))
    }

    private func makeConfiguration(metadataRoute: BackendAIConfiguration.MetadataRoute) -> BackendAIConfiguration {
        BackendAIConfiguration(
            mode: .real,
            provider: "minimax",
            baseURL: URL(string: "https://api.minimaxi.com/anthropic")!,
            textBaseURL: URL(string: "https://api.minimaxi.com")!,
            model: "MiniMax-M2.5-highspeed",
            metadataRoute: metadataRoute
        )
    }

    private func makeSnapshot(
        title: String,
        prompt: String,
        documentText: String,
        mode: WritingProjectMode,
        globalSynopsis: String = "",
        context: ProjectContext? = nil,
        suggestionChips: [String] = []
    ) -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            automationKey: "backend.prompt.test",
            title: title,
            prompt: prompt,
            mode: mode,
            localSummary: "本地摘要",
            globalSynopsis: globalSynopsis,
            context: context ?? ProjectContext(
                intentSummary: "意图",
                styleConstraints: ["克制", "平静"],
                currentGoal: "目标",
                recentDecisions: ["决策"],
                workingMemory: ["记忆"],
                nextFocus: "下一步"
            ),
            conversation: [],
            documentText: documentText,
            suggestionChips: suggestionChips,
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }

    private func makeRequest(
        action: WritingAIAction,
        project: WritingProjectSnapshot,
        userMessage: String?,
        selectionText: String?,
        kind: WritingAIRequestKind = .prose
    ) -> WritingAIRequest {
        WritingAIRequest(
            action: action,
            project: project,
            userMessage: userMessage,
            selectionText: selectionText,
            kind: kind
        )
    }
}

private struct BackendPromptComposerClock: VibeWriteClock, @unchecked Sendable {
    let dateValue: Date

    init(date: Date) {
        self.dateValue = date
    }

    func now() -> Date {
        dateValue
    }
}
