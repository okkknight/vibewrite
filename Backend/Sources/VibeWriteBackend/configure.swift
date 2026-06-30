import FluentPostgresDriver
import FluentSQLiteDriver
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
    let environment = ProcessInfo.processInfo.environment
    let backendAIConfiguration = BackendAIConfiguration.current(isTesting: app.environment == .testing)
    let shouldUseMemoryStores = quotaLedger != nil
        || requestLogStore != nil
        || (app.environment == .testing && !BackendPersistenceConfiguration.hasExplicitPersistentConfiguration(environment: environment))
    let resolvedAdminSecrets = try resolveAdminSecrets(
        app: app,
        provider: backendAIConfiguration.provider,
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

    let persistenceConfiguration = try BackendPersistenceConfiguration.current(environment: environment)
    try configureDatabase(app, persistenceConfiguration: persistenceConfiguration)
    BackendDatabaseMigrationPlan.register(app)

    let secretCipher = try BackendSecretCipher.resolveFromEnvironment()
    let adminSecretSeed = AdminSecretStore.Snapshot(
        providerApiKey: resolvedAdminSecrets.providerApiKey,
        adminUsername: resolvedAdminSecrets.adminUsername,
        adminPassword: resolvedAdminSecrets.adminPassword,
        updatedAt: clock.now()
    )
    let adminSystemPromptSeed = AdminSystemPromptSeed.makeSnapshot(clock: clock)
    let persistence = DatabaseBackendPersistence(
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

private func configureDatabase(
    _ app: Application,
    persistenceConfiguration: BackendPersistenceConfiguration
) throws {
    switch persistenceConfiguration.storage {
    case .postgres(let databaseURL):
        guard let postgresConfiguration = PostgresConfiguration(url: databaseURL) else {
            throw Abort(.internalServerError, reason: "DATABASE_URL is not a valid PostgreSQL URL.")
        }
        app.databases.use(.postgres(configuration: postgresConfiguration), as: .psql)

    case .sqlite(let filePath):
        let databaseURL = URL(fileURLWithPath: filePath)
        let parentDirectoryURL = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDirectoryURL,
            withIntermediateDirectories: true
        )
        app.databases.use(.sqlite(.file(filePath)), as: .sqlite)
    }
}

private func resolveAdminSecrets(
    app: Application,
    provider: String,
    providerApiKey: String?,
    adminUsername: String?,
    adminPassword: String?
) throws -> (providerApiKey: String?, adminUsername: String, adminPassword: String) {
    let resolvedProviderApiKey: String?
    if provider.lowercased() == "codex" {
        resolvedProviderApiKey = providerApiKey
    } else {
        resolvedProviderApiKey = providerApiKey ?? Environment.get("MINIMAX_API_KEY")
    }

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
