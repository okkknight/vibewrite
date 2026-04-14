import FluentPostgresDriver
import Vapor

@discardableResult
func configure(
    _ app: Application,
    quotaLedger: (any VibeWriteQuotaLedgerStore)? = nil,
    requestLogStore: (any VibeWriteRequestLogStore)? = nil,
    clock: any VibeWriteClock = SystemVibeWriteClock(),
    providerApiKey: String? = nil,
    adminUsername: String? = nil,
    adminPassword: String? = nil
) throws -> (any BackendPersistenceBootstrapper)? {
    let backendAIConfiguration = BackendAIConfiguration.current(isTesting: app.environment == .testing)
    let shouldUseMemoryStores = quotaLedger != nil || requestLogStore != nil || (app.environment == .testing && Environment.get("DATABASE_URL") == nil)
    let resolvedAdminSecrets = try resolveAdminSecrets(
        app: app,
        providerApiKey: providerApiKey,
        adminUsername: adminUsername,
        adminPassword: adminPassword
    )

    if shouldUseMemoryStores {
        let deviceRegistry = InMemoryDeviceRegistry(clock: clock)
        let resolvedQuotaLedger = quotaLedger ?? InMemoryQuotaLedger(clock: clock)
        let resolvedRequestLogStore = requestLogStore ?? InMemoryRequestLogStore()
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
            requestLogStore: resolvedRequestLogStore,
            aiConfiguration: backendAIConfiguration,
            aiExecutor: aiExecutor,
            clock: clock
        )
        try routes(
            app,
            deviceRegistry: deviceRegistry,
            quotaLedger: resolvedQuotaLedger,
            writeService: writeService,
            requestLogStore: resolvedRequestLogStore,
            secretStore: adminSecretStore,
            systemPromptStore: adminSystemPromptStore,
            adminSessionStore: adminSessionStore,
            aiConfiguration: backendAIConfiguration,
            clock: clock
        )
        return nil
    }

    guard let databaseURL = Environment.get("DATABASE_URL") else {
        throw Abort(.internalServerError, reason: "Missing DATABASE_URL.")
    }

    guard let postgresConfiguration = PostgresConfiguration(url: databaseURL) else {
        throw Abort(.internalServerError, reason: "DATABASE_URL is not a valid PostgreSQL URL.")
    }
    app.databases.use(.postgres(configuration: postgresConfiguration), as: .psql)
    BackendDatabaseMigrationPlan.register(app)

    let secretCipher = try BackendSecretCipher.resolveFromEnvironment()
    let adminSecretSeed = AdminSecretStore.Snapshot(
        providerApiKey: resolvedAdminSecrets.providerApiKey,
        adminUsername: resolvedAdminSecrets.adminUsername,
        adminPassword: resolvedAdminSecrets.adminPassword,
        updatedAt: clock.now()
    )
    let adminSystemPromptSeed = AdminSystemPromptSeed.makeSnapshot(clock: clock)
    let persistence = PostgresBackendPersistence(
        app: app,
        clock: clock,
        secretCipher: secretCipher,
        adminSecretSeed: adminSecretSeed,
        systemPromptSeed: adminSystemPromptSeed
    )
    let providerClient = BackendAIProviderClientFactory.make(configuration: backendAIConfiguration)
    let aiExecutor = BackendAIExecutor(
        configuration: backendAIConfiguration,
        providerClient: providerClient,
        secretStore: persistence,
        systemPromptStore: persistence
    )
    let writeService = WriteService(
        deviceRegistry: persistence,
        quotaLedger: persistence,
        requestLogStore: persistence,
        aiConfiguration: backendAIConfiguration,
        aiExecutor: aiExecutor,
        clock: clock
    )
    try routes(
        app,
        deviceRegistry: persistence,
        quotaLedger: persistence,
        writeService: writeService,
        requestLogStore: persistence,
        secretStore: persistence,
        systemPromptStore: persistence,
        adminSessionStore: persistence,
        aiConfiguration: backendAIConfiguration,
        clock: clock
    )
    return persistence
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
