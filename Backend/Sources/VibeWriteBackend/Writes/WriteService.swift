import Vapor
import VibeWriteShared

actor WriteService {
    private let deviceRegistry: any VibeWriteDeviceRegistryStore
    private let quotaLedger: any VibeWriteQuotaLedgerStore
    private let requestLogStore: any VibeWriteRequestLogStore
    private let aiConfiguration: BackendAIConfiguration
    private let aiExecutor: BackendAIExecutor
    private let clock: any VibeWriteClock

    init(
        deviceRegistry: any VibeWriteDeviceRegistryStore,
        quotaLedger: any VibeWriteQuotaLedgerStore,
        requestLogStore: any VibeWriteRequestLogStore,
        aiConfiguration: BackendAIConfiguration,
        aiExecutor: BackendAIExecutor,
        clock: any VibeWriteClock = SystemVibeWriteClock()
    ) {
        self.deviceRegistry = deviceRegistry
        self.quotaLedger = quotaLedger
        self.requestLogStore = requestLogStore
        self.aiConfiguration = aiConfiguration
        self.aiExecutor = aiExecutor
        self.clock = clock
    }

    func startDraft(_ envelope: WriteRequestEnvelope) async throws -> WritingGatewayResponse {
        try await handle(envelope, expectedAction: .startDraft)
    }

    func continueWriting(_ envelope: WriteRequestEnvelope) async throws -> WritingGatewayResponse {
        try await handle(envelope, expectedAction: .continueWriting)
    }

    func edit(_ envelope: WriteRequestEnvelope) async throws -> WritingGatewayResponse {
        try await handle(
            envelope,
            expectedAction: .edit,
            requiresSelectionRange: true
        )
    }

    func startDraftStream(_ envelope: WriteRequestEnvelope) async throws -> AsyncThrowingStream<WritingGatewayStreamEvent, Error> {
        try await handleStream(envelope, expectedAction: .startDraft)
    }

    func continueWritingStream(_ envelope: WriteRequestEnvelope) async throws -> AsyncThrowingStream<WritingGatewayStreamEvent, Error> {
        try await handleStream(envelope, expectedAction: .continueWriting)
    }

    func editStream(_ envelope: WriteRequestEnvelope) async throws -> AsyncThrowingStream<WritingGatewayStreamEvent, Error> {
        try await handleStream(
            envelope,
            expectedAction: .edit,
            requiresSelectionRange: true
        )
    }

    private func handle(
        _ envelope: WriteRequestEnvelope,
        expectedAction: WritingAIAction,
        requiresSelectionRange: Bool = false
    ) async throws -> WritingGatewayResponse {
        let startedAt = clock.now()

        guard envelope.action == expectedAction else {
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "invalid_request"
            )
            throw Abort(.badRequest, reason: "Only \(expectedAction.rawValue) is supported in this task.")
        }

        switch try await deviceRegistry.validateDevice(
            installationId: envelope.installationId,
            deviceToken: envelope.deviceToken
        ) {
        case .valid:
            break
        case .blocked:
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "device_blocked"
            )
            throw Abort(.forbidden, reason: "device_blocked")
        case .unauthorized:
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "unauthorized"
            )
            throw Abort(.unauthorized, reason: "Device token does not match bootstrap registration.")
        }

        if requiresSelectionRange {
            guard let editWindow = envelope.editWindow,
                  !editWindow.selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await recordRejectedLog(
                    envelope: envelope,
                    startedAt: startedAt,
                    errorCode: "invalid_request"
                )
                throw Abort(.badRequest, reason: "A valid editWindow.selectionText is required for edit requests.")
            }
        }

        try validateEnvelopeStructure(envelope)

        guard try await quotaLedger.evaluateAndConsumeIfAllowed(installationId: envelope.installationId) == .allowed else {
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "quota_exceeded"
            )
            throw Abort(.tooManyRequests, reason: "quota_exceeded")
        }

        do {
            let response = try await aiExecutor.execute(for: envelope)
            await recordAcceptedLog(envelope: envelope, startedAt: startedAt)
            return response
        } catch let error as BackendAIError {
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: error.requestLogCode
            )
            throw Abort(error.abortStatus, reason: error.errorDescription ?? "AI request failed.")
        } catch {
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "backend_error"
            )
            throw Abort(.internalServerError, reason: error.localizedDescription)
        }
    }

    private func handleStream(
        _ envelope: WriteRequestEnvelope,
        expectedAction: WritingAIAction,
        requiresSelectionRange: Bool = false
    ) async throws -> AsyncThrowingStream<WritingGatewayStreamEvent, Error> {
        let startedAt = clock.now()

        guard envelope.action == expectedAction else {
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "invalid_request"
            )
            throw Abort(.badRequest, reason: "Only \(expectedAction.rawValue) is supported in this task.")
        }

        switch try await deviceRegistry.validateDevice(
            installationId: envelope.installationId,
            deviceToken: envelope.deviceToken
        ) {
        case .valid:
            break
        case .blocked:
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "device_blocked"
            )
            throw Abort(.forbidden, reason: "device_blocked")
        case .unauthorized:
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "unauthorized"
            )
            throw Abort(.unauthorized, reason: "Device token does not match bootstrap registration.")
        }

        if requiresSelectionRange {
            guard let editWindow = envelope.editWindow,
                  !editWindow.selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await recordRejectedLog(
                    envelope: envelope,
                    startedAt: startedAt,
                    errorCode: "invalid_request"
                )
                throw Abort(.badRequest, reason: "A valid editWindow.selectionText is required for edit requests.")
            }
        }

        try validateEnvelopeStructure(envelope)

        guard try await quotaLedger.evaluateAndConsumeIfAllowed(installationId: envelope.installationId) == .allowed else {
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "quota_exceeded"
            )
            throw Abort(.tooManyRequests, reason: "quota_exceeded")
        }

        let stream: AsyncThrowingStream<WritingGatewayStreamEvent, Error>
        do {
            stream = try await aiExecutor.streamProse(for: envelope)
        } catch let error as BackendAIError {
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: error.requestLogCode
            )
            throw Abort(error.abortStatus, reason: error.errorDescription ?? "AI request failed.")
        } catch {
            await recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "backend_error"
            )
            throw Abort(.internalServerError, reason: error.localizedDescription)
        }

        return AsyncThrowingStream { continuation in
            Task {
                var sawCompleted = false
                do {
                    for try await event in stream {
                        if case .completed = event {
                            sawCompleted = true
                        }
                        continuation.yield(event)
                    }

                    guard sawCompleted else {
                        await recordRejectedLog(
                            envelope: envelope,
                            startedAt: startedAt,
                            errorCode: "backend_error"
                        )
                        continuation.finish(throwing: Abort(.internalServerError, reason: "AI stream did not complete."))
                        return
                    }

                    await recordAcceptedLog(envelope: envelope, startedAt: startedAt)
                    continuation.finish()
                } catch let error as AbortError {
                    await recordRejectedLog(
                        envelope: envelope,
                        startedAt: startedAt,
                        errorCode: error.status.reasonPhrase
                    )
                    continuation.finish(throwing: error)
                } catch {
                    await recordRejectedLog(
                        envelope: envelope,
                        startedAt: startedAt,
                        errorCode: "backend_error"
                    )
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func recordAcceptedLog(
        envelope: WriteRequestEnvelope,
        startedAt: Date
    ) async {
        let endedAt = clock.now()
        let durationMs = Self.durationMilliseconds(from: startedAt, to: endedAt)

        try? await requestLogStore.append(
            RequestLogEntry(
                requestId: envelope.requestId,
                installationId: envelope.installationId,
                action: envelope.action,
                status: RequestLogStatus.accepted,
                errorCode: nil,
                provider: aiConfiguration.provider,
                model: aiConfiguration.model,
                durationMs: durationMs,
                tokenIn: 0,
                tokenOut: 0,
                createdAt: endedAt
            )
        )
    }

    private func recordRejectedLog(
        envelope: WriteRequestEnvelope,
        startedAt: Date,
        errorCode: String
    ) async {
        let endedAt = clock.now()
        let durationMs = Self.durationMilliseconds(from: startedAt, to: endedAt)

        try? await requestLogStore.append(
            RequestLogEntry(
                requestId: envelope.requestId,
                installationId: envelope.installationId,
                action: envelope.action,
                status: RequestLogStatus.rejected,
                errorCode: errorCode,
                provider: aiConfiguration.provider,
                model: aiConfiguration.model,
                durationMs: durationMs,
                tokenIn: 0,
                tokenOut: 0,
                createdAt: endedAt
            )
        )
    }

    private static func durationMilliseconds(from start: Date, to end: Date) -> Int {
        let duration = end.timeIntervalSince(start) * 1000
        return max(0, Int(duration.rounded(.down)))
    }

    private func validateEnvelopeStructure(_ envelope: WriteRequestEnvelope) throws {
        switch envelope.action {
        case .startDraft:
            guard envelope.startProject != nil else {
                throw Abort(.badRequest, reason: "A valid startProject is required for start requests.")
            }

        case .continueWriting:
            guard envelope.sessionContext != nil,
                  envelope.continueWindow != nil else {
                throw Abort(.badRequest, reason: "A valid continueWindow is required for continue requests.")
            }

        case .edit:
            guard envelope.sessionContext != nil,
                  envelope.editWindow != nil else {
                throw Abort(.badRequest, reason: "A valid editWindow is required for edit requests.")
            }
        }
    }
}
