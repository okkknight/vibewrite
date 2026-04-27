import Foundation
import XCTVapor
@testable import VibeWriteBackend
import VibeWriteShared

final class QuotaGateTests: XCTestCase {
    func testStartContinueAndEditAllPassWithinQuota() throws {
        let clock = FixedClock(date: shanghaiDate(year: 2026, month: 4, day: 13, hour: 9))
        let ledger = InMemoryQuotaLedger(
            limit: QuotaLimit(dailyLimit: 3, weeklyLimit: 3),
            clock: clock
        )
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, quotaLedger: ledger)

        let bootstrap = try bootstrapDevice(in: app, installationId: "installation-quota-001")
        let project = sampleProjectSnapshot(documentText: "prefix middle suffix")

        try sendStart(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project
        )

        try sendContinue(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project
        )

        try sendEdit(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project
        )
    }

    func testDailyQuotaExceedRejectsAndDoesNotConsumeRejectedRequest() throws {
        let clock = FixedClock(date: shanghaiDate(year: 2026, month: 4, day: 13, hour: 9))
        let ledger = InMemoryQuotaLedger(
            limit: QuotaLimit(dailyLimit: 1, weeklyLimit: 2),
            clock: clock
        )
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, quotaLedger: ledger)

        let bootstrap = try bootstrapDevice(in: app, installationId: "installation-quota-002")
        let project = sampleProjectSnapshot(documentText: "prefix middle suffix")

        try sendStart(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project
        )

        try sendContinue(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            expectedStatus: .tooManyRequests
        )

        clock.set(shanghaiDate(year: 2026, month: 4, day: 14, hour: 9))

        try sendStart(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project
        )
    }

    func testWeeklyQuotaExceedRejectsWithinSameWeek() throws {
        let clock = FixedClock(date: shanghaiDate(year: 2026, month: 4, day: 13, hour: 9))
        let ledger = InMemoryQuotaLedger(
            limit: QuotaLimit(dailyLimit: 10, weeklyLimit: 1),
            clock: clock
        )
        let app = Application(.testing)
        defer { app.shutdown() }

        try configure(app, quotaLedger: ledger)

        let bootstrap = try bootstrapDevice(in: app, installationId: "installation-quota-003")
        let project = sampleProjectSnapshot(documentText: "prefix middle suffix")

        try sendEdit(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project
        )

        try sendStart(
            in: app,
            installationId: bootstrap.installationId,
            deviceToken: bootstrap.deviceToken,
            project: project,
            expectedStatus: .tooManyRequests
        )
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
        expectedStatus: HTTPStatus = .ok
    ) throws {
        let request = makeGatewayStartRequest(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: UUID().uuidString,
            project: project,
            userMessage: "先写开头"
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
        expectedStatus: HTTPStatus = .ok
    ) throws {
        let request = makeGatewayContinueRequest(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: UUID().uuidString,
            project: project,
            userMessage: "继续写"
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
        expectedStatus: HTTPStatus = .ok
    ) throws {
        let selectionRange = WritingTextSelectionRange(location: 7, length: 6)
        let request = makeGatewayEditRequest(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: UUID().uuidString,
            project: project,
            selectionRange: selectionRange,
            userMessage: "把中间改得更克制"
        )

        try app.test(.POST, "v3/writes/edit", beforeRequest: { req in
            try req.content.encode(request)
        }, afterResponse: { response in
            XCTAssertEqual(response.status, expectedStatus)
        })
    }

    private func sampleProjectSnapshot(documentText: String) -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031") ?? UUID(),
            automationKey: "task31",
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
}

final class FixedClock: VibeWriteClock, @unchecked Sendable {
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
