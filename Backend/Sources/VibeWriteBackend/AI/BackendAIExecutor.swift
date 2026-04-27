import Foundation
import Vapor
import VibeWriteShared

enum BackendAIError: LocalizedError {
    case invalidRequest(String)
    case invalidConfiguration(String)
    case providerUnavailable(String)
    case providerError(String)
    case backendError(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message),
             .invalidConfiguration(let message),
             .providerUnavailable(let message),
             .providerError(let message),
             .backendError(let message):
            return message
        }
    }

    var requestLogCode: String {
        switch self {
        case .invalidRequest:
            return "invalid_request"
        case .providerUnavailable:
            return "provider_unavailable"
        case .providerError:
            return "provider_error"
        case .invalidConfiguration, .backendError:
            return "backend_error"
        }
    }

    var abortStatus: HTTPResponseStatus {
        switch self {
        case .invalidRequest:
            return .badRequest
        case .invalidConfiguration, .backendError:
            return .internalServerError
        case .providerUnavailable:
            return .serviceUnavailable
        case .providerError:
            return .badGateway
        }
    }
}

actor BackendAIExecutor {
    private let configuration: BackendAIConfiguration
    private let promptComposer: BackendPromptComposer
    private let providerClient: any BackendAIProviderClient
    private let secretStore: any VibeWriteAdminSecretStore
    private let systemPromptStore: any VibeWriteAdminSystemPromptStore
    private let responseBuilder = BackendWritingResponseBuilder()

    init(
        configuration: BackendAIConfiguration,
        promptComposer: BackendPromptComposer = BackendPromptComposer(),
        providerClient: any BackendAIProviderClient,
        secretStore: any VibeWriteAdminSecretStore,
        systemPromptStore: any VibeWriteAdminSystemPromptStore
    ) {
        self.configuration = configuration
        self.promptComposer = promptComposer
        self.providerClient = providerClient
        self.secretStore = secretStore
        self.systemPromptStore = systemPromptStore
    }

    func execute(for envelope: WriteRequestEnvelope) async throws -> WritingGatewayResponse {
        let request = try gatewayRequest(from: envelope)
        switch envelope.kind {
        case .prose:
            return try await executeProse(for: request)

        case .metadata:
            let systemPromptSnapshot = try await systemPromptStore.systemPromptCurrentSnapshot()
            let apiKey = try await resolvedProviderApiKey()
            return try await executeMetadata(
                for: request,
                systemPromptSnapshot: systemPromptSnapshot,
                apiKey: apiKey
            )
        }
    }

    func streamProse(for envelope: WriteRequestEnvelope) async throws -> AsyncThrowingStream<WritingGatewayStreamEvent, Error> {
        let request = try gatewayRequest(from: envelope)
        let systemPromptSnapshot = try await systemPromptStore.systemPromptCurrentSnapshot()
        let apiKey = try await resolvedProviderApiKey()

        let proseMessages: [WritingAIChatMessage]
        do {
            proseMessages = try promptComposer.proseMessages(
                for: request,
                systemPromptSnapshot: systemPromptSnapshot,
                configuration: configuration
            )
        } catch let error as BackendAIError {
            throw error
        } catch {
            throw BackendAIError.invalidConfiguration(error.localizedDescription)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let proseStream = try await providerClient.streamProseText(
                        for: request,
                        messages: proseMessages,
                        configuration: configuration,
                        apiKey: apiKey
                    )

                    var proseText = ""
                    for try await delta in proseStream {
                        proseText += delta
                        continuation.yield(.textDelta(delta))
                    }

                    let response = responseBuilder.response(
                        for: request,
                        proseText: proseText,
                        metadata: nil,
                        assistantMessage: responseBuilder.assistantLine(for: request.action)
                    )

                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch let error as BackendAIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: BackendAIError.providerError(error.localizedDescription))
                }
            }
        }
    }

    private func executeProse(
        for request: WritingAIRequest
    ) async throws -> WritingGatewayResponse {
        let systemPromptSnapshot = try await systemPromptStore.systemPromptCurrentSnapshot()
        let apiKey = try await resolvedProviderApiKey()

        let proseMessages: [WritingAIChatMessage]
        do {
            proseMessages = try promptComposer.proseMessages(
                for: request,
                systemPromptSnapshot: systemPromptSnapshot,
                configuration: configuration
            )
        } catch let error as BackendAIError {
            throw error
        } catch {
            throw BackendAIError.invalidConfiguration(error.localizedDescription)
        }

        let proseText: String
        do {
            proseText = try await providerClient.generateProseText(
                for: request,
                messages: proseMessages,
                configuration: configuration,
                apiKey: apiKey
            )
        } catch let error as BackendAIError {
            throw error
        } catch {
            throw BackendAIError.providerError(error.localizedDescription)
        }

        return responseBuilder.response(
            for: request,
            proseText: proseText,
            metadata: nil,
            assistantMessage: responseBuilder.assistantLine(for: request.action)
        )
    }

    private func resolvedProviderApiKey() async throws -> String {
        let secretSnapshot = try await secretStore.secretCurrentSnapshot()
        let providerApiKey = secretSnapshot.providerApiKey

        if configuration.mode == .real && (providerApiKey?.isEmpty ?? true) {
            throw BackendAIError.providerUnavailable("Missing provider API key.")
        }

        return providerApiKey ?? ""
    }

    private func executeMetadata(
        for request: WritingAIRequest,
        systemPromptSnapshot: AdminSystemPromptStore.Snapshot,
        apiKey: String
    ) async throws -> WritingGatewayResponse {
        let metadataMessages: [WritingAIChatMessage]
        do {
            metadataMessages = try promptComposer.metadataMessages(
                for: request,
                systemPromptSnapshot: systemPromptSnapshot,
                configuration: configuration
            )
        } catch let error as BackendAIError {
            throw error
        } catch {
            throw BackendAIError.invalidConfiguration(error.localizedDescription)
        }

        let metadata: WritingAICompletionMetadata
        do {
            metadata = try await providerClient.generateMetadata(
                for: request,
                messages: metadataMessages,
                configuration: configuration,
                apiKey: apiKey
            )
        } catch let error as BackendAIError {
            throw error
        } catch {
            throw BackendAIError.providerError(error.localizedDescription)
        }

        return responseBuilder.response(
            for: request,
            proseText: nil,
            metadata: metadata,
            assistantMessage: responseBuilder.assistantLine(for: request.action)
        )
    }

    private func gatewayRequest(from envelope: WriteRequestEnvelope) throws -> WritingAIRequest {
        switch envelope.action {
        case .startDraft:
            guard let project = envelope.startProject else {
                throw BackendAIError.invalidRequest("A valid startProject is required for start requests.")
            }
            return WritingAIRequest(
                action: envelope.action,
                project: project,
                userMessage: envelope.userMessage,
                selectionText: nil,
                selectionRange: nil,
                kind: envelope.kind
            )

        case .continueWriting:
            guard let sessionContext = envelope.sessionContext,
                  let continueWindow = envelope.continueWindow else {
                throw BackendAIError.invalidRequest("A valid continueWindow is required for continue requests.")
            }
            return WritingAIRequest(
                action: envelope.action,
                project: gatewayProjectSnapshot(
                    sessionContext: sessionContext,
                    documentText: continueWindow.tailText
                ),
                userMessage: envelope.userMessage,
                selectionText: nil,
                selectionRange: nil,
                kind: envelope.kind
            )

        case .edit:
            guard let sessionContext = envelope.sessionContext,
                  let editWindow = envelope.editWindow else {
                throw BackendAIError.invalidRequest("A valid editWindow is required for edit requests.")
            }
            return WritingAIRequest(
                action: envelope.action,
                project: gatewayProjectSnapshot(
                    sessionContext: sessionContext,
                    documentText: editWindow.windowText
                ),
                userMessage: envelope.userMessage,
                selectionText: editWindow.selectionText,
                selectionRange: editWindow.localSelectionRange,
                kind: envelope.kind
            )
        }
    }

    private func gatewayProjectSnapshot(
        sessionContext: WritingGatewaySessionContext,
        documentText: String
    ) -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000BEEF") ?? UUID(),
            automationKey: "backend.gateway.window",
            title: sessionContext.title,
            prompt: sessionContext.prompt,
            mode: sessionContext.mode,
            localSummary: sessionContext.localSummary,
            globalSynopsis: sessionContext.globalSynopsis,
            context: sessionContext.context,
            conversation: [],
            documentText: documentText,
            suggestionChips: sessionContext.suggestionChips,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
