import Foundation
import VibeWriteShared

enum WritingAICompletionMetadataDecoder {
    static func decode(from rawContent: String) throws -> WritingAICompletionMetadata {
        let sanitized = sanitize(rawContent)
        guard let data = sanitized.data(using: .utf8) else {
            throw BackendAIError.providerError("AI completion metadata could not be converted to UTF-8")
        }

        do {
            return try JSONDecoder.vibeWriteAIResponseDecoder.decode(WritingAICompletionMetadata.self, from: data)
        } catch {
            throw BackendAIError.providerError("AI completion metadata was not valid JSON")
        }
    }

    private static func sanitize(_ rawContent: String) -> String {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let withoutFences = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
            return extractJSONObject(from: withoutFences.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return extractJSONObject(from: trimmed)
    }

    private static func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return text
        }

        return String(text[start...end])
    }
}

private extension JSONDecoder {
    static var vibeWriteAIResponseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

protocol BackendAIProviderClient: Sendable {
    func generateProseText(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> String

    func generateMetadata(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> WritingAICompletionMetadata
}

enum BackendAIProviderClientFactory {
    static func make(configuration: BackendAIConfiguration) -> any BackendAIProviderClient {
        switch configuration.mode {
        case .stub:
            return StubBackendAIProviderClient()
        case .real:
            return MiniMaxBackendAIProviderClient()
        }
    }
}

struct StubBackendAIProviderClient: BackendAIProviderClient {
    func generateProseText(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> String {
        switch request.action {
        case .startDraft:
            return """
            在你给出的方向里，最重要的不是把情绪讲满，而是先把它停在一个合适的位置。
            这篇文字先不急着给结论，而是从一个更具体的开头进入，让内容慢慢往前走。
            """

        case .continueWriting:
            return """

            接下来可以顺着这个主线，再补一段更自然的推进。
            """

        case .edit:
            return "这里不用说得太满，留白会更好。"
        }
    }

    func generateMetadata(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> WritingAICompletionMetadata {
        switch request.action {
        case .startDraft:
            return WritingAICompletionMetadata(
                localSummary: "已生成开头",
                globalSynopsis: "已生成总览",
                nextFocus: "继续推进第一段",
                suggestionChips: ["继续写", "编辑这段", "补一段"]
            )
        case .continueWriting:
            return WritingAICompletionMetadata(
                localSummary: "已续写一段",
                globalSynopsis: "已续写一段总览",
                nextFocus: "继续顺着当前主线往下写",
                suggestionChips: ["继续写", "编辑这段", "补一段"]
            )
        case .edit:
            return WritingAICompletionMetadata(
                localSummary: "已完成局部修改",
                globalSynopsis: "已完成局部修改总览",
                nextFocus: "检查选中文段是否还需要继续调整",
                suggestionChips: ["继续写", "编辑这段", "补一段"]
            )
        }
    }
}

final class MiniMaxBackendAIProviderClient: BackendAIProviderClient, @unchecked Sendable {
    private let session: URLSession
    private let responseBuilder = BackendWritingResponseBuilder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func generateProseText(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> String {
        let urlRequest = try makeAnthropicRequest(
            for: request,
            messages: messages,
            apiKey: apiKey,
            baseURL: configuration.baseURL,
            model: configuration.model,
            stream: false
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAIError.providerUnavailable("AI request did not return an HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(AnthropicErrorEnvelope.self, from: data) {
                throw BackendAIError.providerError(decodedError.errorMessage ?? "AI request failed with HTTP \(httpResponse.statusCode).")
            }

            throw BackendAIError.providerUnavailable("AI request failed with HTTP \(httpResponse.statusCode).")
        }

        let decodedResponse: AnthropicMessagesResponse
        do {
            decodedResponse = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        } catch {
            throw BackendAIError.providerError("AI prose response was not valid JSON.")
        }

        guard let proseText = decodedResponse.textContent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !proseText.isEmpty else {
            throw BackendAIError.providerError("AI prose response did not include text content.")
        }

        return proseText
    }

    func generateMetadata(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> WritingAICompletionMetadata {
        switch configuration.metadataRoute {
        case .current:
            return try await generateCurrentRouteMetadata(
                for: request,
                messages: messages,
                configuration: configuration,
                apiKey: apiKey
            )
        case .text01JsonSchema:
            return try await generateTextSchemaMetadata(
                for: request,
                messages: messages,
                configuration: configuration,
                apiKey: apiKey
            )
        }
    }

    private func generateCurrentRouteMetadata(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> WritingAICompletionMetadata {
        let metadataTool = AnthropicToolDefinition.metadata
        let urlRequest = try makeAnthropicRequest(
            for: request,
            messages: messages,
            apiKey: apiKey,
            baseURL: configuration.metadataRequestBaseURL,
            model: configuration.metadataModel,
            stream: false,
            tools: [metadataTool],
            toolChoice: .tool(name: metadataTool.name)
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAIError.providerUnavailable("AI request did not return an HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(AnthropicErrorEnvelope.self, from: data) {
                throw BackendAIError.providerError(decodedError.errorMessage ?? "AI request failed with HTTP \(httpResponse.statusCode).")
            }

            throw BackendAIError.providerUnavailable("AI request failed with HTTP \(httpResponse.statusCode).")
        }

        let decodedResponse: AnthropicMessagesResponse
        do {
            decodedResponse = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        } catch {
            throw BackendAIError.providerError("AI metadata response was not valid JSON.")
        }

        if let toolUse = decodedResponse.firstToolUse(named: metadataTool.name) {
            return toolUse.input
        }

        if let textContent = decodedResponse.textContent,
           let decoded = try? WritingAICompletionMetadataDecoder.decode(from: textContent) {
            return decoded
        }

        return responseBuilder.fallbackMetadata(for: request)
    }

    private func generateTextSchemaMetadata(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> WritingAICompletionMetadata {
        let requestBody = MiniMaxTextCompletionRequest(
            model: configuration.metadataModel,
            messages: messages.map {
                MiniMaxTextMessage(
                    role: $0.role.textRole,
                    name: $0.role.textName,
                    content: $0.content
                )
            },
            temperature: 0.1,
            maxCompletionTokens: maxTokens(for: request),
            stream: false,
            responseFormat: .jsonSchema()
        )

        var urlRequest = URLRequest(url: configuration.metadataRequestBaseURL.appendingPathComponent("v1/text/chatcompletion_v2"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder.vibeWriteAIRequestEncoder.encode(requestBody)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAIError.providerUnavailable("AI request did not return an HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw BackendAIError.providerUnavailable("AI request failed with HTTP \(httpResponse.statusCode).")
        }

        let decodedResponse: MiniMaxTextChatCompletionResponse
        do {
            decodedResponse = try JSONDecoder().decode(MiniMaxTextChatCompletionResponse.self, from: data)
        } catch {
            throw BackendAIError.providerError("AI metadata response was not valid JSON.")
        }

        if let baseResp = decodedResponse.baseResp, baseResp.statusCode != 0 {
            throw BackendAIError.providerError(baseResp.statusMessage ?? "AI request failed with HTTP \(httpResponse.statusCode).")
        }

        guard let content = decodedResponse.firstMessageContent else {
            return responseBuilder.fallbackMetadata(for: request)
        }

        do {
            return try WritingAICompletionMetadataDecoder.decode(from: content)
        } catch {
            return responseBuilder.fallbackMetadata(for: request)
        }
    }

    private func makeAnthropicRequest(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        apiKey: String,
        baseURL: URL,
        model: String,
        stream: Bool,
        tools: [AnthropicToolDefinition]? = nil,
        toolChoice: AnthropicToolChoice? = nil
    ) throws -> URLRequest {
        let systemPrompt = messages.first(where: { $0.role == .system })?.content ?? ""
        let userMessages = messages
            .filter { $0.role != .system }
            .map { message in
                AnthropicMessage(
                    role: message.role.anthropicRole,
                    content: [.text(message.content)]
                )
            }

        let body = AnthropicCompatibleRequest(
            model: model,
            system: systemPrompt,
            messages: userMessages,
            temperature: request.kind == .metadata ? 0.1 : 0.2,
            maxTokens: maxTokens(for: request),
            stream: stream,
            tools: tools,
            toolChoice: toolChoice
        )

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder.vibeWriteAIRequestEncoder.encode(body)
        return urlRequest
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

private struct AnthropicCompatibleRequest: Encodable {
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

private struct AnthropicToolDefinition: Encodable {
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

private struct AnthropicToolInputSchema: Encodable {
    let type = "object"
    let properties = Properties()
    let required = ["localSummary", "globalSynopsis", "nextFocus", "suggestionChips"]
    let additionalProperties = false

    struct Properties: Encodable {
        let localSummary = StringProperty(
            description: "A concise local summary of the completed prose. Keep it brief."
        )

        let globalSynopsis = StringProperty(
            description: "A stable overall synopsis of the story or article so far. Keep it short and do not repeat the local summary."
        )

        let nextFocus = StringProperty(
            description: "The next concrete step after the current prose."
        )

        let suggestionChips = SuggestionChipsProperty(
            description: "Exactly three concise suggestion chips for the next step. This is the most important output."
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

private struct AnthropicToolChoice: Encodable {
    let type = "tool"
    let name: String

    static func tool(name: String) -> AnthropicToolChoice {
        AnthropicToolChoice(name: name)
    }
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [AnthropicResponseContentBlock]

    var textContent: String? {
        let textBlocks = content.compactMap { block -> String? in
            guard case .text(let value) = block else { return nil }
            return value
        }

        let joined = textBlocks.joined()
        return joined.isEmpty ? nil : joined
    }

    func firstToolUse(named name: String) -> AnthropicToolUseBlock? {
        for block in content {
            if case .toolUse(let toolUse) = block, toolUse.name == name {
                return toolUse
            }
        }

        return nil
    }
}

private enum AnthropicResponseContentBlock: Decodable {
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

private struct AnthropicToolUseBlock: Decodable {
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

private struct MiniMaxTextCompletionRequest: Encodable {
    let model: String
    let messages: [MiniMaxTextMessage]
    let temperature: Double
    let maxCompletionTokens: Int
    let stream: Bool
    let responseFormat: MiniMaxTextResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
        case stream
        case responseFormat = "response_format"
    }
}

private struct MiniMaxTextMessage: Encodable {
    let role: String
    let name: String?
    let content: String
}

private struct MiniMaxTextResponseFormat: Encodable {
    let type = "json_schema"
    let jsonSchema = MiniMaxTextJSONSchema()

    static func jsonSchema() -> MiniMaxTextResponseFormat {
        MiniMaxTextResponseFormat()
    }

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

private struct MiniMaxTextJSONSchema: Encodable {
    let name = "writing_ai_metadata"
    let strict = true
    let schema = MiniMaxTextJSONSchemaDefinition()
}

private struct MiniMaxTextJSONSchemaDefinition: Encodable {
    let type = "object"
    let properties = Properties()
    let required = ["localSummary", "globalSynopsis", "nextFocus", "suggestionChips"]
    let additionalProperties = false

    struct Properties: Encodable {
        let localSummary = StringProperty(
            description: "A concise local summary of the completed prose. Keep it brief."
        )

        let globalSynopsis = StringProperty(
            description: "A stable overall synopsis of the story or article so far. Keep it short and do not repeat the local summary."
        )

        let nextFocus = StringProperty(
            description: "The next concrete step after the current prose."
        )

        let suggestionChips = SuggestionChipsProperty(
            description: "Exactly three concise suggestion chips for the next step. This is the most important output."
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

private struct MiniMaxTextChatCompletionResponse: Decodable {
    let choices: [Choice]
    let baseResp: BaseResp?

    var firstMessageContent: String? {
        choices.first?.message.content
    }

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }

    struct BaseResp: Decodable {
        let statusCode: Int
        let statusMessage: String?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case statusMessage = "status_msg"
        }
    }

    enum CodingKeys: String, CodingKey {
        case choices
        case baseResp = "base_resp"
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

    var textRole: String {
        switch self {
        case .system:
            return "system"
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        }
    }

    var textName: String? {
        switch self {
        case .system:
            return "MiniMax AI"
        case .user:
            return "用户"
        case .assistant:
            return "MiniMax AI"
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
