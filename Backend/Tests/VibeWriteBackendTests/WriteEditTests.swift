import Foundation
import XCTVapor
@testable import VibeWriteBackend
import VibeWriteShared

final class WriteEditTests: XCTestCase {
    func testEditDraftAcceptsMatchingBootstrapTokenWithValidSelection() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let bootstrapRequest = BootstrapRequest(
            installationId: "installation-edit-001",
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

        let project = sampleProjectSnapshot()
        let selectionRange = WritingTextSelectionRange(location: 4, length: 4)
        let editRequest = WriteRequestEnvelope(
            installationId: bootstrapRequest.installationId,
            deviceToken: issuedToken,
            requestId: "request-edit-001",
            action: .edit,
            kind: .prose,
            project: project,
            userMessage: "把选中内容改得更克制",
            selectionText: selectionRange.substring(in: project.documentText),
            selectionRange: selectionRange
        )

        try app.test(.POST, "v3/writes/edit", beforeRequest: { request in
            try request.content.encode(editRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(WritingAIResponse.self, response) { writeResponse in
                XCTAssertEqual(writeResponse.assistantMessage, "[stub] /v3/writes/edit accepted")
                XCTAssertEqual(writeResponse.documentText, editRequest.project.documentText)
                XCTAssertEqual(writeResponse.localSummary, editRequest.project.localSummary)
                XCTAssertEqual(writeResponse.globalSynopsis, editRequest.project.globalSynopsis)
                XCTAssertEqual(writeResponse.intentSummary, editRequest.project.context.intentSummary)
                XCTAssertEqual(writeResponse.styleConstraints, editRequest.project.context.styleConstraints)
                XCTAssertEqual(writeResponse.currentGoal, editRequest.project.context.currentGoal)
                XCTAssertEqual(writeResponse.recentDecisions, editRequest.project.context.recentDecisions)
                XCTAssertEqual(writeResponse.workingMemory, editRequest.project.context.workingMemory)
                XCTAssertEqual(writeResponse.nextFocus, editRequest.project.context.nextFocus)
                XCTAssertEqual(writeResponse.suggestionChips, editRequest.project.suggestionChips)
                XCTAssertEqual(writeResponse.mode, editRequest.project.mode)
            }
        })
    }

    func testEditDraftRejectsInvalidSelectionRange() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let bootstrapRequest = BootstrapRequest(
            installationId: "installation-edit-002",
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

        let editRequest = WriteRequestEnvelope(
            installationId: bootstrapRequest.installationId,
            deviceToken: issuedToken,
            requestId: "request-edit-002",
            action: .edit,
            kind: .prose,
            project: sampleProjectSnapshot(),
            userMessage: "把这段改一下",
            selectionText: "不存在的选区",
            selectionRange: WritingTextSelectionRange(location: 999, length: 5)
        )

        try app.test(.POST, "v3/writes/edit", beforeRequest: { request in
            try request.content.encode(editRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .badRequest)
        })
    }

    func testEditDraftRejectsMismatchedToken() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app)

        let editRequest = WriteRequestEnvelope(
            installationId: "installation-edit-003",
            deviceToken: "not-a-real-token",
            requestId: "request-edit-003",
            action: .edit,
            kind: .prose,
            project: sampleProjectSnapshot(),
            userMessage: nil,
            selectionText: "选中文段",
            selectionRange: WritingTextSelectionRange(location: 4, length: 4)
        )

        try app.test(.POST, "v3/writes/edit", beforeRequest: { request in
            try request.content.encode(editRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .unauthorized)
        })
    }

    private func sampleProjectSnapshot() -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000030") ?? UUID(),
            automationKey: "task30",
            title: "写作任务",
            prompt: "把这段改一下",
            mode: .collaboration,
            localSummary: "本地摘要",
            globalSynopsis: "全局梗概",
            context: ProjectContext(
                intentSummary: "围绕选中文段局部协作",
                styleConstraints: ["克制", "平静"],
                currentGoal: "局部润色",
                recentDecisions: ["先改选中段落"],
                workingMemory: ["当前要做局部编辑"],
                nextFocus: "继续收紧局部语气"
            ),
            conversation: [
                ConversationMessage(role: .user, text: "把这段改一下", timestamp: "2026-04-12T00:00:00Z")
            ],
            documentText: "前文正文选中文段后文正文",
            suggestionChips: ["更克制", "更抓人"],
            updatedAt: Date(timeIntervalSince1970: 1_719_000_000)
        )
    }
}
