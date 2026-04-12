import Vapor

func configure(
    _ app: Application,
    quotaLedger: InMemoryQuotaLedger? = nil,
    requestLogStore: InMemoryRequestLogStore = InMemoryRequestLogStore(),
    clock: any VibeWriteClock = SystemVibeWriteClock(),
    adminUsername: String? = nil,
    adminPassword: String? = nil
) throws {
    let deviceRegistry = InMemoryDeviceRegistry()
    let resolvedQuotaLedger = quotaLedger ?? InMemoryQuotaLedger(clock: clock)
    let resolvedAdminCredentials = try resolveAdminCredentials(
        app: app,
        adminUsername: adminUsername,
        adminPassword: adminPassword
    )
    let adminSessionStore = AdminSessionStore(
        username: resolvedAdminCredentials.username,
        password: resolvedAdminCredentials.password
    )
    let writeService = WriteService(
        deviceRegistry: deviceRegistry,
        quotaLedger: resolvedQuotaLedger,
        requestLogStore: requestLogStore,
        clock: clock
    )
    try routes(
        app,
        deviceRegistry: deviceRegistry,
        writeService: writeService,
        requestLogStore: requestLogStore,
        adminSessionStore: adminSessionStore
    )
}

private func resolveAdminCredentials(
    app: Application,
    adminUsername: String?,
    adminPassword: String?
) throws -> (username: String, password: String) {
    let resolvedUsername = adminUsername
        ?? Environment.get("ADMIN_USERNAME")
        ?? (app.environment == .testing ? "admin" : nil)
    let resolvedPassword = adminPassword
        ?? Environment.get("ADMIN_PASSWORD")
        ?? (app.environment == .testing ? "password" : nil)

    guard let resolvedUsername, let resolvedPassword else {
        throw Abort(.internalServerError, reason: "Missing ADMIN_USERNAME or ADMIN_PASSWORD.")
    }

    return (resolvedUsername, resolvedPassword)
}
