import XCTest
@testable import VibeWriteApp

@MainActor
final class VibeWriteAppFlowTests: XCTestCase {
    func testCreateNewProjectMovesToProjectScreenWithCollaborationDraft() {
        let flow = VibeWriteAppFlow()

        flow.createNewProject()

        XCTAssertEqual(flow.screen, .project)
        XCTAssertEqual(flow.activeProject.mode, .collaboration)
        XCTAssertFalse(flow.activeProject.documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(flow.activeProject.automationKey, "project.quickstart.default")
    }

    func testDiscussionQuickStartStartsDiscussionProjectWithEmptyDraft() {
        let flow = VibeWriteAppFlow()

        flow.startQuickDraft(prompt: "我想先聊清楚方向", mode: .discussion)

        XCTAssertEqual(flow.screen, .project)
        XCTAssertEqual(flow.activeProject.mode, .discussion)
        XCTAssertTrue(flow.activeProject.documentText.isEmpty)
        XCTAssertEqual(flow.activeProject.automationKey, "project.quickstart.discussion")
    }

    func testFlowPersistsAndRestoresLastOpenedProject() throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let initialFlow = VibeWriteAppFlow(storageURL: storageURL)
        let project = WritingProject.quickStart(
            prompt: "写一个雨夜重逢的小说场景",
            mode: .discussion,
            automationKey: "project.persisted.demo"
        )
        initialFlow.openProject(project)

        var updatedProject = initialFlow.activeProject
        updatedProject.currentGoal = "确认角色关系"
        updatedProject.recentDecisions = ["先说明场景", "再处理重逢"]
        initialFlow.activeProject = updatedProject
        initialFlow.returnHome()

        let restoredFlow = VibeWriteAppFlow(storageURL: storageURL)

        XCTAssertEqual(restoredFlow.screen, .project)
        XCTAssertEqual(restoredFlow.activeProject.id, updatedProject.id)
        XCTAssertEqual(restoredFlow.activeProject.currentGoal, "确认角色关系")
        XCTAssertTrue(restoredFlow.recentProjects.contains(where: { $0.id == updatedProject.id }))
    }

    func testMockEngineRevisesSelectedAndWholeDocumentText() {
        let draft = MockWritingEngine.firstDraft(for: "写一篇关于成年人孤独感的公众号文章")
        let revisedWhole = MockWritingEngine.revisedText(
            for: draft,
            selectedSegment: nil,
            action: .expand,
            variant: .standard
        )
        let revisedSelection = MockWritingEngine.revisedText(
            for: draft,
            selectedSegment: draft.components(separatedBy: "\n\n").first,
            action: .selectionModify,
            variant: .standard
        )

        XCTAssertNotEqual(draft, revisedWhole)
        XCTAssertNotEqual(draft, revisedSelection)
        XCTAssertTrue(revisedSelection.contains("留一点空白") || revisedSelection.contains("不用说得太满"))
    }

    func testFailedAIRequestDoesNotMutateActiveProjectState() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: ThrowingWritingAIClient())
        let project = WritingProject.quickStart(
            prompt: "把这段日记整理成更克制的随笔",
            mode: .collaboration,
            automationKey: "project.failure.demo"
        )
        flow.openProject(project)

        let before = flow.activeProject

        do {
            try await flow.performWritingAction(
                .submitMessage,
                userMessage: "请把这段改得更克制一点",
                selectionText: nil
            )
            XCTFail("Expected the AI request to fail")
        } catch {
            XCTAssertNotNil(flow.aiErrorMessage)
        }

        XCTAssertEqual(flow.activeProject.documentText, before.documentText)
        XCTAssertEqual(flow.activeProject.conversation.count, before.conversation.count)
        XCTAssertEqual(flow.activeProject.updatedAt, before.updatedAt)
    }

    func testStartDraftDoesNotDuplicateMatchingPrompt() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let recorder = RequestRecorder()
        let flow = VibeWriteAppFlow(
            storageURL: storageURL,
            aiClient: RecordingWritingAIClient(recorder: recorder)
        )
        let prompt = "写一篇关于成年人孤独感的公众号文章"
        let project = WritingProject.quickStart(
            prompt: prompt,
            mode: .discussion,
            automationKey: "project.startdraft.demo"
        )
        flow.openProject(project)

        try await flow.performWritingAction(
            .startDraft,
            userMessage: prompt,
            selectionText: nil
        )

        let request = await recorder.lastRequest()
        XCTAssertNil(request?.userMessage)

        let matchingUserMessages = flow.activeProject.conversation.filter {
            $0.role == .user && $0.text == prompt
        }
        XCTAssertEqual(matchingUserMessages.count, 1)
    }

    private func makeTempStorageURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("local-project-store.json")
    }
}

private actor RequestRecorder {
    private var requests: [WritingAIRequest] = []

    func record(_ request: WritingAIRequest) {
        requests.append(request)
    }

    func lastRequest() -> WritingAIRequest? {
        requests.last
    }
}

private struct RecordingWritingAIClient: WritingAIClient {
    let recorder: RequestRecorder

    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        await recorder.record(request)
        return WritingProjectResponseBuilder.response(for: request)
    }
}

private struct ThrowingWritingAIClient: WritingAIClient {
    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        throw WritingAIClientError.requestFailed("AI request failed for test")
    }
}
