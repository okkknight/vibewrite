import Vapor
import VibeWriteShared

actor WriteService {
    private let deviceRegistry: InMemoryDeviceRegistry

    init(deviceRegistry: InMemoryDeviceRegistry) {
        self.deviceRegistry = deviceRegistry
    }

    func startDraft(_ envelope: WriteRequestEnvelope) async throws -> WritingAIResponse {
        try await handle(envelope, expectedAction: .startDraft, routeLabel: "/v3/writes/start")
    }

    func continueWriting(_ envelope: WriteRequestEnvelope) async throws -> WritingAIResponse {
        try await handle(envelope, expectedAction: .continueWriting, routeLabel: "/v3/writes/continue")
    }

    private func handle(
        _ envelope: WriteRequestEnvelope,
        expectedAction: WritingAIAction,
        routeLabel: String
    ) async throws -> WritingAIResponse {
        guard envelope.action == expectedAction else {
            throw Abort(.badRequest, reason: "Only \(expectedAction.rawValue) is supported in this task.")
        }

        guard await deviceRegistry.isValidDevice(
            installationId: envelope.installationId,
            deviceToken: envelope.deviceToken
        ) else {
            throw Abort(.unauthorized, reason: "Device token does not match bootstrap registration.")
        }

        return Self.makeStubResponse(from: envelope, routeLabel: routeLabel)
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
}
