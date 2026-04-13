import Foundation
import Vapor

func registerAdminRoutes(
    _ app: Application,
    deviceRegistry: InMemoryDeviceRegistry,
    quotaLedger: InMemoryQuotaLedger,
    requestLogStore: InMemoryRequestLogStore,
    secretStore: AdminSecretStore,
    systemPromptStore: AdminSystemPromptStore,
    adminSessionStore: AdminSessionStore,
    aiConfiguration: BackendAIConfiguration,
    clock: any VibeWriteClock
) throws {
    app.post("v3", "admin", "login") { req async throws -> Response in
        let request = try req.content.decode(AdminLoginRequest.self)
        guard await secretStore.authenticate(username: request.username, password: request.password) else {
            throw Abort(.unauthorized, reason: "Invalid admin credentials.")
        }

        return try makeJSONResponse(
            AdminStatusResponse(status: "ok"),
            setCookieHeader: AdminSessionCookie.loginHeader(for: await adminSessionStore.issueSession())
        )
    }

    app.post("v3", "admin", "logout") { req async throws -> Response in
        await adminSessionStore.logout(sessionToken: AdminSessionCookie.sessionToken(from: req))

        return try makeJSONResponse(
            AdminStatusResponse(status: "ok"),
            setCookieHeader: AdminSessionCookie.logoutHeader()
        )
    }

    app.get("v3", "admin", "requests") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        let query = try req.query.decode(AdminRequestQuery.self)
        let requestLogQuery = try makeRequestLogQuery(from: query)
        return try makeJSONResponse(requestLogStore.query(requestLogQuery))
    }

    app.get("v3", "admin", "overview") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        let now = clock.now()
        let todayRange = currentDayRange(now: now)
        let todaySummary = requestLogStore.query(
            RequestLogQuery(
                installationId: nil,
                action: nil,
                status: nil,
                errorCode: nil,
                createdAtRange: todayRange
            )
        ).summary
        let quotaExceededCount = requestLogStore.query(
            RequestLogQuery(
                installationId: nil,
                action: nil,
                status: .rejected,
                errorCode: "quota_exceeded",
                createdAtRange: todayRange
            )
        ).summary.totalCount
        let currentLimit = await quotaLedger.currentLimit()

        return try makeJSONResponse(
            AdminOverviewResponse(
                todayRequestCount: todaySummary.totalCount,
                todaySuccessRate: todaySummary.totalCount == 0
                    ? 0
                    : Double(todaySummary.acceptedCount) / Double(todaySummary.totalCount),
                todayQuotaExceededCount: quotaExceededCount,
                activeDeviceCount: await deviceRegistry.activeDeviceCount(),
                provider: aiConfiguration.provider,
                model: aiConfiguration.model,
                dailyLimit: currentLimit.dailyLimit,
                weeklyLimit: currentLimit.weeklyLimit
            )
        )
    }

    app.get("v3", "admin", "quota") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        let snapshot = await quotaLedger.currentUsageSnapshot()
        return try makeJSONResponse(
            AdminQuotaResponse(
                dailyLimit: snapshot.limit.dailyLimit,
                weeklyLimit: snapshot.limit.weeklyLimit,
                dailyUsed: snapshot.totalDailyUsed,
                weeklyUsed: snapshot.totalWeeklyUsed,
                updatedAt: AdminDateCodec.string(from: snapshot.limitUpdatedAt)
            )
        )
    }

    app.put("v3", "admin", "quota") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        let request = try req.content.decode(AdminQuotaUpdateRequest.self)

        if let dailyLimit = request.dailyLimit, dailyLimit < 0 {
            throw Abort(.badRequest, reason: "dailyLimit must be zero or greater.")
        }

        if let weeklyLimit = request.weeklyLimit, weeklyLimit < 0 {
            throw Abort(.badRequest, reason: "weeklyLimit must be zero or greater.")
        }

        await quotaLedger.updateLimit(dailyLimit: request.dailyLimit, weeklyLimit: request.weeklyLimit)
        let snapshot = await quotaLedger.currentUsageSnapshot()
        return try makeJSONResponse(
            AdminQuotaResponse(
                dailyLimit: snapshot.limit.dailyLimit,
                weeklyLimit: snapshot.limit.weeklyLimit,
                dailyUsed: snapshot.totalDailyUsed,
                weeklyUsed: snapshot.totalWeeklyUsed,
                updatedAt: AdminDateCodec.string(from: snapshot.limitUpdatedAt)
            )
        )
    }

    app.get("v3", "admin", "devices") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        return try makeJSONResponse(
            AdminDeviceListResponse(
                devices: await makeAdminDeviceResponses(
                    deviceRegistry: deviceRegistry,
                    quotaLedger: quotaLedger
                )
            )
        )
    }

    app.post("v3", "admin", "devices", ":installationId", "block") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        guard let installationId = req.parameters.get("installationId"), !installationId.isEmpty else {
            throw Abort(.badRequest, reason: "installationId is required.")
        }

        let blockRequest = try? req.content.decode(AdminDeviceBlockRequest.self)
        let snapshot = await deviceRegistry.block(
            installationId: installationId,
            reason: blockRequest?.blockReason
        )

        return try makeJSONResponse(
            makeAdminDeviceResponse(
                from: snapshot,
                usage: await quotaLedger.usageSnapshot(for: installationId)
            )
        )
    }

    app.post("v3", "admin", "devices", ":installationId", "unblock") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        guard let installationId = req.parameters.get("installationId"), !installationId.isEmpty else {
            throw Abort(.badRequest, reason: "installationId is required.")
        }

        let snapshot = await deviceRegistry.unblock(installationId: installationId)
        return try makeJSONResponse(
            makeAdminDeviceResponse(
                from: snapshot,
                usage: await quotaLedger.usageSnapshot(for: installationId)
            )
        )
    }

    app.get("v3", "admin", "secrets") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        return try makeJSONResponse(await secretStore.snapshotResponse())
    }

    app.put("v3", "admin", "secrets") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        let request = try req.content.decode(AdminSecretsUpdateRequest.self)
        await secretStore.update(
            providerApiKey: request.providerApiKey,
            adminUsername: request.adminUsername,
            adminPassword: request.adminPassword
        )
        return try makeJSONResponse(await secretStore.snapshotResponse())
    }

    app.get("v3", "admin", "system-prompt") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        return try makeJSONResponse(await systemPromptStore.snapshotResponse())
    }

    app.put("v3", "admin", "system-prompt") { req async throws -> Response in
        guard await adminSessionStore.isAuthenticated(sessionToken: AdminSessionCookie.sessionToken(from: req)) else {
            throw Abort(.unauthorized, reason: "Admin session required.")
        }

        let request = try req.content.decode(AdminSystemPromptUpdateRequest.self)
        try await systemPromptStore.update(
            templateBody: request.templateBody,
            actionRulesJson: request.actionRulesJson,
            modelContextRulesJson: request.modelContextRulesJson
        )

        return try makeJSONResponse(await systemPromptStore.snapshotResponse())
    }
}

