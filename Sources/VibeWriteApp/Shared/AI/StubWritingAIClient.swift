import Foundation

struct StubWritingAIClient: WritingAIClient {
    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        WritingProjectResponseBuilder.response(for: request)
    }
}
