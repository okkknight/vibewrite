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
                XCTAssertEqual(writeResponse.assistantMessage, "我已经根据你的方向起了一版第一稿。")
                XCTAssertEqual(
                    writeResponse.documentText.trimmingCharacters(in: .whitespacesAndNewlines),
                    """
                    在你给出的方向里，最重要的不是把情绪讲满，而是先把它停在一个合适的位置。
                    这篇文字先不急着给结论，而是从一个更具体的开头进入，让内容慢慢往前走。
                    """
                )
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
                XCTAssertEqual(writeResponse.assistantMessage, "我接着往下写了一段，让主线继续往前走。")
                XCTAssertEqual(
                    writeResponse.documentText,
                    """
                    开头正文
                    接下来可以顺着这个主线，再补一段更自然的推进。
                    """
                )
                XCTAssertEqual(writeResponse.localSummary, "")
                XCTAssertEqual(writeResponse.globalSynopsis, "")
                XCTAssertEqual(
                    writeResponse.intentSummary,
                    "围绕当前正文继续往下写一段，让主线自然往前推进。"
                )
                XCTAssertEqual(writeResponse.styleConstraints, ["克制", "平静"])
                XCTAssertEqual(writeResponse.currentGoal, "继续写")
                XCTAssertEqual(writeResponse.recentDecisions, ["继续沿当前主线", "保持节奏稳定"])
                XCTAssertEqual(writeResponse.workingMemory, ["继续沿当前正文推进", "优先保持节奏稳定"])
                XCTAssertEqual(writeResponse.nextFocus, "")
                XCTAssertEqual(writeResponse.suggestionChips, [])
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
