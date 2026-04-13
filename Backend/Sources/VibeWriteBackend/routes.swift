import Vapor
import VibeWriteShared

func routes(
    _ app: Application,
    deviceRegistry: InMemoryDeviceRegistry,
    quotaLedger: InMemoryQuotaLedger,
    writeService: WriteService,
    requestLogStore: InMemoryRequestLogStore,
    secretStore: AdminSecretStore,
    systemPromptStore: AdminSystemPromptStore,
    adminSessionStore: AdminSessionStore,
    aiConfiguration: BackendAIConfiguration,
    clock: any VibeWriteClock
) throws {
    app.get("v3", "health") { _ in
        HealthResponse(status: "ok")
    }

    app.post("v3", "client", "bootstrap") { req async throws -> BootstrapResponse in
        let request = try req.content.decode(BootstrapRequest.self)
        let bootstrap = await deviceRegistry.bootstrap(installationId: request.installationId)
        let currentLimit = await quotaLedger.currentLimit()

        return BootstrapResponse(
            deviceToken: bootstrap.deviceToken,
            deviceStatus: bootstrap.deviceStatus,
            quotaSummary: QuotaSummary(
                dailyLimit: currentLimit.dailyLimit,
                weeklyLimit: currentLimit.weeklyLimit
            )
        )
    }

    app.post("v3", "writes", "start") { req async throws -> WritingAIResponse in
        let envelope = try req.content.decode(WriteRequestEnvelope.self)
        return try await writeService.startDraft(envelope)
    }

    app.post("v3", "writes", "continue") { req async throws -> WritingAIResponse in
        let envelope = try req.content.decode(WriteRequestEnvelope.self)
        return try await writeService.continueWriting(envelope)
    }

    app.post("v3", "writes", "edit") { req async throws -> WritingAIResponse in
        let envelope = try req.content.decode(WriteRequestEnvelope.self)
        return try await writeService.edit(envelope)
    }

    try registerAdminRoutes(
        app,
        deviceRegistry: deviceRegistry,
        quotaLedger: quotaLedger,
        requestLogStore: requestLogStore,
        secretStore: secretStore,
        systemPromptStore: systemPromptStore,
        adminSessionStore: adminSessionStore,
        aiConfiguration: aiConfiguration,
        clock: clock
    )
}
