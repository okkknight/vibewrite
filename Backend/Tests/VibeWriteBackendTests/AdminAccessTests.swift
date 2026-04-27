import Foundation
import XCTVapor
@testable import VibeWriteBackend
import VibeWriteShared

final class AdminAccessTests: XCTestCase {
    func testAdminPageShowsLoginFormWhenAnonymous() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, adminUsername: "admin", adminPassword: "password")

        try app.test(.GET, "v3/admin", afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertTrue(response.headers.first(name: .contentType)?.contains("text/html") == true)

            let body = response.body.string
            XCTAssertTrue(body.contains("data-authenticated=\"false\""))
            XCTAssertTrue(body.contains("id=\"login-panel\""))
            XCTAssertTrue(body.contains("id=\"dashboard-panel\" class=\"hidden\""))
            XCTAssertTrue(body.contains("管理员登录"))
        })
    }

    func testAdminPageShowsDashboardWhenAuthenticatedAndReturnsToLoginAfterLogout() throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, adminUsername: "admin", adminPassword: "password")

        let cookieHeader = try adminSessionCookieHeader(in: app, username: "admin", password: "password")

        try app.test(.GET, "v3/admin", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertTrue(response.headers.first(name: .contentType)?.contains("text/html") == true)

            let body = response.body.string
            XCTAssertTrue(body.contains("data-authenticated=\"true\""))
            XCTAssertTrue(body.contains("id=\"dashboard-panel\""))
            XCTAssertTrue(body.contains("总览"))
            XCTAssertTrue(body.contains("请求列表"))
            XCTAssertTrue(body.contains("密钥"))
            XCTAssertTrue(body.contains("AI System Prompt"))
            XCTAssertTrue(body.contains("Quota"))
            XCTAssertTrue(body.contains("Devices"))
            XCTAssertTrue(body.contains("id=\"login-panel\" class=\"panel login hidden\""))
        })

        try app.test(.POST, "v3/admin/logout", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
        })

        try app.test(.GET, "v3/admin", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)

            let body = response.body.string
            XCTAssertTrue(body.contains("data-authenticated=\"false\""))
            XCTAssertTrue(body.contains("管理员登录"))
            XCTAssertTrue(body.contains("id=\"dashboard-panel\" class=\"hidden\""))
        })
    }

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

    func testAdminOverviewReflectsTodayCountsAndBackendConfiguration() throws {
        let clock = TestClock(date: shanghaiDate(year: 2026, month: 4, day: 13, hour: 9))
        let quotaLedger = InMemoryQuotaLedger(
            limit: QuotaLimit(dailyLimit: 1, weeklyLimit: 1),
            clock: clock
        )
        let requestLogStore = InMemoryRequestLogStore()
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(
            app,
            quotaLedger: quotaLedger,
            requestLogStore: requestLogStore,
            clock: clock,
            adminUsername: "admin",
            adminPassword: "password"
        )

        let bootstrap = try bootstrapDevice(in: app, installationId: "installation-overview-001")
        let project = sampleProjectSnapshot(documentText: "prefix middle suffix")

        try sendStart(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            requestId: "request-overview-accepted"
        )

        try app.test(.POST, "v3/writes/continue", beforeRequest: { request in
            try request.content.encode(makeGatewayContinueRequest(
                installationId: bootstrap.installationId,
                deviceToken: bootstrap.deviceToken,
                requestId: "request-overview-quota",
                project: project,
                userMessage: "继续写"
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .tooManyRequests)
        })

        let cookieHeader = try adminSessionCookieHeader(in: app, username: "admin", password: "password")

        try app.test(.GET, "v3/admin/overview", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminOverviewResponse.self, response) { body in
                XCTAssertEqual(body.todayRequestCount, 2)
                XCTAssertEqual(body.todaySuccessRate, 0.5, accuracy: 0.0001)
                XCTAssertEqual(body.todayQuotaExceededCount, 1)
                XCTAssertEqual(body.activeDeviceCount, 1)
                XCTAssertEqual(body.provider, "minimax")
                XCTAssertEqual(body.model, "MiniMax-M2.5-highspeed")
                XCTAssertEqual(body.dailyLimit, 1)
                XCTAssertEqual(body.weeklyLimit, 1)
            }
        })
    }

    func testAdminQuotaUpdateChangesBootstrapAndWriteLimitsImmediately() throws {
        let clock = TestClock(date: shanghaiDate(year: 2026, month: 4, day: 13, hour: 9))
        let requestLogStore = InMemoryRequestLogStore()
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(
            app,
            requestLogStore: requestLogStore,
            clock: clock,
            adminUsername: "admin",
            adminPassword: "password"
        )

        let cookieHeader = try adminSessionCookieHeader(in: app, username: "admin", password: "password")

        try app.test(.GET, "v3/admin/quota", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminQuotaResponse.self, response) { body in
                XCTAssertEqual(body.dailyLimit, 500)
                XCTAssertEqual(body.weeklyLimit, 2_000)
                XCTAssertEqual(body.dailyUsed, 0)
                XCTAssertEqual(body.weeklyUsed, 0)
                XCTAssertFalse(body.updatedAt.isEmpty)
            }
        })

        try app.test(.PUT, "v3/admin/quota", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
            try request.content.encode(AdminQuotaUpdateRequest(dailyLimit: 1, weeklyLimit: 2))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminQuotaResponse.self, response) { body in
                XCTAssertEqual(body.dailyLimit, 1)
                XCTAssertEqual(body.weeklyLimit, 2)
                XCTAssertEqual(body.dailyUsed, 0)
                XCTAssertEqual(body.weeklyUsed, 0)
                XCTAssertFalse(body.updatedAt.isEmpty)
            }
        })

        let bootstrap = try bootstrapDevice(in: app, installationId: "installation-quota-admin-001")
        XCTAssertEqual(bootstrap.deviceToken.isEmpty, false)

        try app.test(.POST, "v3/writes/start", beforeRequest: { request in
            try request.content.encode(makeGatewayStartRequest(
                installationId: bootstrap.installationId,
                deviceToken: bootstrap.deviceToken,
                requestId: "request-quota-admin-start",
                project: sampleProjectSnapshot(documentText: "prefix middle suffix"),
                userMessage: "先写开头"
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
        })

        try app.test(.POST, "v3/writes/continue", beforeRequest: { request in
            try request.content.encode(makeGatewayContinueRequest(
                installationId: bootstrap.installationId,
                deviceToken: bootstrap.deviceToken,
                requestId: "request-quota-admin-continue",
                project: sampleProjectSnapshot(documentText: "prefix middle suffix"),
                userMessage: "继续写"
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .tooManyRequests)
        })

        try app.test(.GET, "v3/admin/quota", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminQuotaResponse.self, response) { body in
                XCTAssertEqual(body.dailyLimit, 1)
                XCTAssertEqual(body.weeklyLimit, 2)
                XCTAssertEqual(body.dailyUsed, 1)
                XCTAssertEqual(body.weeklyUsed, 1)
            }
        })

        try app.test(.POST, "v3/client/bootstrap", beforeRequest: { request in
            try request.content.encode(BootstrapRequest(
                installationId: bootstrap.installationId,
                appVersion: "3.0.0",
                platform: "macOS",
                deviceName: "QA Mac"
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(BootstrapResponse.self, response) { bootstrapResponse in
                XCTAssertEqual(bootstrapResponse.quotaSummary.dailyLimit, 1)
                XCTAssertEqual(bootstrapResponse.quotaSummary.weeklyLimit, 2)
            }
        })
    }

    func testAdminDeviceBlockAndUnblockAffectBootstrapAndWrites() throws {
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

        let bootstrap = try bootstrapDevice(in: app, installationId: "installation-device-001")
        let project = sampleProjectSnapshot(documentText: "prefix middle suffix")

        try sendStart(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            requestId: "request-device-accepted"
        )

        let cookieHeader = try adminSessionCookieHeader(in: app, username: "admin", password: "password")

        try app.test(.POST, "v3/admin/devices/\(bootstrap.installationId)/block", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
            try request.content.encode(AdminDeviceBlockRequest(blockReason: "manual maintenance"))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminDeviceResponse.self, response) { body in
                XCTAssertEqual(body.installationId, bootstrap.installationId)
                XCTAssertEqual(body.status, .blocked)
                XCTAssertEqual(body.blockReason, "manual maintenance")
                XCTAssertFalse(body.blockedAt == nil)
            }
        })

        try app.test(.GET, "v3/admin/devices", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminDeviceListResponse.self, response) { body in
                XCTAssertEqual(body.devices.count, 1)
                XCTAssertEqual(body.devices[0].installationId, bootstrap.installationId)
                XCTAssertEqual(body.devices[0].status, .blocked)
                XCTAssertEqual(body.devices[0].todayUsed, 1)
                XCTAssertEqual(body.devices[0].weeklyUsed, 1)
                XCTAssertEqual(body.devices[0].blockReason, "manual maintenance")
                XCTAssertFalse(body.devices[0].blockedAt == nil)
            }
        })

        try app.test(.POST, "v3/client/bootstrap", beforeRequest: { request in
            try request.content.encode(BootstrapRequest(
                installationId: bootstrap.installationId,
                appVersion: "3.0.0",
                platform: "macOS",
                deviceName: "QA Mac"
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(BootstrapResponse.self, response) { bootstrapResponse in
                XCTAssertEqual(bootstrapResponse.deviceStatus, .blocked)
                XCTAssertEqual(bootstrapResponse.deviceToken, bootstrap.deviceToken)
            }
        })

        try app.test(.POST, "v3/writes/start", beforeRequest: { request in
            try request.content.encode(makeGatewayStartRequest(
                installationId: bootstrap.installationId,
                deviceToken: bootstrap.deviceToken,
                requestId: "request-device-blocked",
                project: project,
                userMessage: "先写开头"
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .forbidden)
        })

        let rejectedLogs = try blockingValue {
            (await requestLogStore.snapshot()).filter { $0.requestId == "request-device-blocked" }
        }
        XCTAssertEqual(rejectedLogs.count, 1)
        XCTAssertEqual(rejectedLogs[0].status, .rejected)
        XCTAssertEqual(rejectedLogs[0].errorCode, "device_blocked")

        try app.test(.GET, "v3/admin/quota", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminQuotaResponse.self, response) { body in
                XCTAssertEqual(body.dailyUsed, 1)
                XCTAssertEqual(body.weeklyUsed, 1)
            }
        })

        try app.test(.POST, "v3/admin/devices/\(bootstrap.installationId)/unblock", beforeRequest: { request in
            request.headers.replaceOrAdd(name: .cookie, value: cookieHeader)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(AdminDeviceResponse.self, response) { body in
                XCTAssertEqual(body.installationId, bootstrap.installationId)
                XCTAssertEqual(body.status, .active)
                XCTAssertNil(body.blockedAt)
                XCTAssertNil(body.blockReason)
            }
        })

        try app.test(.POST, "v3/client/bootstrap", beforeRequest: { request in
            try request.content.encode(BootstrapRequest(
                installationId: bootstrap.installationId,
                appVersion: "3.0.0",
                platform: "macOS",
                deviceName: "QA Mac"
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(BootstrapResponse.self, response) { bootstrapResponse in
                XCTAssertEqual(bootstrapResponse.deviceStatus, .active)
            }
        })

        try app.test(.POST, "v3/writes/start", beforeRequest: { request in
            try request.content.encode(makeGatewayStartRequest(
                installationId: bootstrap.installationId,
                deviceToken: bootstrap.deviceToken,
                requestId: "request-device-unblocked",
                project: project,
                userMessage: "先写开头"
            ))
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
        })
    }

    private func blockingValue<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = BlockingResultBox<T>()
        let job: @Sendable () async -> Void = {
            do {
                box.store(.success(try await operation()))
            } catch {
                box.store(.failure(error))
            }
            semaphore.signal()
        }
        Task.detached(operation: job)
        semaphore.wait()
        return try box.load()
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
        let request = makeGatewayStartRequest(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: requestId,
            project: project,
            userMessage: "先写开头"
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
        let request = makeGatewayContinueRequest(
            installationId: installationId,
            deviceToken: "invalid-token",
            requestId: requestId,
            project: sampleProjectSnapshot(documentText: "prefix middle suffix"),
            userMessage: "继续写"
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
        let request = makeGatewayEditRequest(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: requestId,
            project: project,
            selectionRange: selectionRange,
            userMessage: "把中间改得更克制"
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

private final class BlockingResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func store(_ result: Result<T, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try result!.get()
    }
}
