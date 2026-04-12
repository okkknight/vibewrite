import Foundation
import XCTVapor
@testable import VibeWriteBackend
import VibeWriteShared

final class AdminAccessTests: XCTestCase {
    func testLoginSuccessSetsAdminSessionCookie() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, adminUsername: "admin", adminPassword: "password")

        try app.test(.POST, "v3/admin/login", beforeRequest: { request in
            try request.content.encode(AdminLoginRequest(username: "admin", password: "password"))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminStatusResponse.self, response) { body in
                XCTAssertEqual(body.status, "ok")
            }

            let setCookieHeader = response.headers.first(name: .setCookie)
            XCTAssertNotNil(setCookieHeader)
            XCTAssertTrue(setCookieHeader?.contains(AdminSessionCookie.name) == true)
            XCTAssertTrue(setCookieHeader?.contains("HttpOnly") == true)
            XCTAssertTrue(setCookieHeader?.contains("SameSite=Lax") == true)
        })
    }

    func testBadCredentialsFailLogin() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, adminUsername: "admin", adminPassword: "password")

        try app.test(.POST, "v3/admin/login", beforeRequest: { request in
            try request.content.encode(AdminLoginRequest(username: "admin", password: "wrong"))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .unauthorized)
        })
    }

    func testAdminRequestsRequireSessionCookie() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, adminUsername: "admin", adminPassword: "password")

        try app.test(.GET, "v3/admin/requests", afterResponse: { response in
            XCTAssertEqual(response.status, .unauthorized)
        })
    }

    func testLoggedInAdminCanQueryRequestsAndSummary() throws {
        let requestLogStore = InMemoryRequestLogStore()
        let clock = TestClock(date: shanghaiDate(year: 2026, month: 4, day: 13, hour: 9))
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(
            app,
            requestLogStore: requestLogStore,
            clock: clock,
            adminUsername: "admin",
            adminPassword: "password"
        )

        let bootstrap = try bootstrapDevice(in: app, installationId: "installation-admin-001")
        let project = sampleProjectSnapshot(documentText: "prefix middle suffix")

        try sendStart(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            requestId: "request-admin-start"
        )

        try sendRejectedContinue(
            in: app,
            installationId: bootstrap.installationId,
            requestId: "request-admin-rejected"
        )

        clock.set(shanghaiDate(year: 2026, month: 4, day: 14, hour: 11))

        try sendEdit(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            requestId: "request-admin-edit"
        )

        let cookieHeader = try adminSessionCookieHeader(in: app, username: "admin", password: "password")

        try app.test(.GET, queryPath(
            "v3/admin/requests",
            queryItems: [
                .init(name: "installationId", value: bootstrap.installationId)
            ]
        ), beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(RequestLogQueryResult.self, response) { result in
                XCTAssertEqual(result.entries.map(\.requestId), [
                    "request-admin-edit",
                    "request-admin-start",
                    "request-admin-rejected"
                ])
                XCTAssertEqual(result.summary.totalCount, 3)
                XCTAssertEqual(result.summary.acceptedCount, 2)
                XCTAssertEqual(result.summary.rejectedCount, 1)
            }
        })

        try app.test(.GET, queryPath(
            "v3/admin/requests",
            queryItems: [
                .init(name: "installationId", value: bootstrap.installationId),
                .init(name: "action", value: WritingAIAction.edit.rawValue),
                .init(name: "status", value: RequestLogStatus.accepted.rawValue),
                .init(name: "createdAtStart", value: AdminDateCodec.string(from: shanghaiDate(year: 2026, month: 4, day: 14, hour: 0))),
                .init(name: "createdAtEnd", value: AdminDateCodec.string(from: shanghaiDate(year: 2026, month: 4, day: 14, hour: 23)))
            ]
        ), beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(RequestLogQueryResult.self, response) { result in
                XCTAssertEqual(result.entries.map(\.requestId), ["request-admin-edit"])
                XCTAssertEqual(result.summary.totalCount, 1)
                XCTAssertEqual(result.summary.acceptedCount, 1)
                XCTAssertEqual(result.summary.rejectedCount, 0)
            }
        })

        try app.test(.GET, queryPath(
            "v3/admin/requests",
            queryItems: [
                .init(name: "installationId", value: bootstrap.installationId),
                .init(name: "status", value: RequestLogStatus.rejected.rawValue),
                .init(name: "errorCode", value: "unauthorized")
            ]
        ), beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(RequestLogQueryResult.self, response) { result in
                XCTAssertEqual(result.entries.map(\.requestId), ["request-admin-rejected"])
                XCTAssertEqual(result.summary.totalCount, 1)
                XCTAssertEqual(result.summary.acceptedCount, 0)
                XCTAssertEqual(result.summary.rejectedCount, 1)
            }
        })
    }

    func testLoggedInAdminCanReadRedactedSecretsSnapshot() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(
            app,
            adminUsername: "admin",
            adminPassword: "password"
        )

        let cookieHeader = try adminSessionCookieHeader(in: app, username: "admin", password: "password")

        try app.test(.GET, "v3/admin/secrets", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminSecretsResponse.self, response) { body in
                XCTAssertEqual(body.providerApiKeyConfigured, false)
                XCTAssertEqual(body.adminUsername, "admin")
                XCTAssertEqual(body.adminPasswordConfigured, true)
                XCTAssertFalse(body.updatedAt.isEmpty)
            }
        })
    }

    func testAdminSecretsUpdateTakesEffectImmediatelyAndPreservesExistingSession() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(
            app,
            adminUsername: "admin",
            adminPassword: "password"
        )

        let cookieHeader = try adminSessionCookieHeader(in: app, username: "admin", password: "password")

        try app.test(.PUT, "v3/admin/secrets", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
            try request.content.encode(AdminSecretsUpdateRequest(
                providerApiKey: "minimax-test-key",
                adminUsername: "superadmin",
                adminPassword: "supersecret"
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminSecretsResponse.self, response) { body in
                XCTAssertEqual(body.providerApiKeyConfigured, true)
                XCTAssertEqual(body.adminUsername, "superadmin")
                XCTAssertEqual(body.adminPasswordConfigured, true)
                XCTAssertFalse(body.updatedAt.isEmpty)
            }
        })

        try app.test(.GET, "v3/admin/secrets", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
        })

        try app.test(.POST, "v3/admin/login", beforeRequest: { request in
            try request.content.encode(AdminLoginRequest(username: "admin", password: "password"))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .unauthorized)
        })

        var updatedSessionCookieHeader: String?
        try app.test(.POST, "v3/admin/login", beforeRequest: { request in
            try request.content.encode(AdminLoginRequest(username: "superadmin", password: "supersecret"))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            updatedSessionCookieHeader = response.headers.first(name: .setCookie)
        })

        guard let updatedSessionCookieHeader else {
            XCTFail("Expected updated admin credentials to log in.")
            return
        }

        guard let updatedSessionToken = AdminSessionCookie.sessionToken(fromSetCookieHeader: updatedSessionCookieHeader) else {
            XCTFail("Expected updated admin session cookie to be set.")
            return
        }

        try app.test(.GET, "v3/admin/requests", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: "\(AdminSessionCookie.name)=\(updatedSessionToken)")
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
        })
    }

    func testLogoutInvalidatesAdminSession() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, adminUsername: "admin", adminPassword: "password")

        let cookieHeader = try adminSessionCookieHeader(in: app, username: "admin", password: "password")

        try app.test(.POST, "v3/admin/logout", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminStatusResponse.self, response) { body in
                XCTAssertEqual(body.status, "ok")
            }
        })

        try app.test(.GET, "v3/admin/requests", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .unauthorized)
        })
    }

    private func adminSessionCookieHeader(in app: Application, username: String, password: String) throws -> String {
        var setCookieHeader: String?
        try app.test(.POST, "v3/admin/login", beforeRequest: { request in
            try request.content.encode(AdminLoginRequest(username: username, password: password))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            setCookieHeader = response.headers.first(name: .setCookie)
        })

        guard let sessionToken = AdminSessionCookie.sessionToken(fromSetCookieHeader: setCookieHeader) else {
            XCTFail("Expected admin session cookie to be set.")
            return ""
        }

        return "\(AdminSessionCookie.name)=\(sessionToken)"
    }

    private func bootstrapDevice(in app: Application, installationId: String) throws -> (installationId: String, deviceToken: String) {
        let bootstrapRequest = BootstrapRequest(
            installationId: installationId,
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

        return (bootstrapRequest.installationId, issuedToken)
    }

    private func sendStart(
        in app: Application,
        installationId: String,
        deviceToken: String,
        project: WritingProjectSnapshot,
        requestId: String
    ) throws {
        let request = WriteRequestEnvelope(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: requestId,
            action: .startDraft,
            kind: .prose,
            project: project,
            userMessage: "先写开头",
            selectionText: nil,
            selectionRange: nil
        )

        try app.test(.POST, "v3/writes/start", beforeRequest: { req in
            try req.content.encode(request)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
        })
    }

    private func sendRejectedContinue(
        in app: Application,
        installationId: String,
        requestId: String
    ) throws {
        let request = WriteRequestEnvelope(
            installationId: installationId,
            deviceToken: "invalid-token",
            requestId: requestId,
            action: .continueWriting,
            kind: .prose,
            project: sampleProjectSnapshot(documentText: "prefix middle suffix"),
            userMessage: "继续写",
            selectionText: nil,
            selectionRange: nil
        )

        try app.test(.POST, "v3/writes/continue", beforeRequest: { req in
            try req.content.encode(request)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .unauthorized)
        })
    }

    private func sendEdit(
        in app: Application,
        installationId: String,
        deviceToken: String,
        project: WritingProjectSnapshot,
        requestId: String
    ) throws {
        let selectionRange = WritingTextSelectionRange(location: 7, length: 6)
        let request = WriteRequestEnvelope(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: requestId,
            action: .edit,
            kind: .prose,
            project: project,
            userMessage: "把中间改得更克制",
            selectionText: selectionRange.substring(in: project.documentText),
            selectionRange: selectionRange
        )

        try app.test(.POST, "v3/writes/edit", beforeRequest: { req in
            try req.content.encode(request)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
        })
    }

    private func sampleProjectSnapshot(documentText: String) -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000034") ?? UUID(),
            automationKey: "task34",
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
            documentText: documentText,
            suggestionChips: ["继续", "收紧"],
            updatedAt: Date(timeIntervalSince1970: 1_719_000_000)
        )
    }

    private func shanghaiDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Asia/Shanghai")
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    private func queryPath(_ path: String, queryItems: [URLQueryItem]) -> String {
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.string ?? path
    }
}
