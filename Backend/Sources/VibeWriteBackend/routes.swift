import Vapor

func routes(_ app: Application, deviceRegistry: InMemoryDeviceRegistry) throws {
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
}
