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

    func execute(for envelope: WriteRequestEnvelope) async throws -> WritingAIResponse {
        switch envelope.kind {
        case .prose:
            return try await executeProse(for: envelope)

        case .metadata:
            let request = WritingAIRequest(
                action: envelope.action,
                project: envelope.project,
                userMessage: envelope.userMessage,
                selectionText: envelope.selectionText,
                selectionRange: envelope.selectionRange,
                kind: envelope.kind
            )
            let systemPromptSnapshot = try await systemPromptStore.systemPromptCurrentSnapshot()
            let apiKey = try await resolvedProviderApiKey()
            return try await executeMetadata(
                for: request,
                systemPromptSnapshot: systemPromptSnapshot,
                apiKey: apiKey
            )
        }
    }

    func streamProse(for envelope: WriteRequestEnvelope) async throws -> AsyncThrowingStream<WritingAIStreamEvent, Error> {
        let request = WritingAIRequest(
            action: envelope.action,
            project: envelope.project,
            userMessage: envelope.userMessage,
            selectionText: envelope.selectionText,
            selectionRange: envelope.selectionRange,
            kind: envelope.kind
        )
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

                    let documentText = try responseBuilder.appliedDocumentText(
                        for: request,
                        proseText: proseText
                    )

                    let response = responseBuilder.response(
                        for: request,
                        documentText: documentText,
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
        for envelope: WriteRequestEnvelope
    ) async throws -> WritingAIResponse {
        let request = WritingAIRequest(
            action: envelope.action,
            project: envelope.project,
            userMessage: envelope.userMessage,
            selectionText: envelope.selectionText,
            selectionRange: envelope.selectionRange,
            kind: envelope.kind
        )
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

        let documentText: String
        do {
            documentText = try responseBuilder.appliedDocumentText(
                for: request,
                proseText: proseText
            )
        } catch let error as BackendAIError {
            throw error
        } catch {
            throw BackendAIError.backendError(error.localizedDescription)
        }

        return responseBuilder.response(
            for: request,
            documentText: documentText,
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
    ) async throws -> WritingAIResponse {
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
            documentText: request.project.documentText,
            metadata: metadata,
            assistantMessage: responseBuilder.assistantLine(for: request.action)
        )
    }
}
