import Foundation
import XCTVapor
@testable import VibeWriteBackend
import VibeWriteShared

final class RequestLogTests: XCTestCase {
    func testAcceptedWriteRequestsAppendAcceptedLogs() throws {
        let clock = TestClock(date: shanghaiDate(year: 2026, month: 4, day: 13, hour: 9))
        let requestLogStore = InMemoryRequestLogStore()
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, requestLogStore: requestLogStore, clock: clock)

        let bootstrap = try bootstrapDevice(in: app, installationId: "installation-log-001")
        let project = sampleProjectSnapshot(documentText: "prefix middle suffix")

        try sendStart(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            requestId: "request-log-start-001"
        )
        try sendContinue(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            requestId: "request-log-continue-001"
        )
        try sendEdit(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            requestId: "request-log-edit-001"
        )

        let entries = try snapshotEntries(from: requestLogStore)
        XCTAssertEqual(entries.count, 3)

        XCTAssertEqual(entries[0].requestId, "request-log-start-001")
        XCTAssertEqual(entries[0].installationId, bootstrap.installationId)
        XCTAssertEqual(entries[0].action, .startDraft)
        XCTAssertEqual(entries[0].status, .accepted)
        XCTAssertNil(entries[0].errorCode)
        XCTAssertEqual(entries[0].provider, "minimax")
        XCTAssertEqual(entries[0].model, "MiniMax-M2.5-highspeed")
        XCTAssertEqual(entries[0].tokenIn, 0)
        XCTAssertEqual(entries[0].tokenOut, 0)

        XCTAssertEqual(entries[1].action, .continueWriting)
        XCTAssertEqual(entries[1].status, .accepted)

