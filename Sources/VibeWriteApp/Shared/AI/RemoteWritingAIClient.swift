import Foundation

final class RemoteWritingAIClient: WritingAIClient, @unchecked Sendable {
    private let configuration: WritingAIConfiguration
    private let session: URLSession
    private let promptBuilder = WritingAIPromptBuilder()

    init(configuration: WritingAIConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            throw WritingAIClientError.missingConfiguration
        }

        let messages = promptBuilder.messages(
            for: request,
            provider: configuration.provider,
            model: configuration.model
        )

        let body = OpenAICompatibleRequest(
            model: configuration.model,
            messages: messages,
            temperature: 0.2,
            topP: 0.95,
            stream: false
        )

        var urlRequest = URLRequest(url: configuration.baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder.vibeWriteAIRequestEncoder.encode(body)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WritingAIClientError.requestFailed("AI request did not return an HTTP response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder.vibeWriteAIErrorDecoder.decode(OpenAICompatibleErrorEnvelope.self, from: data) {
                throw WritingAIClientError.requestFailed(decodedError.error.message)
            }
            throw WritingAIClientError.requestFailed("AI request failed with HTTP \(httpResponse.statusCode).")
        }

        let payload = try JSONDecoder.vibeWriteAIResponseEnvelopeDecoder.decode(OpenAICompatibleResponse.self, from: data)
        guard let content = payload.choices.first?.message.content else {
            throw WritingAIClientError.invalidResponse("AI response did not include assistant content.")
        }

        return try WritingAIResponseDecoder.decode(from: content)
    }
}

private struct OpenAICompatibleRequest: Codable {
    let model: String
    let messages: [WritingAIChatMessage]
    let temperature: Double
    let topP: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case topP = "top_p"
        case stream
    }
}

private struct OpenAICompatibleResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct OpenAICompatibleErrorEnvelope: Decodable {
    let error: ErrorPayload

    struct ErrorPayload: Decodable {
        let message: String
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
    static var vibeWriteAIResponseEnvelopeDecoder: JSONDecoder {
        JSONDecoder()
    }

    static var vibeWriteAIErrorDecoder: JSONDecoder {
        JSONDecoder()
    }
}
