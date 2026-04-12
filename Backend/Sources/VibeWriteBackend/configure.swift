import Vapor

func configure(
    _ app: Application,
    quotaLedger: InMemoryQuotaLedger? = nil,
    requestLogStore: InMemoryRequestLogStore = InMemoryRequestLogStore(),
    clock: any VibeWriteClock = SystemVibeWriteClock(),
    providerApiKey: String? = nil,
    adminUsername: String? = nil,
    adminPassword: String? = nil
) throws {
    let deviceRegistry = InMemoryDeviceRegistry()
    let resolvedQuotaLedger = quotaLedger ?? InMemoryQuotaLedger(clock: clock)
    let backendAIConfiguration = BackendAIConfiguration.current(isTesting: app.environment == .testing)
    let resolvedAdminSecrets = try resolveAdminSecrets(
        app: app,
        providerApiKey: providerApiKey,
        adminUsername: adminUsername,
        adminPassword: adminPassword
    )
    let adminSecretStore = AdminSecretStore(
        providerApiKey: resolvedAdminSecrets.providerApiKey,
        adminUsername: resolvedAdminSecrets.adminUsername,
        adminPassword: resolvedAdminSecrets.adminPassword,
        clock: clock
    )
    let adminSystemPromptStore = AdminSystemPromptStore(
        snapshot: AdminSystemPromptSeed.makeSnapshot(clock: clock),
        clock: clock
    )
    let adminSessionStore = AdminSessionStore()
    let providerClient = BackendAIProviderClientFactory.make(configuration: backendAIConfiguration)
    let aiExecutor = BackendAIExecutor(
        configuration: backendAIConfiguration,
        providerClient: providerClient,
        secretStore: adminSecretStore,
        systemPromptStore: adminSystemPromptStore
    )
    let writeService = WriteService(
        deviceRegistry: deviceRegistry,
        quotaLedger: resolvedQuotaLedger,
        requestLogStore: requestLogStore,
        aiConfiguration: backendAIConfiguration,
        aiExecutor: aiExecutor,
        clock: clock
    )
    try routes(
        app,
        deviceRegistry: deviceRegistry,
        writeService: writeService,
        requestLogStore: requestLogStore,
        secretStore: adminSecretStore,
        systemPromptStore: adminSystemPromptStore,
        adminSessionStore: adminSessionStore
    )
}

private func resolveAdminSecrets(
    app: Application,
    providerApiKey: String?,
    adminUsername: String?,
    adminPassword: String?
) throws -> (providerApiKey: String?, adminUsername: String, adminPassword: String) {
    let resolvedProviderApiKey = providerApiKey ?? Environment.get("MINIMAX_API_KEY")
    let resolvedUsername = adminUsername
        ?? Environment.get("ADMIN_USERNAME")
        ?? (app.environment == .testing ? "admin" : nil)
    let resolvedPassword = adminPassword
        ?? Environment.get("ADMIN_PASSWORD")
        ?? (app.environment == .testing ? "password" : nil)

    guard let resolvedUsername, let resolvedPassword else {
        throw Abort(.internalServerError, reason: "Missing ADMIN_USERNAME or ADMIN_PASSWORD.")
    }

    return (resolvedProviderApiKey, resolvedUsername, resolvedPassword)
}