        XCTAssertEqual(entries[2].action, .edit)
        XCTAssertEqual(entries[2].status, .accepted)
        XCTAssertEqual(entries[2].requestId, "request-log-edit-001")
        XCTAssertEqual(entries[2].installationId, bootstrap.installationId)
        XCTAssertEqual(entries[2].provider, "minimax")
        XCTAssertEqual(entries[2].model, "MiniMax-M2.5-highspeed")
        XCTAssertEqual(entries[2].tokenIn, 0)
        XCTAssertEqual(entries[2].tokenOut, 0)
    }

    func testRejectedAuthenticationAppendsRejectedLog() throws {
        let clock = TestClock(date: shanghaiDate(year: 2026, month: 4, day: 13, hour: 9))
        let requestLogStore = InMemoryRequestLogStore()
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, requestLogStore: requestLogStore, clock: clock)

        let project = sampleProjectSnapshot(documentText: "prefix middle suffix")
        try sendStart(
            in: app,
            installationId: "installation-log-unauthorized",
            deviceToken: "not-a-real-token",
            project: project,
            requestId: "request-log-rejected-auth",
            expectedStatus: .unauthorized
        )

        let entries = try snapshotEntries(from: requestLogStore)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].status, .rejected)
        XCTAssertEqual(entries[0].errorCode, "unauthorized")
        XCTAssertEqual(entries[0].action, .startDraft)
        XCTAssertEqual(entries[0].provider, "minimax")
        XCTAssertEqual(entries[0].model, "MiniMax-M2.5-highspeed")
        XCTAssertEqual(entries[0].tokenIn, 0)
        XCTAssertEqual(entries[0].tokenOut, 0)
        XCTAssertEqual(entries[0].requestId, "request-log-rejected-auth")
    }

    func testRejectedQuotaAppendsRejectedLogWithoutConsumingRejectedRequest() throws {
        let clock = TestClock(date: shanghaiDate(year: 2026, month: 4, day: 13, hour: 9))
        let quotaLedger = InMemoryQuotaLedger(
            limit: QuotaLimit(dailyLimit: 1, weeklyLimit: 2),
            clock: clock
        )
        let requestLogStore = InMemoryRequestLogStore()
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, quotaLedger: quotaLedger, requestLogStore: requestLogStore, clock: clock)

        let bootstrap = try bootstrapDevice(in: app, installationId: "installation-log-quota")
        let project = sampleProjectSnapshot(documentText: "prefix middle suffix")

        try sendStart(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            requestId: "request-log-quota-accepted"
        )
        try sendContinue(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            requestId: "request-log-quota-rejected",
            expectedStatus: .tooManyRequests
        )

        clock.set(shanghaiDate(year: 2026, month: 4, day: 14, hour: 9))

        try sendEdit(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            requestId: "request-log-quota-next-day"
        )

        let entries = try snapshotEntries(from: requestLogStore)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[1].status, .rejected)
        XCTAssertEqual(entries[1].errorCode, "quota_exceeded")
        XCTAssertEqual(entries[1].requestId, "request-log-quota-rejected")
        XCTAssertEqual(entries[1].action, .continueWriting)
        XCTAssertEqual(entries[2].status, .accepted)
        XCTAssertEqual(entries[2].requestId, "request-log-quota-next-day")
    }

    private func bootstrapDevice(in app: Application, installationId: String) throws -> (installationId: String, deviceToken: String) {
        let bootstrapRequest = BootstrapRequest(
            installationId: installationId,
            appVersion: "3.0.0",
            platform: "macOS",
            deviceName: "QA Mac"
        )

        var issuedToken = ""
        try app.test(.POST, "v3/client/bootstrap", beforeRequest: { request in
            try request.content.encode(bootstrapRequest)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, .ok)
            XCTAssertContent(BootstrapResponse.self, response) { bootstrap in
                issuedToken = bootstrap.deviceToken
            }
        })

        return (bootstrapRequest.installationId, issuedToken)
    }

    private func sendStart(
        in app: Application,
        installationId: String,
        deviceToken: String,
        project: WritingProjectSnapshot,
        requestId: String,
        expectedStatus: HTTPStatus = .ok
    ) throws {
        let request = WriteRequestEnvelope(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: requestId,
            action: .startDraft,
            kind: .prose,
            project: project,
            userMessage: "先写开头",
            selectionText: nil,
            selectionRange: nil
        )

        try app.test(.POST, "v3/writes/start", beforeRequest: { req in
            try req.content.encode(request)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, expectedStatus)
        })
    }

    private func sendContinue(
        in app: Application,
        installationId: String,
        deviceToken: String,
        project: WritingProjectSnapshot,
        requestId: String,
        expectedStatus: HTTPStatus = .ok
    ) throws {
        let request = WriteRequestEnvelope(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: requestId,
            action: .continueWriting,
            kind: .prose,
            project: project,
            userMessage: "继续写",
            selectionText: nil,
            selectionRange: nil
        )

        try app.test(.POST, "v3/writes/continue", beforeRequest: { req in
            try req.content.encode(request)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, expectedStatus)
        })
    }

    private func sendEdit(
        in app: Application,
        installationId: String,
        deviceToken: String,
        project: WritingProjectSnapshot,
        requestId: String,
        expectedStatus: HTTPStatus = .ok
    ) throws {
        let selectionRange = WritingTextSelectionRange(location: 7, length: 6)
        let request = WriteRequestEnvelope(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: requestId,
            action: .edit,
            kind: .prose,
            project: project,
            userMessage: "把中间改得更克制",
            selectionText: selectionRange.substring(in: project.documentText),
            selectionRange: selectionRange
        )

        try app.test(.POST, "v3/writes/edit", beforeRequest: { req in
            try req.content.encode(request)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, expectedStatus)
        })
    }

    private func sampleProjectSnapshot(documentText: String) -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000032") ?? UUID(),
            automationKey: "task32",
            title: "写作任务",
            prompt: "先写开头",
            mode: .collaboration,
            localSummary: "本地摘要",
            globalSynopsis: "全局梗概",
            context: ProjectContext(
                intentSummary: "先起稿",
                styleConstraints: ["克制", "平静"],
                currentGoal: "生成第一段",
                recentDecisions: ["先写开头"],
                workingMemory: ["还在起稿"],
                nextFocus: "继续展开"
            ),
            conversation: [
                ConversationMessage(role: .user, text: "先写开头", timestamp: "2026-04-12T00:00:00Z")
            ],
            documentText: documentText,
            suggestionChips: ["继续", "收紧"],
            updatedAt: Date(timeIntervalSince1970: 1_719_000_000)
        )
    }

    private func shanghaiDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Asia/Shanghai")
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    private func snapshotEntries(from store: InMemoryRequestLogStore) throws -> [RequestLogEntry] {
        try blockingValue {
            await store.snapshot()
        }
    }

    private func blockingValue<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = BlockingResultBox<T>()
        let job: @Sendable () async -> Void = {
            do {
                box.store(.success(try await operation()))
            } catch {
                box.store(.failure(error))
            }
            semaphore.signal()
        }
        Task.detached(operation: job)
        semaphore.wait()
        return try box.load()
    }
}

private final class BlockingResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func store(_ result: Result<T, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try result!.get()
    }
}

final class TestClock: VibeWriteClock, @unchecked Sendable {
    private let lock = NSLock()
    private var currentDate: Date

    init(date: Date) {
        self.currentDate = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return currentDate
    }

    func set(_ date: Date) {
        lock.lock()
        currentDate = date
        lock.unlock()
    }
}
