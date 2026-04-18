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
        XCTAssertEqual(
            messages[0].content,
            joined(
                "You are VibeWrite, a calm macOS writing collaborator.",
                "Output only prose text for the requested action.",
                "Do not output metadata, JSON, markdown fences, or commentary.",
                "Keep the output short enough to stream quickly.",
                "- Write only the opening prose for the first draft.",
                "- Keep the opening brief and concrete so it can stand on its own.",
                "- Keep the writing voice calm, precise, and native to a macOS writing app.",
                "- Preserve the current article's structure unless the action explicitly changes it.",
                "- When the action is \"startDraft\", focus on the first usable opening rather than a full outline.",
                "Provider: minimax",
                "Model: MiniMax-M2.5-highspeed"
            )
        )
        XCTAssertEqual(
            messages[1].content,
            joined(
                "Action: startDraft",
                "Project title: 开头测试",
                "Current document:",
                "(empty)",
                "User message: \(prompt)",
                "Write the opening prose for the first draft.",
                "Keep the opening brief and concrete so it can stand on its own.",
                "Do not output metadata or commentary."
            )
        )
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

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(
            messages[0].content,
            joined(
                "You are VibeWrite, a calm macOS writing collaborator.",
                "Output only prose text for the requested action.",
                "Do not output metadata, JSON, markdown fences, or commentary.",
                "Keep the output short enough to stream quickly.",
                "- Continue the current正文 with the next short paragraph or scene.",
                "- Advance the passage only a little; do not turn this into a full ending or a fully closed paragraph.",
                "- Leave a small amount of forward momentum for the next step.",
                "- Keep the writing voice calm, precise, and native to a macOS writing app.",
                "- Preserve the current article's structure unless the action explicitly changes it.",
                "- When the action is \"continueWriting\", continue the existing正文 instead of restarting the article.",
                "Provider: minimax",
                "Model: MiniMax-M2.5-highspeed"
            )
        )
        XCTAssertEqual(
            messages[1].content,
            joined(
                "Action: continueWriting",
                "Project title: 续写测试",
                "Global synopsis:",
                "给模型看的全局摘要要更短、更偏状态",
                "Document tail:",
                documentText,
                "User message: 继续往下写",
                "Use the global synopsis as stable context and the document tail as the continuation anchor.",
                "Do not restart from the beginning of the article.",
                "Advance the passage only a little; do not turn this into a full ending or a fully closed paragraph.",
                "Leave a small amount of forward momentum for the next step.",
                "Keep the continuation brief so the next move still feels natural."
            )
        )
    }

    func testEditMessagesUseLegacyMetadataBlockPlacement() throws {
        let composer = BackendPromptComposer()
        let snapshot = AdminSystemPromptSeed.makeSnapshot(clock: BackendPromptComposerClock(date: Date(timeIntervalSince1970: 1_710_000_000)))
        let configuration = makeConfiguration(metadataRoute: .current)
        let documentText = """
        前文第一段，用来填充上下文。

        前文第二段，继续铺陈背景。
        """
        let selectionText = "原文片段"
        let request = makeRequest(
            action: .edit,
            project: makeSnapshot(
                title: "润色测试",
                prompt: "把这一段写得更克制",
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
            userMessage: "把这一段写得更克制",
            selectionText: selectionText
        )

        let messages = try composer.proseMessages(
            for: request,
            systemPromptSnapshot: snapshot,
            configuration: configuration
        )

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(
            messages[0].content,
            joined(
                "You are VibeWrite, a calm macOS writing collaborator.",
                "Output the writing text first, then append exactly one metadata block for the app.",
                "Do not output commentary outside the writing text and metadata block.",
                "A response is incomplete until the metadata block is present.",
                "- When the action is \"edit\", return only the replacement text for the selected segment.",
                "- Keep the output short enough to stream quickly.",
                "- Do not stop after writing text alone.",
                "- After the prose is finished, output a blank line, then `[[VIBEWRITE_METADATA]]`, then a single JSON object.",
                "- The metadata JSON must contain: localSummary, globalSynopsis, nextFocus, suggestionChips.",
                "- Keep the metadata specific to the current正文 and actionable for the next step.",
                "- Match the metadata language to the language of the current正文 and user request.",
                "- For Chinese writing tasks, localSummary, globalSynopsis, nextFocus, and suggestionChips must be concise Chinese.",
                "- The metadata block is not part of the正文 and must not be mixed into the prose.",
                "- Every response must end with exactly one metadata block.",
                "- When the action is \"edit\", rewrite only the selected passage or local region whenever practical.",
                "- Keep the prose concise enough for streaming.",
                "- The metadata JSON should stay concise and concrete, not templated.",
                "",
                "Rules:",
                "- Keep the writing voice calm, precise, and native to a macOS writing app.",
                "- Preserve the current article's structure unless the action explicitly changes it.",
                "- When the action is \"edit\", rewrite only the selected passage or local region whenever practical.",
                "",
                "Provider: minimax",
                "Model: MiniMax-M2.5-highspeed"
            )
        )
        XCTAssertEqual(
            messages[1].content,
            joined(
                "Action: edit",
                "Project title: 润色测试",
                "Current document:",
                documentText,
                "User message: 把这一段写得更克制",
                "Selection: \(selectionText)",
                "Return only the replacement text for the selected segment.",
                "Rewrite only the selected passage or local region whenever practical.",
                "After the prose, append a blank line, then [[VIBEWRITE_METADATA]], then a single JSON object with localSummary, globalSynopsis, nextFocus, and suggestionChips.",
                "Do not mix the metadata into the prose.",
                "The metadata must be concise, concrete, and in the same language as the current正文."
            )
        )
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

        XCTAssertEqual(currentRouteMessages.count, 2)
        XCTAssertEqual(textRouteMessages.count, 2)
        XCTAssertEqual(
            currentSystemPrompt,
            joined(
                "You are VibeWrite metadata-only response builder.",
                "The only valid response is a single `emit_metadata` tool call.",
                "Do not output plain text, prose, markdown fences, JSON, reasoning, or commentary.",
                "Do not answer in any other format.",
                "If you are about to produce ordinary assistant text, stop and emit the tool call instead.",
                "",
                "- Return suggestionChips as the primary output and keep them concrete.",
                "- Describe the current opening state as the local summary.",
                "- Keep the global synopsis short and stable; it should preserve broader story state without repeating the local summary.",
                "- Suggest the next concrete step after the opening exists.",
                "- Return exactly 3 concise suggestion chips.",
                "",
                "- Keep the metadata specific to the current正文 and actionable for the next step.",
                "- Treat suggestionChips as the most important field and do not let globalSynopsis crowd it out.",
                "- Keep localSummary brief, keep globalSynopsis stable and short, and let suggestionChips stay concrete.",
                "- Match the metadata language to the language of the current正文 and user request.",
                "- For Chinese writing tasks, localSummary, globalSynopsis, nextFocus, and suggestionChips must be concise Chinese.",
                "- suggestionChips must be concise, concrete, and non-generic."
            )
        )
        XCTAssertEqual(
            currentUserPrompt,
            joined(
                "Action: startDraft metadata",
                "Project title: 元数据测试",
                "Completed prose:",
                "前文第一段。\n\n前文第二段。",
                "Current global synopsis:",
                "给模型看的全局摘要要更短、更偏状态",
                "User message: 继续往下写",
                "Use the `emit_metadata` tool to return localSummary, globalSynopsis, nextFocus, and suggestionChips.",
                "Make suggestionChips the most concrete part of the response; keep globalSynopsis short and stable.",
                "Return exactly one `emit_metadata` tool call and nothing else.",
                "Do not include prose, markdown fences, or commentary.",
                "Do not produce ordinary assistant text.",
                "For Chinese writing tasks, keep localSummary, globalSynopsis, nextFocus, and suggestionChips in concise Chinese.",
                "Return exactly 3 concise suggestion chips."
            )
        )
        XCTAssertEqual(
            textSystemPrompt,
            joined(
                "You are VibeWrite metadata-only response builder.",
                "Return only the metadata for the completed prose.",
                "Do not output prose, markdown fences, tool calls, or commentary.",
                "Do not answer in plain text.",
                "",
                "- Return suggestionChips as the primary output and keep them concrete.",
                "- Describe the current opening state as the local summary.",
                "- Keep the global synopsis short and stable; it should preserve broader story state without repeating the local summary.",
                "- Suggest the next concrete step after the opening exists.",
                "- Return exactly 3 concise suggestion chips.",
                "",
                "- Keep the metadata specific to the current正文 and actionable for the next step.",
                "- Treat suggestionChips as the most important field and do not let globalSynopsis crowd it out.",
                "- Keep localSummary brief, keep globalSynopsis stable and short, and let suggestionChips stay concrete.",
                "- Match the metadata language to the language of the current正文 and user request.",
                "- For Chinese writing tasks, localSummary, globalSynopsis, nextFocus, and suggestionChips must be concise Chinese.",
                "- suggestionChips must be concise, concrete, and non-generic.",
                "- The response format is schema-enforced, so do not wrap the metadata in extra text.",
                "",
                "Provider: minimax",
                "Model: MiniMax-Text-01"
            )
        )
        XCTAssertEqual(
            textUserPrompt,
            joined(
                "Action: startDraft metadata",
                "Project title: 元数据测试",
                "Completed prose:",
                "前文第一段。\n\n前文第二段。",
                "Current global synopsis:",
                "给模型看的全局摘要要更短、更偏状态",
                "User message: 继续往下写",
                "Return localSummary, globalSynopsis, nextFocus, and suggestionChips only.",
                "Make suggestionChips the most concrete part of the response; keep globalSynopsis short and stable.",
                "Do not include prose, markdown fences, or commentary.",
                "For Chinese writing tasks, keep localSummary, globalSynopsis, nextFocus, and suggestionChips in concise Chinese.",
                "Return exactly 3 concise suggestion chips."
            )
        )
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

    private func joined(_ lines: String...) -> String {
        lines.joined(separator: "\n")
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
