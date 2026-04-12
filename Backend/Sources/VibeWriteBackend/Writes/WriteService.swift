import Vapor
import VibeWriteShared

actor WriteService {
    private let deviceRegistry: InMemoryDeviceRegistry
    private let quotaLedger: InMemoryQuotaLedger
    private let requestLogStore: InMemoryRequestLogStore
    private let aiConfiguration: BackendAIConfiguration
    private let aiExecutor: BackendAIExecutor
    private let clock: any VibeWriteClock

    init(
        deviceRegistry: InMemoryDeviceRegistry,
        quotaLedger: InMemoryQuotaLedger,
        requestLogStore: InMemoryRequestLogStore,
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

    func startDraft(_ envelope: WriteRequestEnvelope) async throws -> WritingAIResponse {
        try await handle(envelope, expectedAction: .startDraft)
    }

    func continueWriting(_ envelope: WriteRequestEnvelope) async throws -> WritingAIResponse {
        try await handle(envelope, expectedAction: .continueWriting)
    }

    func edit(_ envelope: WriteRequestEnvelope) async throws -> WritingAIResponse {
        try await handle(
            envelope,
            expectedAction: .edit,
            requiresSelectionRange: true
        )
    }

    private func handle(
        _ envelope: WriteRequestEnvelope,
        expectedAction: WritingAIAction,
        requiresSelectionRange: Bool = false
    ) async throws -> WritingAIResponse {
        let startedAt = clock.now()

        guard envelope.action == expectedAction else {
            recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "invalid_request"
            )
            throw Abort(.badRequest, reason: "Only \(expectedAction.rawValue) is supported in this task.")
        }

        guard await deviceRegistry.isValidDevice(
            installationId: envelope.installationId,
            deviceToken: envelope.deviceToken
        ) else {
            recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "unauthorized"
            )
            throw Abort(.unauthorized, reason: "Device token does not match bootstrap registration.")
        }

        if requiresSelectionRange {
            guard let selectionRange = envelope.selectionRange,
                  selectionRange.range(in: envelope.project.documentText) != nil else {
                recordRejectedLog(
                    envelope: envelope,
                    startedAt: startedAt,
                    errorCode: "invalid_request"
                )
                throw Abort(.badRequest, reason: "A valid selectionRange is required for edit requests.")
            }
        }

        guard await quotaLedger.evaluateAndConsumeIfAllowed(installationId: envelope.installationId) == .allowed else {
            recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "quota_exceeded"
            )
            throw Abort(.tooManyRequests, reason: "quota_exceeded")
        }

        do {
            let response = try await aiExecutor.execute(for: envelope)
            recordAcceptedLog(envelope: envelope, startedAt: startedAt)
            return response
        } catch let error as BackendAIError {
            recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: error.requestLogCode
            )
            throw Abort(error.abortStatus, reason: error.errorDescription ?? "AI request failed.")
        } catch {
            recordRejectedLog(
                envelope: envelope,
                startedAt: startedAt,
                errorCode: "backend_error"
            )
            throw Abort(.internalServerError, reason: error.localizedDescription)
        }
    }

    private func recordAcceptedLog(
        envelope: WriteRequestEnvelope,
        startedAt: Date
    ) {
        let endedAt = clock.now()
        let durationMs = Self.durationMilliseconds(from: startedAt, to: endedAt)

        requestLogStore.append(
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
    ) {
        let endedAt = clock.now()
        let durationMs = Self.durationMilliseconds(from: startedAt, to: endedAt)

        requestLogStore.append(
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
}
