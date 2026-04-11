import Foundation
import VibeWriteShared

struct StubWritingAIClient: WritingAIClient {
    func streamResponse(for request: WritingAIRequest) -> AsyncThrowingStream<WritingAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                switch request.kind {
                case .prose:
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
                    continuation.yield(.completed(finalResponse))
                    continuation.finish()

                case .metadata:
                    let metadata = MockWritingEngine.completionMetadata(for: request)
                    let finalResponse = WritingProjectResponseBuilder.response(
                        for: request,
                        documentText: request.project.documentText,
                        metadata: metadata
                    )
                    continuation.yield(.completed(finalResponse))
                    continuation.finish()
                }
            }
        }
    }
}
