import Foundation
import XCTVapor
@testable import VibeWriteBackend
import VibeWriteShared

final class WriteStartTests: XCTestCase {
    func testStartDraftAcceptsMatchingBootstrapToken() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let bootstrapRequest = BootstrapRequest(
            installationId: "installation-001",
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

        let writeRequest = WriteStartEnvelope(
            installationId: bootstrapRequest.installationId,
            deviceToken: issuedToken,
            requestId: "request-001",
            action: .startDraft,
            kind: .prose,
            project: sampleProjectSnapshot(),
            userMessage: "先写一个开头",
            selectionText: nil,
            selectionRange: nil
        )

        try app.test(.POST, "v3/writes/start", beforeRequest: { request in
            try request.content.encode(writeRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(WritingAIResponse.self, response) { writeResponse in
                XCTAssertEqual(writeResponse.assistantMessage, "[stub] /v3/writes/start accepted")
                XCTAssertEqual(writeResponse.documentText, writeRequest.project.documentText)
                XCTAssertEqual(writeResponse.localSummary, writeRequest.project.localSummary)
                XCTAssertEqual(writeResponse.globalSynopsis, writeRequest.project.globalSynopsis)
                XCTAssertEqual(writeResponse.intentSummary, writeRequest.project.context.intentSummary)
                XCTAssertEqual(writeResponse.styleConstraints, writeRequest.project.context.styleConstraints)
                XCTAssertEqual(writeResponse.currentGoal, writeRequest.project.context.currentGoal)
                XCTAssertEqual(writeResponse.recentDecisions, writeRequest.project.context.recentDecisions)
                XCTAssertEqual(writeResponse.workingMemory, writeRequest.project.context.workingMemory)
                XCTAssertEqual(writeResponse.nextFocus, writeRequest.project.context.nextFocus)
                XCTAssertEqual(writeResponse.suggestionChips, writeRequest.project.suggestionChips)
                XCTAssertEqual(writeResponse.mode, writeRequest.project.mode)
            }
        })
    }

    func testStartDraftRejectsMismatchedToken() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let writeRequest = WriteStartEnvelope(
            installationId: "installation-002",
            deviceToken: "not-a-real-token",
            requestId: "request-002",
            action: .startDraft,
            kind: .prose,
            project: sampleProjectSnapshot(),
            userMessage: nil,
            selectionText: nil,
            selectionRange: nil
        )

        try app.test(.POST, "v3/writes/start", beforeRequest: { request in
            try request.content.encode(writeRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .unauthorized)
        })
    }

    private func sampleProjectSnapshot() -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000028") ?? UUID(),
            automationKey: "task28",
            title: "写作任务",
            prompt: "先写开头",
            mode: .collaboration,
            localSummary: "本地摘要",
            globalSynopsis: "全局梗概",
            context: ProjectContext(
                intentSummary: "先起稿",
                styleConstraints: ["克制", "平静"],
                currentGoal: "生成第一段",
                recentDecisions: ["先写开头"],
                workingMemory: ["还在起稿"],
                nextFocus: "继续展开"
            ),
            conversation: [
                ConversationMessage(role: .user, text: "先写开头", timestamp: "2026-04-12T00:00:00Z")
            ],
            documentText: "开头正文",
            suggestionChips: ["继续", "收紧"],
            updatedAt: Date(timeIntervalSince1970: 1_719_000_000)
        )
    }
}
