import XCTest
@testable import VibeWriteApp

@MainActor
final class WritingAITests: XCTestCase {
    func testStubAIProducesStructuredDraftResponse() async throws {
        let request = WritingAIRequest(
            action: .startDraft,
            project: WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot,
            userMessage: "写一篇关于成年人孤独感的公众号文章",
            selectionText: nil
        )

        let response = try await StubWritingAIClient().generateResponse(for: request)

        XCTAssertFalse(response.documentText.isEmpty)
        XCTAssertFalse(response.assistantMessage.isEmpty)
        XCTAssertEqual(response.mode, .collaboration)
        XCTAssertFalse(response.suggestionChips.isEmpty)
    }

    func testResponseDecoderParsesFencedJSONString() throws {
        let raw = """
        ```json
        {
          "assistantMessage": "我已经起草完了。",
          "documentText": "正文",
          "summary": "摘要",
          "intentSummary": "意图",
          "styleConstraints": ["克制"],
          "currentGoal": "目标",
          "recentDecisions": ["决策"],
          "workingMemory": ["记忆"],
          "nextFocus": "下一步",
          "suggestionChips": ["继续"],
          "mode": "collaboration"
        }
        ```
        """

        let response = try WritingAIResponseDecoder.decode(from: raw)

        XCTAssertEqual(response.documentText, "正文")
        XCTAssertEqual(response.mode, .collaboration)
        XCTAssertEqual(response.suggestionChips, ["继续"])
    }

    func testApplyingAIResponseUpdatesProjectContext() {
        var project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!
        let response = WritingAIResponse(
            assistantMessage: "继续推进",
            documentText: "新的正文",
            summary: "新的摘要",
            intentSummary: "新的意图",
            styleConstraints: ["克制", "平静"],
            currentGoal: "新的目标",
            recentDecisions: ["新的决策"],
            workingMemory: ["新的记忆"],
            nextFocus: "新的下一步",
            suggestionChips: ["继续展开"],
            mode: .collaboration
        )

        project.apply(aiResponse: response)

        XCTAssertEqual(project.documentText, "新的正文")
        XCTAssertEqual(project.currentGoal, "新的目标")
        XCTAssertEqual(project.intentSummary, "新的意图")
        XCTAssertEqual(project.suggestionChips, ["继续展开"])
        XCTAssertEqual(project.mode, .collaboration)
        XCTAssertEqual(project.conversation.last?.text, "继续推进")
    }

    func testStartDraftPromptBuilderCollapsesDuplicatePromptInRequestContext() {
        let prompt = "写一篇关于成年人孤独感的公众号文章"
        let project = WritingProject.quickStart(
            prompt: prompt,
            mode: .discussion,
            automationKey: "project.prompt.dedup"
        )
        let request = WritingAIRequest(
            action: .startDraft,
            project: project.aiSnapshot,
            userMessage: prompt,
            selectionText: nil
        )

        let messages = WritingAIPromptBuilder().messages(
            for: request,
            provider: "minimax",
            model: "MiniMax-M2.7"
        )

        let userPrompt = messages.last?.content ?? ""
        let occurrences = userPrompt.components(separatedBy: prompt).count - 1

        XCTAssertEqual(occurrences, 1)
        XCTAssertFalse(userPrompt.contains(#""userMessage": ""#))
    }
}
