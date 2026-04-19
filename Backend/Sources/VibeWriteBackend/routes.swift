import Foundation
import Vapor
import VibeWriteShared

func routes(
    _ app: Application,
    deviceRegistry: any VibeWriteDeviceRegistryStore,
    quotaLedger: any VibeWriteQuotaLedgerStore,
    writeService: WriteService,
    requestLogStore: any VibeWriteRequestLogStore,
    secretStore: any VibeWriteAdminSecretStore,
    systemPromptStore: any VibeWriteAdminSystemPromptStore,
    adminSessionStore: any VibeWriteAdminSessionStore,
    aiConfiguration: BackendAIConfiguration,
    clock: any VibeWriteClock
) throws {
    app.get("v3", "health") { _ in
        HealthResponse(status: "ok")
    }

    app.post("v3", "client", "bootstrap") { req async throws -> BootstrapResponse in
        let request = try req.content.decode(BootstrapRequest.self)
        let bootstrap = try await deviceRegistry.bootstrap(installationId: request.installationId)
        let currentLimit = try await quotaLedger.currentLimit()

        return BootstrapResponse(
            deviceToken: bootstrap.deviceToken,
            deviceStatus: bootstrap.deviceStatus,
            quotaSummary: QuotaSummary(
                dailyLimit: currentLimit.dailyLimit,
                weeklyLimit: currentLimit.weeklyLimit
            )
        )
    }

    app.post("v3", "writes", "start") { req async throws -> Response in
        let envelope = try req.content.decode(WriteRequestEnvelope.self)
        return try await writeResponse(for: envelope, action: .startDraft, request: req, writeService: writeService)
    }

    app.post("v3", "writes", "continue") { req async throws -> Response in
        let envelope = try req.content.decode(WriteRequestEnvelope.self)
        return try await writeResponse(for: envelope, action: .continueWriting, request: req, writeService: writeService)
    }

    app.post("v3", "writes", "edit") { req async throws -> Response in
        let envelope = try req.content.decode(WriteRequestEnvelope.self)
        return try await writeResponse(for: envelope, action: .edit, request: req, writeService: writeService)
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

private func writeResponse(
    for envelope: WriteRequestEnvelope,
    action: WritingAIAction,
    request: Request,
    writeService: WriteService
) async throws -> Response {
    guard envelope.action == action else {
        throw Abort(.badRequest, reason: "Only \(action.rawValue) is supported in this task.")
    }

    if request.prefersStreamingWrites {
        let stream: AsyncThrowingStream<WritingAIStreamEvent, Error>
        switch action {
        case .startDraft:
            stream = try await writeService.startDraftStream(envelope)
        case .continueWriting:
            stream = try await writeService.continueWritingStream(envelope)
        case .edit:
            stream = try await writeService.editStream(envelope)
        }
        return try streamingWriteResponse(for: stream)
    }

    let response: WritingAIResponse
    switch action {
    case .startDraft:
        response = try await writeService.startDraft(envelope)
    case .continueWriting:
        response = try await writeService.continueWriting(envelope)
    case .edit:
        response = try await writeService.edit(envelope)
    }

    return try jsonResponse(response)
}

private func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponseStatus = .ok) throws -> Response {
    let data = try JSONEncoder.vibeWriteBackendResponseEncoder.encode(value)
    var headers = HTTPHeaders()
    headers.contentType = .json
    return Response(status: status, headers: headers, body: .init(data: data))
}

private func streamingWriteResponse(
    for stream: AsyncThrowingStream<WritingAIStreamEvent, Error>
) throws -> Response {
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/x-ndjson; charset=utf-8")
    headers.add(name: .cacheControl, value: "no-cache")
    headers.add(name: .connection, value: "keep-alive")

    return Response(
        status: .ok,
        headers: headers,
        body: .init(managedAsyncStream: { writer in
            for try await event in stream {
                let data = try JSONEncoder.vibeWriteBackendResponseEncoder.encode(event)
                var buffer = ByteBufferAllocator().buffer(capacity: data.count + 1)
                buffer.writeBytes(data)
                buffer.writeString("\n")
                try await writer.write(.buffer(buffer))
            }
        })
    )
}

private extension Request {
    var prefersStreamingWrites: Bool {
        guard let accept = headers.first(name: .accept)?.lowercased() else {
            return false
        }

        return accept.contains("application/x-ndjson") || accept.contains("text/event-stream")
    }
}

private extension JSONEncoder {
    static var vibeWriteBackendResponseEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
