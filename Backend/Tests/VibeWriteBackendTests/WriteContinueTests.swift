import Foundation
import XCTVapor
@testable import VibeWriteBackend
import VibeWriteShared

final class WriteContinueTests: XCTestCase {
    func testContinueDraftAcceptsMatchingBootstrapTokenAndKeepsStartRouteWorking() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let bootstrapRequest = BootstrapRequest(
            installationId: "installation-continue-001",
            appVersion: "3.0.0",
            platform: "macOS",
            deviceName: "QA Mac"
        )

        var issuedToken = ""
        try app.test(.POST, "v3/client/bootstrap", beforeRequest: { request in
            try request.content.encode(bootstrapRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(BootstrapResponse.self, response) { bootstrap in
                issuedToken = bootstrap.deviceToken
            }
        })

        let startRequest = WriteRequestEnvelope(
            installationId: bootstrapRequest.installationId,
            deviceToken: issuedToken,
            requestId: "request-start-001",
            action: .startDraft,
            kind: .prose,
            project: sampleProjectSnapshot(automationKey: "task29-start"),
            userMessage: "先写一个开头",
            selectionText: nil,
            selectionRange: nil
        )

        try app.test(.POST, "v3/writes/start", beforeRequest: { request in
            try request.content.encode(startRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(WritingAIResponse.self, response) { writeResponse in
                XCTAssertEqual(writeResponse.assistantMessage, "[stub] /v3/writes/start accepted")
                XCTAssertEqual(writeResponse.documentText, startRequest.project.documentText)
            }
        })

        let continueRequest = WriteRequestEnvelope(
            installationId: bootstrapRequest.installationId,
            deviceToken: issuedToken,
            requestId: "request-continue-001",
            action: .continueWriting,
            kind: .prose,
            project: sampleProjectSnapshot(automationKey: "task29-continue"),
            userMessage: "继续写下去",
            selectionText: "开头正文",
            selectionRange: WritingTextSelectionRange(location: 0, length: 4)
        )

        try app.test(.POST, "v3/writes/continue", beforeRequest: { request in
            try request.content.encode(continueRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(WritingAIResponse.self, response) { writeResponse in
                XCTAssertEqual(writeResponse.assistantMessage, "[stub] /v3/writes/continue accepted")
                XCTAssertEqual(writeResponse.documentText, continueRequest.project.documentText)
                XCTAssertEqual(writeResponse.localSummary, continueRequest.project.localSummary)
                XCTAssertEqual(writeResponse.globalSynopsis, continueRequest.project.globalSynopsis)
                XCTAssertEqual(writeResponse.intentSummary, continueRequest.project.context.intentSummary)
                XCTAssertEqual(writeResponse.styleConstraints, continueRequest.project.context.styleConstraints)
                XCTAssertEqual(writeResponse.currentGoal, continueRequest.project.context.currentGoal)
                XCTAssertEqual(writeResponse.recentDecisions, continueRequest.project.context.recentDecisions)
                XCTAssertEqual(writeResponse.workingMemory, continueRequest.project.context.workingMemory)
                XCTAssertEqual(writeResponse.nextFocus, continueRequest.project.context.nextFocus)
                XCTAssertEqual(writeResponse.suggestionChips, continueRequest.project.suggestionChips)
                XCTAssertEqual(writeResponse.mode, continueRequest.project.mode)
            }
        })
    }

    func testContinueDraftRejectsMismatchedToken() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let continueRequest = WriteRequestEnvelope(
            installationId: "installation-continue-002",
            deviceToken: "not-a-real-token",
            requestId: "request-continue-002",
            action: .continueWriting,
            kind: .prose,
            project: sampleProjectSnapshot(automationKey: "task29-invalid"),
            userMessage: nil,
            selectionText: nil,
            selectionRange: nil
        )

        try app.test(.POST, "v3/writes/continue", beforeRequest: { request in
            try request.content.encode(continueRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .unauthorized)
        })
    }

    private func sampleProjectSnapshot(automationKey: String) -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000029") ?? UUID(),
            automationKey: automationKey,
            title: "写作任务",
            prompt: "继续写下去",
            mode: .collaboration,
            localSummary: "本地摘要",
            globalSynopsis: "全局梗概",
            context: ProjectContext(
                intentSummary: "先继续正文",
                styleConstraints: ["克制", "平静"],
                currentGoal: "续写下一段",
                recentDecisions: ["先写开头"],
                workingMemory: ["正文仍在推进"],
                nextFocus: "继续展开"
            ),
            conversation: [
                ConversationMessage(role: .user, text: "继续写下去", timestamp: "2026-04-12T00:00:00Z")
            ],
            documentText: "开头正文",
            suggestionChips: ["继续", "收紧"],
            updatedAt: Date(timeIntervalSince1970: 1_719_000_000)
        )
    }
}
