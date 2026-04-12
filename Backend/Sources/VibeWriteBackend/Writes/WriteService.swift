import Vapor
import VibeWriteShared

actor WriteService {
    private let deviceRegistry: InMemoryDeviceRegistry
    private let quotaLedger: InMemoryQuotaLedger
    private let requestLogStore: InMemoryRequestLogStore
    private let clock: any VibeWriteClock

    private static let logProvider = "stub-provider"
    private static let logModel = "stub-model"

    init(
        deviceRegistry: InMemoryDeviceRegistry,
        quotaLedger: InMemoryQuotaLedger,
        requestLogStore: InMemoryRequestLogStore,
        clock: any VibeWriteClock = SystemVibeWriteClock()
    ) {
        self.deviceRegistry = deviceRegistry
        self.quotaLedger = quotaLedger
        self.requestLogStore = requestLogStore
        self.clock = clock
    }

    func startDraft(_ envelope: WriteRequestEnvelope) async throws -> WritingAIResponse {
        try await handle(envelope, expectedAction: .startDraft, routeLabel: "/v3/writes/start")
    }

    func continueWriting(_ envelope: WriteRequestEnvelope) async throws -> WritingAIResponse {
        try await handle(envelope, expectedAction: .continueWriting, routeLabel: "/v3/writes/continue")
    }

    func edit(_ envelope: WriteRequestEnvelope) async throws -> WritingAIResponse {
        try await handle(
            envelope,
            expectedAction: .edit,
            routeLabel: "/v3/writes/edit",
            requiresSelectionRange: true
        )
    }

    private func handle(
        _ envelope: WriteRequestEnvelope,
        expectedAction: WritingAIAction,
        routeLabel: String,
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

        let response = Self.makeStubResponse(from: envelope, routeLabel: routeLabel)
        recordAcceptedLog(envelope: envelope, startedAt: startedAt)
        return response
    }

    private static func makeStubResponse(from envelope: WriteRequestEnvelope, routeLabel: String) -> WritingAIResponse {
        WritingAIResponse(
            assistantMessage: "[stub] \(routeLabel) accepted",
            documentText: envelope.project.documentText,
            localSummary: envelope.project.localSummary,
            globalSynopsis: envelope.project.globalSynopsis,
            intentSummary: envelope.project.context.intentSummary,
            styleConstraints: envelope.project.context.styleConstraints,
            currentGoal: envelope.project.context.currentGoal,
            recentDecisions: envelope.project.context.recentDecisions,
            workingMemory: envelope.project.context.workingMemory,
            nextFocus: envelope.project.context.nextFocus,
            suggestionChips: envelope.project.suggestionChips,
            mode: envelope.project.mode
        )
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
                provider: Self.logProvider,
                model: Self.logModel,
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
                provider: Self.logProvider,
                model: Self.logModel,
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
