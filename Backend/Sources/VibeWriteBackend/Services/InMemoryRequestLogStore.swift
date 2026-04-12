import Foundation
import VibeWriteShared

enum RequestLogStatus: String, Sendable, Equatable {
    case accepted
    case rejected
}

struct RequestLogEntry: Sendable, Equatable {
    let requestId: String
    let installationId: String
    let action: WritingAIAction
    let status: RequestLogStatus
    let errorCode: String?
    let provider: String
    let model: String
    let durationMs: Int
    let tokenIn: Int
    let tokenOut: Int
    let createdAt: Date
}

final class InMemoryRequestLogStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [RequestLogEntry] = []

    func append(_ entry: RequestLogEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    func snapshot() -> [RequestLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}
