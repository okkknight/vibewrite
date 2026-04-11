import Vapor
import VibeWriteShared

actor WriteService {
    private let deviceRegistry: InMemoryDeviceRegistry

    init(deviceRegistry: InMemoryDeviceRegistry) {
        self.deviceRegistry = deviceRegistry
    }

    func startDraft(_ envelope: WriteStartEnvelope) async throws -> WritingAIResponse {
        guard envelope.action == .startDraft else {
            throw Abort(.badRequest, reason: "Only startDraft is supported in this task.")
        }

        guard await deviceRegistry.isValidDevice(
            installationId: envelope.installationId,
            deviceToken: envelope.deviceToken
        ) else {
            throw Abort(.unauthorized, reason: "Device token does not match bootstrap registration.")
        }

        return Self.makeStubResponse(from: envelope)
    }

    private static func makeStubResponse(from envelope: WriteStartEnvelope) -> WritingAIResponse {
        WritingAIResponse(
            assistantMessage: "[stub] /v3/writes/start accepted",
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
