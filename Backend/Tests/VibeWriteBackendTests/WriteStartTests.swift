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

        let writeRequest = makeGatewayStartRequest(
            installationId: bootstrapRequest.installationId,
            deviceToken: issuedToken,
            requestId: "request-001",
            project: sampleProjectSnapshot(),
            userMessage: "先写一个开头"
        )

        try app.test(.POST, "v3/writes/start", beforeRequest: { request in
            try request.content.encode(writeRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(WritingGatewayResponse.self, response) { writeResponse in
                XCTAssertEqual(writeResponse.assistantMessage, "我已经根据你的方向起了一版第一稿。")
                XCTAssertEqual(
                    writeResponse.documentText?.trimmingCharacters(in: .whitespacesAndNewlines),
                    """
                    在你给出的方向里，最重要的不是把情绪讲满，而是先把它停在一个合适的位置。
                    这篇文字先不急着给结论，而是从一个更具体的开头进入，让内容慢慢往前走。
                    """
                )
                XCTAssertNil(writeResponse.appendedText)
                XCTAssertNil(writeResponse.replacementText)
                XCTAssertEqual(writeResponse.localSummary, "")
                XCTAssertEqual(writeResponse.globalSynopsis, "")
                XCTAssertEqual(
                    writeResponse.intentSummary,
                    "围绕“先写一个开头”持续协作，正文会直接写入文档而不是停留在聊天里。"
                )
                XCTAssertEqual(writeResponse.styleConstraints, ["克制", "平静", "非鸡汤", "避免说教"])
                XCTAssertEqual(writeResponse.currentGoal, "收紧开头")
                XCTAssertEqual(writeResponse.recentDecisions, ["先生成第一稿", "开头保持克制"])
                XCTAssertEqual(writeResponse.workingMemory, ["正文已经进入协作阶段", "后续修改优先围绕主线推进"])
                XCTAssertEqual(writeResponse.nextFocus, "")
                XCTAssertEqual(writeResponse.suggestionChips, [])
                XCTAssertEqual(writeResponse.mode, .collaboration)
            }
        })
    }

    func testStartDraftRejectsMismatchedToken() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let writeRequest = makeGatewayStartRequest(
            installationId: "installation-002",
            deviceToken: "not-a-real-token",
            requestId: "request-002",
            project: sampleProjectSnapshot()
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
