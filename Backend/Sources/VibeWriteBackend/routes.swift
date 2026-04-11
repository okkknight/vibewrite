import Vapor
import VibeWriteShared

func routes(
    _ app: Application,
    deviceRegistry: InMemoryDeviceRegistry,
    writeService: WriteService
) throws {
    app.get("v3", "health") { _ in
        HealthResponse(status: "ok")
    }

    app.post("v3", "client", "bootstrap") { req async throws -> BootstrapResponse in
        let request = try req.content.decode(BootstrapRequest.self)
        let deviceToken = await deviceRegistry.deviceToken(for: request.installationId)

        return BootstrapResponse(
            deviceToken: deviceToken,
            deviceStatus: .active,
            quotaSummary: .default
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
}