private func currentDayRange(now: Date, timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current) -> ClosedRange<Date> {
    let calendar = Calendar(identifier: .gregorian)
    var adjusted = calendar
    adjusted.timeZone = timeZone
    let startOfDay = adjusted.startOfDay(for: now)
    return startOfDay...now
}

private func makeAdminDeviceResponses(
    deviceRegistry: InMemoryDeviceRegistry,
    quotaLedger: InMemoryQuotaLedger
) async -> [AdminDeviceResponse] {
    let deviceSnapshots = await deviceRegistry.snapshot()
    let quotaSnapshots = await quotaLedger.snapshotUsage()
    let usageByInstallationId = Dictionary(
        uniqueKeysWithValues: quotaSnapshots.map { snapshot in
            (snapshot.installationId, snapshot)
        }
    )

    return deviceSnapshots.map { snapshot in
        makeAdminDeviceResponse(
            from: snapshot,
            usage: usageByInstallationId[snapshot.installationId]
        )
    }
}

private func makeAdminDeviceResponse(
    from snapshot: DeviceSnapshot,
    usage: QuotaUsageSnapshot?
) -> AdminDeviceResponse {
    AdminDeviceResponse(
        installationId: snapshot.installationId,
        status: snapshot.status,
        firstSeenAt: AdminDateCodec.string(from: snapshot.firstSeenAt),
        lastSeenAt: AdminDateCodec.string(from: snapshot.lastSeenAt),
        tokenIssuedAt: AdminDateCodec.string(from: snapshot.tokenIssuedAt),
        todayUsed: usage?.dailyUsed ?? 0,
        weeklyUsed: usage?.weeklyUsed ?? 0,
        blockedAt: snapshot.blockedAt.map { AdminDateCodec.string(from: $0) },
        blockReason: snapshot.blockReason
    )
}

private func makeRequestLogQuery(from query: AdminRequestQuery) throws -> RequestLogQuery {
    let createdAtStart = query.createdAtStart.flatMap(AdminDateCodec.parse)
    let createdAtEnd = query.createdAtEnd.flatMap(AdminDateCodec.parse)

    if query.createdAtStart != nil, createdAtStart == nil {
        throw Abort(.badRequest, reason: "createdAtStart must be a valid ISO-8601 date.")
    }

    if query.createdAtEnd != nil, createdAtEnd == nil {
        throw Abort(.badRequest, reason: "createdAtEnd must be a valid ISO-8601 date.")
    }

    if let createdAtStart, let createdAtEnd, createdAtStart > createdAtEnd {
        throw Abort(.badRequest, reason: "createdAtStart must be on or before createdAtEnd.")
    }

    let createdAtRange: ClosedRange<Date>? = {
        switch (createdAtStart, createdAtEnd) {
        case let (.some(start), .some(end)):
            return start...end
        case let (.some(start), nil):
            return start...Date.distantFuture
        case let (nil, .some(end)):
            return Date.distantPast...end
        case (nil, nil):
            return nil
        }
    }()

    return RequestLogQuery(
        installationId: query.installationId,
        action: query.action,
        status: query.status,
        errorCode: query.errorCode,
        createdAtRange: createdAtRange
    )
}

private func makeJSONResponse<T: Content>(
    _ body: T,
    setCookieHeader: String? = nil
) throws -> Response {
    let response = Response(status: .ok)
    try response.content.encode(body)

    if let setCookieHeader {
        response.headers.replaceOrAdd(name: .setCookie, value: setCookieHeader)
    }

    return response
}
