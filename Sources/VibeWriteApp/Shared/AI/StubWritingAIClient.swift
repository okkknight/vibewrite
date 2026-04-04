import Foundation

struct StubWritingAIClient: WritingAIClient {
    func streamResponse(for request: WritingAIRequest) -> AsyncThrowingStream<WritingAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                VibeWriteLog.ai.notice(
                    "Stub AI request started action=\(request.action.rawValue, privacy: .public) promptLength=\(request.userMessage?.count ?? 0, privacy: .public) selectionLength=\(request.selectionText?.count ?? 0, privacy: .public)"
                )
                let finalDocumentText = MockWritingEngine.streamedDocumentText(for: request)
                let finalResponse = WritingProjectResponseBuilder.response(
                    for: request,
                    documentText: finalDocumentText
                )
                let chunks = MockWritingEngine.streamChunks(for: request)

                for (index, chunk) in chunks.enumerated() {
                    continuation.yield(.textDelta(chunk))
                    if index < chunks.count - 1 {
                        try? await Task.sleep(nanoseconds: 85_000_000)
                    }
                }

                VibeWriteLog.ai.notice(
                    "Stub AI response completed action=\(request.action.rawValue, privacy: .public) documentPreview=\(finalDocumentText.vibewriteLogPreview(maxLength: 120), privacy: .public)"
                )
                continuation.yield(.completed(finalResponse))
                continuation.finish()
            }
        }
    }
}
