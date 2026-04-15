import Foundation
import Logging
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
    private let logger = Logger(label: "VibeWriteBackend.AI")
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
        let request = WritingAIRequest(
            action: envelope.action,
            project: envelope.project,
            userMessage: envelope.userMessage,
            selectionText: envelope.selectionText,
            selectionRange: envelope.selectionRange,
            kind: envelope.kind
        )

        let systemPromptSnapshot = try await systemPromptStore.systemPromptCurrentSnapshot()
        let secretSnapshot = try await secretStore.secretCurrentSnapshot()
        let providerApiKey = secretSnapshot.providerApiKey

        if configuration.mode == .real && (providerApiKey?.isEmpty ?? true) {
            throw BackendAIError.providerUnavailable("Missing provider API key.")
        }

        let apiKey = providerApiKey ?? ""

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

        let finalDocumentText: String
        do {
            finalDocumentText = try responseBuilder.appliedDocumentText(
                for: request,
                proseText: proseText
            )
        } catch let error as BackendAIError {
            throw error
        } catch {
            throw BackendAIError.backendError(error.localizedDescription)
        }

        let assistantMessage = responseBuilder.assistantLine(for: request.action)
        let proseAppliedProject = responseBuilder.updatedProjectSnapshot(
            for: request,
            documentText: finalDocumentText,
            assistantMessage: assistantMessage
        )
        let metadataRequest = WritingAIRequest(
            action: request.action,
            project: proseAppliedProject,
            userMessage: request.userMessage,
            selectionText: request.selectionText,
            selectionRange: request.selectionRange,
            kind: .metadata
        )

        var metadata: WritingAICompletionMetadata
        do {
            let metadataMessages = try promptComposer.metadataMessages(
                for: metadataRequest,
                systemPromptSnapshot: systemPromptSnapshot,
                configuration: configuration
            )
            metadata = try await providerClient.generateMetadata(
                for: metadataRequest,
                messages: metadataMessages,
                configuration: configuration,
                apiKey: apiKey
            )
        } catch {
            logger.error(
                "Backend metadata generation failed action=\(request.action.rawValue) error=\(error.localizedDescription) usingFallbackMetadata=true"
            )
            metadata = WritingAICompletionMetadata(
                localSummary: request.project.localSummary,
                globalSynopsis: request.project.globalSynopsis,
                nextFocus: request.project.context.nextFocus,
                suggestionChips: request.project.suggestionChips
            )
        }

        return responseBuilder.response(
            for: request,
            documentText: finalDocumentText,
            metadata: metadata,
            assistantMessage: assistantMessage
        )
    }
}
