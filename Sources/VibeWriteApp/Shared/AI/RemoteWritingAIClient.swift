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
            temperature: 0.2,
            maxTokens: maxTokens(for: request.action),
            stream: true
        )
        let shouldCaptureDebugLogs = request.action == .startDraft
        let requestBodyData = try JSONEncoder.vibeWriteAIRequestEncoder.encode(body)
        let requestBodyText = String(data: requestBodyData, encoding: .utf8) ?? ""

        if shouldCaptureDebugLogs {
            VibeWriteLog.ai.info("startDraft request system=\(systemPrompt, privacy: .public)")
            if let firstUserMessage = userMessages.first?.content.first {
                switch firstUserMessage {
                case .text(let userPrompt):
                    VibeWriteLog.ai.info("startDraft request user=\(userPrompt, privacy: .public)")
                }
            }
            VibeWriteLog.ai.info("startDraft request payload=\(requestBodyText, privacy: .public)")
        }

        var urlRequest = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = requestBodyData

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

        var pendingDataLines: [String] = []
        var streamedCompletion = WritingAICompletionStreamBuffer()

        for try await line in bytes.lines {
            if line.isEmpty {
                try flushStreamEvent(
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
                    try flushStreamEvent(
                        dataLines: &pendingDataLines,
                        completionBuffer: &streamedCompletion,
                        continuation: continuation
                    )
                }
                continue
            }
        }

        try flushStreamEvent(
            dataLines: &pendingDataLines,
            completionBuffer: &streamedCompletion,
            continuation: continuation
        )

        streamedCompletion.finish()
        let finalBodyText = streamedCompletion.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalBodyText.isEmpty else {
            throw WritingAIClientError.invalidResponse("AI stream did not produce any正文。")
        }

        let finalDocumentText = MockWritingEngine.finalDocumentText(for: request, streamedText: finalBodyText)

        let completionMetadata: WritingAICompletionMetadata?
        do {
            completionMetadata = try WritingAICompletionMetadataDecoder.decode(from: streamedCompletion.metadataText)
        } catch {
            completionMetadata = nil
        }

        if shouldCaptureDebugLogs {
            let rawResponseText = streamedCompletion.rawText
            let metadataText = streamedCompletion.metadataText
            let parseStatus = startDraftMetadataParseStatus(
                metadataStarted: streamedCompletion.metadataStarted,
                metadata: completionMetadata
            )

            VibeWriteLog.ai.info("startDraft raw response=\(rawResponseText, privacy: .public)")
            VibeWriteLog.ai.info("startDraft metadata raw=\(metadataText, privacy: .public)")
            VibeWriteLog.ai.info(
                "startDraft metadata parse=\(parseStatus.rawValue, privacy: .public) summary=\(completionMetadata?.summary ?? "", privacy: .public) nextFocus=\(completionMetadata?.nextFocus ?? "", privacy: .public) suggestionChipsCount=\(completionMetadata?.suggestionChips.count ?? 0, privacy: .public)"
            )
        }

        let finalResponse = WritingProjectResponseBuilder.response(
            for: request,
            documentText: finalDocumentText,
            metadata: completionMetadata
        )
        continuation.yield(.completed(finalResponse))
        continuation.finish()
    }

    private func flushStreamEvent(
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

    private func maxTokens(for action: WritingAIAction) -> Int {
        switch action {
        case .startDraft:
            return 2048
        case .continueWriting:
            return 1536
        case .edit:
            return 1024
        }
    }
}

private struct WritingAICompletionStreamBuffer {
    private static let metadataMarker = "[[VIBEWRITE_METADATA]]"

    private(set) var rawText: String = ""
    private(set) var bodyText: String = ""
    private(set) var metadataText: String = ""
    private(set) var metadataStarted = false
    private var pendingText: String = ""

    mutating func append(_ chunk: String) -> [String] {
        guard !chunk.isEmpty else {
            return []
        }

        rawText += chunk
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

private enum StartDraftMetadataParseStatus: String {
    case noMarker = "no_marker"
    case markerPresentJSONFailed = "marker_present_json_failed"
    case jsonSuccessSuggestionChipsEmpty = "json_success_suggestionChips_empty"
    case success = "success"
}

private func startDraftMetadataParseStatus(
    metadataStarted: Bool,
    metadata: WritingAICompletionMetadata?
) -> StartDraftMetadataParseStatus {
    guard metadataStarted else {
        return .noMarker
    }

    guard let metadata else {
        return .markerPresentJSONFailed
    }

    return metadata.suggestionChips.isEmpty ? .jsonSuccessSuggestionChipsEmpty : .success
}

private struct AnthropicCompatibleRequest: Codable {
    let model: String
    let system: String
    let messages: [AnthropicMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
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

private struct AnthropicMessage: Codable {
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
