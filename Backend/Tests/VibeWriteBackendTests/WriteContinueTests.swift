import Foundation
import XCTVapor
@testable import VibeWriteBackend
import VibeWriteShared

final class WriteContinueTests: XCTestCase {
    func testContinueDraftAcceptsKnownLengthStreamingBodyAboveFrameworkDefaultLimit() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let bootstrapRequest = BootstrapRequest(
            installationId: "installation-continue-large-001",
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

        let largeDocument = String(repeating: "a", count: 49_000)
        let project = sampleProjectSnapshot(
            automationKey: "task48-large-stream",
            documentText: largeDocument
        )
        let continueRequest = makeGatewayContinueRequest(
            installationId: bootstrapRequest.installationId,
            deviceToken: issuedToken,
            requestId: "request-continue-large-001",
            project: project,
            userMessage: "继续写下去",
            tailText: String(largeDocument.suffix(1_500))
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let requestBodyData = try encoder.encode(continueRequest)
        XCTAssertLessThan(requestBodyData.count, 16 * 1024)
        XCTAssertLessThan(requestBodyData.count, largeDocument.utf8.count / 4)

        try app.server.start(address: .hostname("127.0.0.1", port: 0))
        defer { app.server.shutdown() }

        guard let port = app.http.server.shared.localAddress?.port else {
            XCTFail("Expected test server to bind an ephemeral port.")
            return
        }

        let client = HTTPClient(eventLoopGroupProvider: .createNew)
        defer { XCTAssertNoThrow(try client.syncShutdown()) }

        var headers = HTTPHeaders()
        headers.contentType = .json
        headers.replaceOrAdd(name: .accept, value: "application/json")
        let url = "http://127.0.0.1:\(port)/v3/writes/continue"
        var request = try HTTPClient.Request(
            url: url,
            method: .POST,
            headers: headers
        )

        let splitIndex = requestBodyData.count / 2
        let firstChunk = Array(requestBodyData[..<splitIndex])
        let secondChunk = Array(requestBodyData[splitIndex...])
        request.body = .stream(contentLength: Int64(requestBodyData.count)) { writer in
            writer.write(.byteBuffer(ByteBuffer(bytes: firstChunk))).flatMap {
                writer.write(.byteBuffer(ByteBuffer(bytes: secondChunk)))
            }
        }

        let response = try client.execute(request: request).wait()
        XCTAssertEqual(response.status, .ok)
        XCTAssertNotNil(response.headers.first(name: .contentType))

        guard var responseBody = response.body else {
            XCTFail("Expected JSON response body for large streamed continue request.")
            return
        }

        let bodyString = responseBody.readString(length: responseBody.readableBytes)
        XCTAssertNotNil(bodyString)
        XCTAssertTrue(bodyString?.contains("\"assistantMessage\"") == true)
    }

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

        let startProject = sampleProjectSnapshot(automationKey: "task29-start")
        let startRequest = makeGatewayStartRequest(
            installationId: bootstrapRequest.installationId,
            deviceToken: issuedToken,
            requestId: "request-start-001",
            project: startProject,
            userMessage: "先写一个开头"
        )

        try app.test(.POST, "v3/writes/start", beforeRequest: { request in
            try request.content.encode(startRequest)
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
            }
        })

        let continueProject = sampleProjectSnapshot(automationKey: "task29-continue")
        let continueRequest = makeGatewayContinueRequest(
            installationId: bootstrapRequest.installationId,
            deviceToken: issuedToken,
            requestId: "request-continue-001",
            project: continueProject,
            userMessage: "继续写下去"
        )

        try app.test(.POST, "v3/writes/continue", beforeRequest: { request in
            try request.content.encode(continueRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(WritingGatewayResponse.self, response) { writeResponse in
                XCTAssertEqual(writeResponse.assistantMessage, "我接着往下写了一段，让主线继续往前走。")
                XCTAssertEqual(
                    writeResponse.appendedText,
                    """
                    
                    接下来可以顺着这个主线，再补一段更自然的推进。
                    """
                )
                XCTAssertNil(writeResponse.documentText)
                XCTAssertNil(writeResponse.replacementText)
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
                XCTAssertEqual(writeResponse.mode, continueProject.mode)
            }
        })
    }

    func testContinueDraftRejectsMismatchedToken() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let continueRequest = makeGatewayContinueRequest(
            installationId: "installation-continue-002",
            deviceToken: "not-a-real-token",
            requestId: "request-continue-002",
            project: sampleProjectSnapshot(automationKey: "task29-invalid")
        )

        try app.test(.POST, "v3/writes/continue", beforeRequest: { request in
            try request.content.encode(continueRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .unauthorized)
        })
    }

    private func sampleProjectSnapshot(
        automationKey: String,
        documentText: String = "开头正文"
    ) -> WritingProjectSnapshot {
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
            documentText: documentText,
            suggestionChips: ["继续", "收紧"],
            updatedAt: Date(timeIntervalSince1970: 1_719_000_000)
        )
    }
}
