import Foundation

final class RemoteWritingAIClient: WritingAIClient, @unchecked Sendable {
    private let configuration: WritingAIConfiguration
    private let session: URLSession
    private let promptBuilder = WritingAIPromptBuilder()

    init(configuration: WritingAIConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func streamResponse(for request: WritingAIRequest) -> AsyncThrowingStream<WritingAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await streamRequest(for: request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamRequest(
        for request: WritingAIRequest,
        continuation: AsyncThrowingStream<WritingAIStreamEvent, Error>.Continuation
    ) async throws {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw WritingAIClientError.missingConfiguration
        }

        switch request.kind {
        case .prose:
            if request.action == .edit {
                try await streamLegacyEditRequest(
                    for: request,
                    apiKey: apiKey,
                    continuation: continuation
                )
                return
            }

            VibeWriteLog.ai.info(
                "Remote prose request start action=\(request.action.rawValue, privacy: .public) provider=\(self.configuration.provider, privacy: .public) model=\(self.configuration.model, privacy: .public) docCount=\(request.project.documentText.count, privacy: .public) selectionCount=\(request.selectionText?.count ?? 0, privacy: .public)"
            )

            let finalBodyText = try await collectProseText(
                for: request,
                apiKey: apiKey
            ) { chunk in
                continuation.yield(.textDelta(chunk))
            }

            let finalDocumentText = WritingProjectResponseBuilder.finalDocumentText(
                for: request,
                streamedText: finalBodyText
            )
            let finalResponse = WritingProjectResponseBuilder.response(
                for: request,
                documentText: finalDocumentText,
                metadata: nil
            )
            VibeWriteLog.ai.info(
                "Remote prose request finished action=\(request.action.rawValue, privacy: .public) bodyCount=\(finalBodyText.count, privacy: .public)"
            )
            continuation.yield(.completed(finalResponse))
            continuation.finish()

        case .metadata:
            VibeWriteLog.ai.info(
                "Remote metadata structured request start action=\(request.action.rawValue, privacy: .public) provider=\(self.configuration.provider, privacy: .public) model=\(self.configuration.model, privacy: .public) docCount=\(request.project.documentText.count, privacy: .public) summaryCount=\(request.project.summary.count, privacy: .public) suggestionCount=\(request.project.suggestionChips.count, privacy: .public)"
            )

            let metadata = try await requestStructuredMetadata(
                for: request,
                apiKey: apiKey
            )

            VibeWriteLog.ai.info(
                "Remote metadata structured request finished action=\(request.action.rawValue, privacy: .public) summaryCount=\(metadata.summary.count, privacy: .public) nextFocusCount=\(metadata.nextFocus.count, privacy: .public) suggestionCount=\(metadata.suggestionChips.count, privacy: .public)"
            )
            let finalResponse = WritingProjectResponseBuilder.response(
                for: request,
                documentText: request.project.documentText,
                metadata: metadata
            )
            continuation.yield(.completed(finalResponse))
            continuation.finish()
        }
    }

    private func requestStructuredMetadata(
        for request: WritingAIRequest,
        apiKey: String
    ) async throws -> WritingAICompletionMetadata {
        let metadataTool = AnthropicToolDefinition.metadata
        let urlRequest = try makeRequest(
            for: request,
            apiKey: apiKey,
            stream: false,
            tools: [metadataTool],
            toolChoice: .tool(name: metadataTool.name)
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WritingAIClientError.requestFailed("AI request did not return an HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder.vibeWriteAIErrorDecoder.decode(AnthropicErrorEnvelope.self, from: data) {
                throw mapError(statusCode: httpResponse.statusCode, message: decodedError.errorMessage)
            }

            if let mappedError = mapConfigurationError(statusCode: httpResponse.statusCode, message: nil) {
                throw mappedError
            }

            throw WritingAIClientError.requestFailed("AI request failed with HTTP \(httpResponse.statusCode).")
        }

        let decodedResponse: AnthropicMessagesResponse
        do {
            decodedResponse = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        } catch {
            let rawText = String(data: data, encoding: .utf8) ?? ""
            let rawCount = rawText.count
            VibeWriteLog.ai.error(
                "Remote metadata structured decode failed action=\(request.action.rawValue, privacy: .public) rawCount=\(rawCount, privacy: .public) rawPreview=\(rawText.vibewriteLogPreview(maxLength: 160), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw WritingAIClientError.invalidResponse("AI metadata response was not valid JSON.")
        }

        guard let toolUse = decodedResponse.firstToolUse(named: metadataTool.name) else {
            let rawText = String(data: data, encoding: .utf8) ?? ""
            let rawCount = rawText.count
            VibeWriteLog.ai.error(
                "Remote metadata structured tool use missing action=\(request.action.rawValue, privacy: .public) rawCount=\(rawCount, privacy: .public) rawPreview=\(rawText.vibewriteLogPreview(maxLength: 160), privacy: .public)"
            )
            throw WritingAIClientError.invalidResponse("AI metadata response did not include the expected tool call.")
        }

        VibeWriteLog.ai.info(
            "Remote metadata structured tool use decoded action=\(request.action.rawValue, privacy: .public) toolName=\(toolUse.name, privacy: .public) summaryCount=\(toolUse.input.summary.count, privacy: .public) nextFocusCount=\(toolUse.input.nextFocus.count, privacy: .public) suggestionCount=\(toolUse.input.suggestionChips.count, privacy: .public)"
        )

        return toolUse.input
    }

    private func streamLegacyEditRequest(
        for request: WritingAIRequest,
        apiKey: String,
        continuation: AsyncThrowingStream<WritingAIStreamEvent, Error>.Continuation
    ) async throws {
        VibeWriteLog.ai.info(
            "Remote edit request start action=\(request.action.rawValue, privacy: .public) provider=\(self.configuration.provider, privacy: .public) model=\(self.configuration.model, privacy: .public)"
        )

        let bytes = try await openStream(for: request, apiKey: apiKey, stream: true)
        var pendingDataLines: [String] = []
        var streamedCompletion = WritingAICompletionStreamBuffer()

        for try await line in bytes.lines {
            if line.isEmpty {
                try flushLegacyStreamEvent(
                    dataLines: &pendingDataLines,
                    completionBuffer: &streamedCompletion,
                    continuation: continuation
                )
                continue
            }

            if line.hasPrefix("data:") {
                var dataLine = String(line.dropFirst("data:".count))
                if dataLine.first == " " {
                    dataLine.removeFirst()
                }
                pendingDataLines.append(dataLine)
                continue
            }

            if line.hasPrefix("event:") {
                if !pendingDataLines.isEmpty {
                    try flushLegacyStreamEvent(
                        dataLines: &pendingDataLines,
                        completionBuffer: &streamedCompletion,
                        continuation: continuation
                    )
                }
                continue
            }
        }

        try flushLegacyStreamEvent(
            dataLines: &pendingDataLines,
            completionBuffer: &streamedCompletion,
            continuation: continuation
        )

        streamedCompletion.finish()
        let finalBodyText = streamedCompletion.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalBodyText.isEmpty else {
            throw WritingAIClientError.invalidResponse("AI stream did not produce any正文。")
        }

        let finalDocumentText = WritingProjectResponseBuilder.finalDocumentText(
            for: request,
            streamedText: finalBodyText
        )

        let completionMetadata: WritingAICompletionMetadata?
        do {
            completionMetadata = try WritingAICompletionMetadataDecoder.decode(from: streamedCompletion.metadataText)
            VibeWriteLog.ai.info(
                "Remote edit metadata parsed action=\(request.action.rawValue, privacy: .public) summaryCount=\(completionMetadata?.summary.count ?? 0, privacy: .public) nextFocusCount=\(completionMetadata?.nextFocus.count ?? 0, privacy: .public) suggestionCount=\(completionMetadata?.suggestionChips.count ?? 0, privacy: .public)"
            )
        } catch {
            VibeWriteLog.ai.error(
                "Remote edit metadata parse failed action=\(request.action.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            completionMetadata = nil
        }

        let finalResponse = WritingProjectResponseBuilder.response(
            for: request,
            documentText: finalDocumentText,
            metadata: completionMetadata
        )
        VibeWriteLog.ai.info(
            "Remote edit request finished action=\(request.action.rawValue, privacy: .public) bodyCount=\(finalBodyText.count, privacy: .public)"
        )
        continuation.yield(.completed(finalResponse))
        continuation.finish()
    }

    private func collectProseText(
        for request: WritingAIRequest,
        apiKey: String,
        yieldChunk: @escaping (String) -> Void
    ) async throws -> String {
        let bytes = try await openStream(for: request, apiKey: apiKey, stream: true)
        var pendingDataLines: [String] = []
        var collectedText = ""

        for try await line in bytes.lines {
            if line.isEmpty {
                try flushStreamEvent(
                    dataLines: &pendingDataLines,
                    collectedText: &collectedText,
                    yieldChunk: yieldChunk
                )
                continue
            }

            if line.hasPrefix("data:") {
                var dataLine = String(line.dropFirst("data:".count))
                if dataLine.first == " " {
                    dataLine.removeFirst()
                }
                pendingDataLines.append(dataLine)
                continue
            }

            if line.hasPrefix("event:") {
                if !pendingDataLines.isEmpty {
                    try flushStreamEvent(
                        dataLines: &pendingDataLines,
                        collectedText: &collectedText,
                        yieldChunk: yieldChunk
                    )
                }
                continue
            }
        }

        try flushStreamEvent(
            dataLines: &pendingDataLines,
            collectedText: &collectedText,
            yieldChunk: yieldChunk
        )

        let trimmed = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WritingAIClientError.invalidResponse("AI stream did not produce any正文。")
        }

        return trimmed
    }

    private func flushStreamEvent(
        dataLines: inout [String],
        collectedText: inout String,
        yieldChunk: (String) -> Void
    ) throws {
        let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        dataLines.removeAll(keepingCapacity: true)

        guard !payload.isEmpty else {
            return
        }

        if let streamedChunk = try decodeTextChunk(from: payload) {
            collectedText += streamedChunk
            yieldChunk(streamedChunk)
        }
    }

    private func flushLegacyStreamEvent(
        dataLines: inout [String],
        completionBuffer: inout WritingAICompletionStreamBuffer,
        continuation: AsyncThrowingStream<WritingAIStreamEvent, Error>.Continuation
    ) throws {
        let payload = dataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        dataLines.removeAll(keepingCapacity: true)

        guard !payload.isEmpty else {
            return
        }

        if let streamedChunk = try decodeTextChunk(from: payload) {
            for bodyDelta in completionBuffer.append(streamedChunk) {
                continuation.yield(.textDelta(bodyDelta))
            }
        }
    }

    private func decodeTextChunk(from payload: String) throws -> String? {
        guard let data = payload.data(using: .utf8) else {
            return nil
        }

        if let envelope = try? JSONDecoder.vibeWriteAIStreamDecoder.decode(AnthropicStreamEnvelope.self, from: data) {
            guard envelope.type == "content_block_delta" else {
                return nil
            }

            let chunk = envelope.delta?.text ?? ""
            return chunk.isEmpty ? nil : chunk
        }

        return nil
    }

    private func openStream(
        for request: WritingAIRequest,
        apiKey: String,
        stream: Bool
    ) async throws -> URLSession.AsyncBytes {
        let urlRequest = try makeRequest(
            for: request,
            apiKey: apiKey,
            stream: stream
        )

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WritingAIClientError.requestFailed("AI request did not return an HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let data = try await collectData(from: bytes)
            if let decodedError = try? JSONDecoder.vibeWriteAIErrorDecoder.decode(AnthropicErrorEnvelope.self, from: data) {
                throw mapError(statusCode: httpResponse.statusCode, message: decodedError.errorMessage)
            }
            if let mappedError = mapConfigurationError(statusCode: httpResponse.statusCode, message: nil) {
                throw mappedError
            }
            throw WritingAIClientError.requestFailed("AI request failed with HTTP \(httpResponse.statusCode).")
        }

        return bytes
    }

    private func makeRequest(
        for request: WritingAIRequest,
        apiKey: String,
        stream: Bool,
        tools: [AnthropicToolDefinition]? = nil,
        toolChoice: AnthropicToolChoice? = nil
    ) throws -> URLRequest {
        let promptMessages = promptBuilder.messages(
            for: request,
            provider: configuration.provider,
            model: configuration.model
        )

        let systemPrompt = promptMessages.first(where: { $0.role == .system })?.content ?? ""
        let userMessages = promptMessages
            .filter { $0.role != .system }
            .map { message in
                AnthropicMessage(
                    role: message.role.anthropicRole,
                    content: [.text(message.content)]
                )
            }

        let body = AnthropicCompatibleRequest(
            model: configuration.model,
            system: systemPrompt,
            messages: userMessages,
            temperature: request.kind == .metadata ? 0.1 : 0.2,
            maxTokens: maxTokens(for: request),
            stream: stream,
            tools: tools,
            toolChoice: toolChoice
        )

        var urlRequest = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder.vibeWriteAIRequestEncoder.encode(body)
        return urlRequest
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func mapError(statusCode: Int, message: String?) -> WritingAIClientError {
        if let mappedError = mapConfigurationError(statusCode: statusCode, message: message) {
            VibeWriteLog.ai.error(
                "Remote AI configuration error status=\(statusCode, privacy: .public) message=\(message ?? "", privacy: .public)"
            )
            return mappedError
        }

        VibeWriteLog.ai.error(
            "Remote AI request failed status=\(statusCode, privacy: .public) message=\(message ?? "", privacy: .public)"
        )
        return .requestFailed(message ?? "AI request failed with HTTP \(statusCode).")
    }

    private func mapConfigurationError(statusCode: Int, message: String?) -> WritingAIClientError? {
        let normalizedMessage = message?.lowercased() ?? ""
        if statusCode == 401 || statusCode == 403 || normalizedMessage.contains("invalid api key") || normalizedMessage.contains("2049") {
            return .invalidConfiguration("MiniMax API key 无效，请检查 Config/VibeWrite.local.xcconfig 后重试。")
        }

        return nil
    }

    private func maxTokens(for request: WritingAIRequest) -> Int {
        switch request.kind {
        case .prose:
            switch request.action {
            case .startDraft:
                return 2048
            case .continueWriting:
                return 1536
            case .edit:
                return 1024
            }
        case .metadata:
            return 512
        }
    }
}

private struct WritingAICompletionStreamBuffer {
    private static let metadataMarker = "[[VIBEWRITE_METADATA]]"

    private(set) var bodyText: String = ""
    private(set) var metadataText: String = ""
    private var pendingText: String = ""
    private var metadataStarted = false

    mutating func append(_ chunk: String) -> [String] {
        guard !chunk.isEmpty else {
            return []
        }

        pendingText += chunk

        if metadataStarted {
            metadataText += pendingText
            pendingText.removeAll(keepingCapacity: true)
            return []
        }

        if let markerRange = pendingText.range(of: Self.metadataMarker) {
            let bodyPart = String(pendingText[..<markerRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            metadataStarted = true
            metadataText += String(pendingText[markerRange.upperBound...])
            pendingText.removeAll(keepingCapacity: true)

            if bodyPart.isEmpty {
                return []
            }

            bodyText += bodyPart
            return [bodyPart]
        }

        let keepLength = Self.metadataMarker.count - 1
        guard pendingText.count > keepLength else {
            return []
        }

        let yieldLength = pendingText.count - keepLength
        let bodyPart = String(pendingText.prefix(yieldLength))
        bodyText += bodyPart
        pendingText.removeFirst(yieldLength)
        return bodyPart.isEmpty ? [] : [bodyPart]
    }

    mutating func finish() {
        if metadataStarted {
            metadataText += pendingText
        } else {
            bodyText += pendingText
        }

        pendingText.removeAll(keepingCapacity: true)
    }
}

struct AnthropicCompatibleRequest: Encodable {
    let model: String
    let system: String
    let messages: [AnthropicMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    let tools: [AnthropicToolDefinition]?
    let toolChoice: AnthropicToolChoice?

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case tools
        case toolChoice = "tool_choice"
    }
}

struct AnthropicToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: AnthropicToolInputSchema

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }

    static let metadata = AnthropicToolDefinition(
        name: "emit_metadata",
        description: "Emit the collaboration metadata for the completed prose as a single tool call.",
        inputSchema: AnthropicToolInputSchema()
    )
}

struct AnthropicToolInputSchema: Encodable {
    let type = "object"
    let properties = Properties()
    let required = ["summary", "nextFocus", "suggestionChips"]
    let additionalProperties = false

    init() {}

    struct Properties: Encodable {
        let summary = StringProperty(
            description: "A concise summary of the completed prose."
        )

        let nextFocus = StringProperty(
            description: "The next concrete step after the current prose."
        )

        let suggestionChips = SuggestionChipsProperty(
            description: "Exactly three concise suggestion chips for the next step."
        )
    }

    struct StringProperty: Encodable {
        let type = "string"
        let description: String
    }

    struct SuggestionChipsProperty: Encodable {
        let type = "array"
        let description: String
        let items = Item()
        let minItems = 3
        let maxItems = 3

        struct Item: Encodable {
            let type = "string"
        }
    }
}

struct AnthropicToolChoice: Encodable {
    let type = "tool"
    let name: String

    init(name: String) {
        self.name = name
    }

    static func tool(name: String) -> AnthropicToolChoice {
        AnthropicToolChoice(name: name)
    }
}

struct AnthropicMessagesResponse: Decodable {
    let content: [AnthropicResponseContentBlock]

    func firstToolUse(named name: String) -> AnthropicToolUseBlock? {
        for block in content {
            if case .toolUse(let toolUse) = block, toolUse.name == name {
                return toolUse
            }
        }

        return nil
    }
}

enum AnthropicResponseContentBlock: Decodable {
    case text(String)
    case toolUse(AnthropicToolUseBlock)
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "tool_use":
            self = .toolUse(try AnthropicToolUseBlock(from: decoder))
        default:
            self = .unknown
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
    }
}

struct AnthropicToolUseBlock: Decodable {
    let type: String
    let id: String?
    let name: String
    let input: WritingAICompletionMetadata

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case input
    }
}

private struct AnthropicStreamEnvelope: Decodable {
    let type: String
    let delta: Delta?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
}

private struct AnthropicErrorEnvelope: Decodable {
    let message: String?
    let error: ErrorPayload?

    var errorMessage: String? {
        error?.message ?? message
    }

    struct ErrorPayload: Decodable {
        let message: String?
    }
}

struct AnthropicMessage: Encodable {
    let role: Role
    let content: [ContentBlock]

    enum Role: String, Codable {
        case user
        case assistant
    }

    enum ContentBlock: Codable {
        case text(String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let value):
                try container.encode("text", forKey: .type)
                try container.encode(value, forKey: .text)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try container.decode(String.self, forKey: .text))
            default:
                self = .text("")
            }
        }

        enum CodingKeys: String, CodingKey {
            case type
            case text
        }
    }
}

private extension WritingAIChatMessage.Role {
    var anthropicRole: AnthropicMessage.Role {
        switch self {
        case .system:
            return .user
        case .user:
            return .user
        case .assistant:
            return .assistant
        }
    }
}

private extension JSONEncoder {
    static var vibeWriteAIRequestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONDecoder {
    static var vibeWriteAIStreamDecoder: JSONDecoder {
        JSONDecoder()
    }

    static var vibeWriteAIErrorDecoder: JSONDecoder {
        JSONDecoder()
    }
}
