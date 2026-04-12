import Vapor

func registerAdminRoutes(
    _ app: Application,
    requestLogStore: InMemoryRequestLogStore,
    adminSessionStore: AdminSessionStore
) throws {
    app.post("v3", "admin", "login") { req async throws -> Response in
        let request = try req.content.decode(AdminLoginRequest.self)
        guard let sessionToken = await adminSessionStore.login(
            username: request.username,
            password: request.password
        ) else {
            throw Abort(.unauthorized, reason: "Invalid admin credentials.")
        }

        return try makeJSONResponse(
            AdminStatusResponse(status: "ok"),
            setCookieHeader: AdminSessionCookie.loginHeader(for: sessionToken)
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
