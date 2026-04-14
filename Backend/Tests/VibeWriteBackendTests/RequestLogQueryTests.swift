import Foundation
import XCTest
@testable import VibeWriteBackend
import VibeWriteShared

final class RequestLogQueryTests: XCTestCase {
    func testQueryFiltersByInstallationIdAndSortsByCreatedAtDescending() async throws {
        let store = InMemoryRequestLogStore()
        let base = Date(timeIntervalSince1970: 1_000)

        try await store.append(makeEntry(
            requestId: "request-001",
            installationId: "installation-a",
            action: .startDraft,
            status: .accepted,
            errorCode: nil,
            createdAt: base.addingTimeInterval(10)
        ))
        try await store.append(makeEntry(
            requestId: "request-002",
            installationId: "installation-b",
            action: .continueWriting,
            status: .rejected,
            errorCode: "quota_exceeded",
            createdAt: base.addingTimeInterval(15)
        ))
        try await store.append(makeEntry(
            requestId: "request-003",
            installationId: "installation-a",
            action: .edit,
            status: .rejected,
            errorCode: "unauthorized",
            createdAt: base.addingTimeInterval(5)
        ))

        let result = try await store.query(RequestLogQuery(installationId: "installation-a", action: nil, status: nil, errorCode: nil, createdAtRange: nil))

        XCTAssertEqual(result.entries.map(\.requestId), ["request-001", "request-003"])
        XCTAssertEqual(result.summary.totalCount, 2)
        XCTAssertEqual(result.summary.acceptedCount, 1)
        XCTAssertEqual(result.summary.rejectedCount, 1)
    }

    func testQueryFiltersByActionStatusAndErrorCode() async throws {
        let store = InMemoryRequestLogStore()
        let base = Date(timeIntervalSince1970: 2_000)

        try await store.append(makeEntry(
            requestId: "request-004",
            installationId: "installation-a",
            action: .startDraft,
            status: .accepted,
            errorCode: nil,
            createdAt: base.addingTimeInterval(10)
        ))
        try await store.append(makeEntry(
            requestId: "request-005",
            installationId: "installation-a",
            action: .continueWriting,
            status: .rejected,
            errorCode: "quota_exceeded",
            createdAt: base.addingTimeInterval(20)
        ))
        try await store.append(makeEntry(
            requestId: "request-006",
            installationId: "installation-b",
            action: .continueWriting,
            status: .rejected,
            errorCode: "unauthorized",
            createdAt: base.addingTimeInterval(30)
        ))

        let continueRejected = try await store.query(RequestLogQuery(
            installationId: nil,
            action: .continueWriting,
            status: .rejected,
            errorCode: nil,
            createdAtRange: nil
        ))
        XCTAssertEqual(continueRejected.entries.map(\.requestId), ["request-006", "request-005"])
        XCTAssertEqual(continueRejected.summary.totalCount, 2)
        XCTAssertEqual(continueRejected.summary.acceptedCount, 0)
        XCTAssertEqual(continueRejected.summary.rejectedCount, 2)

        let quotaRejected = try await store.query(RequestLogQuery(
            installationId: nil,
            action: nil,
            status: nil,
            errorCode: "quota_exceeded",
            createdAtRange: nil
        ))
        XCTAssertEqual(quotaRejected.entries.map(\.requestId), ["request-005"])
        XCTAssertEqual(quotaRejected.summary.totalCount, 1)
        XCTAssertEqual(quotaRejected.summary.acceptedCount, 0)
        XCTAssertEqual(quotaRejected.summary.rejectedCount, 1)
    }

    func testQueryFiltersByTimeRangeAndProducesSummaryCounts() async throws {
        let store = InMemoryRequestLogStore()
        let base = Date(timeIntervalSince1970: 3_000)

        try await store.append(makeEntry(
            requestId: "request-007",
            installationId: "installation-a",
            action: .startDraft,
            status: .accepted,
            errorCode: nil,
            createdAt: base.addingTimeInterval(5)
        ))
        try await store.append(makeEntry(
            requestId: "request-008",
            installationId: "installation-b",
            action: .continueWriting,
            status: .rejected,
            errorCode: "quota_exceeded",
            createdAt: base.addingTimeInterval(15)
        ))
        try await store.append(makeEntry(
            requestId: "request-009",
            installationId: "installation-a",
            action: .edit,
            status: .accepted,
            errorCode: nil,
            createdAt: base.addingTimeInterval(25)
        ))
        try await store.append(makeEntry(
            requestId: "request-010",
            installationId: "installation-c",
            action: .edit,
            status: .rejected,
            errorCode: "invalid_request",
            createdAt: base.addingTimeInterval(35)
        ))

        let result = try await store.query(RequestLogQuery(
            installationId: nil,
            action: nil,
            status: nil,
            errorCode: nil,
            createdAtRange: base.addingTimeInterval(10)...base.addingTimeInterval(30)
        ))

        XCTAssertEqual(result.entries.map(\.requestId), ["request-009", "request-008"])
        XCTAssertEqual(result.summary.totalCount, 2)
        XCTAssertEqual(result.summary.acceptedCount, 1)
        XCTAssertEqual(result.summary.rejectedCount, 1)

        let summary = try await store.summary(matching: RequestLogQuery(
            installationId: "installation-a",
            action: nil,
            status: nil,
            errorCode: nil,
            createdAtRange: nil
        ))
        XCTAssertEqual(summary.totalCount, 2)
        XCTAssertEqual(summary.acceptedCount, 2)
        XCTAssertEqual(summary.rejectedCount, 0)
    }

    private func makeEntry(
        requestId: String,
        installationId: String,
        action: WritingAIAction,
        status: RequestLogStatus,
        errorCode: String?,
        createdAt: Date
    ) -> RequestLogEntry {
        RequestLogEntry(
            requestId: requestId,
            installationId: installationId,
            action: action,
            status: status,
            errorCode: errorCode,
            provider: "stub-provider",
            model: "stub-model",
            durationMs: 12,
            tokenIn: 0,
            tokenOut: 0,
            createdAt: createdAt
        )
    }
}
