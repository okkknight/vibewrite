import Foundation
import VibeWriteShared

enum RequestLogStatus: String, Codable, Sendable, Equatable {
    case accepted
    case rejected
}

struct RequestLogEntry: Codable, Sendable, Equatable {
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

struct RequestLogQuery: Codable, Sendable, Equatable {
    let installationId: String?
    let action: WritingAIAction?
    let status: RequestLogStatus?
    let errorCode: String?
    let createdAtRange: ClosedRange<Date>?

    static let all = RequestLogQuery(
        installationId: nil,
        action: nil,
        status: nil,
        errorCode: nil,
        createdAtRange: nil
    )
}

struct RequestLogSummary: Codable, Sendable, Equatable {
    let totalCount: Int
    let acceptedCount: Int
    let rejectedCount: Int
}

struct RequestLogQueryResult: Codable, Sendable, Equatable {
    let entries: [RequestLogEntry]
    let summary: RequestLogSummary
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

    func query(_ query: RequestLogQuery = .all) -> RequestLogQueryResult {
        let snapshot = self.snapshot()
        let filtered = snapshot
            .enumerated()
            .filter { query.matches($0.element) }
            .sorted { lhs, rhs in
                if lhs.element.createdAt != rhs.element.createdAt {
                    return lhs.element.createdAt > rhs.element.createdAt
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)

        return RequestLogQueryResult(
            entries: filtered,
            summary: RequestLogSummary(from: filtered)
        )
    }

    func summary(matching query: RequestLogQuery = .all) -> RequestLogSummary {
        self.query(query).summary
    }
}

private extension RequestLogQuery {
    func matches(_ entry: RequestLogEntry) -> Bool {
        if let installationId, entry.installationId != installationId {
            return false
        }

        if let action, entry.action != action {
            return false
        }

        if let status, entry.status != status {
            return false
        }

        if let errorCode {
            guard entry.errorCode == errorCode else {
                return false
            }
        }

        if let createdAtRange, !createdAtRange.contains(entry.createdAt) {
            return false
        }

        return true
    }
}

private extension RequestLogSummary {
    init(from entries: [RequestLogEntry]) {
        let acceptedCount = entries.reduce(into: 0) { partialResult, entry in
            if entry.status == .accepted {
                partialResult += 1
            }
        }
        let rejectedCount = entries.count - acceptedCount
        self.init(
            totalCount: entries.count,
            acceptedCount: acceptedCount,
            rejectedCount: rejectedCount
        )
    }
}
