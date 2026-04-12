import Foundation

struct QuotaLimit: Sendable, Equatable {
    let dailyLimit: Int
    let weeklyLimit: Int

    static let `default` = QuotaLimit(dailyLimit: 50, weeklyLimit: 200)
}

enum QuotaLedgerDecision: Sendable, Equatable {
    case allowed
    case quotaExceeded
}

protocol VibeWriteClock: Sendable {
    func now() -> Date
}

struct SystemVibeWriteClock: VibeWriteClock {
    func now() -> Date {
        Date()
    }
}

actor InMemoryQuotaLedger {
    private struct Usage: Sendable {
        var dailyKey: String
        var dailyCount: Int
        var weeklyKey: String
        var weeklyCount: Int
    }

    private let clock: any VibeWriteClock
    private let timeZone: TimeZone
    private let limit: QuotaLimit
    private var usageByInstallationId: [String: Usage] = [:]

    init(
        limit: QuotaLimit = .default,
        clock: any VibeWriteClock = SystemVibeWriteClock(),
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    ) {
        self.limit = limit
        self.clock = clock
        self.timeZone = timeZone
    }

    func evaluateAndConsumeIfAllowed(installationId: String) -> QuotaLedgerDecision {
        let now = clock.now()
        let dailyKey = Self.dailyKey(for: now, timeZone: timeZone)
        let weeklyKey = Self.weeklyKey(for: now, timeZone: timeZone)

        var usage = usageByInstallationId[installationId] ?? Usage(
            dailyKey: dailyKey,
            dailyCount: 0,
            weeklyKey: weeklyKey,
            weeklyCount: 0
        )

        if usage.dailyKey != dailyKey {
            usage.dailyKey = dailyKey
            usage.dailyCount = 0
        }

        if usage.weeklyKey != weeklyKey {
            usage.weeklyKey = weeklyKey
            usage.weeklyCount = 0
        }

        guard usage.dailyCount < limit.dailyLimit,
              usage.weeklyCount < limit.weeklyLimit else {
            usageByInstallationId[installationId] = usage
            return .quotaExceeded
        }

        usage.dailyCount += 1
        usage.weeklyCount += 1
        usageByInstallationId[installationId] = usage
        return .allowed
    }

    private static func dailyKey(for date: Date, timeZone: TimeZone) -> String {
        let calendar = Calendar(identifier: .gregorian)
        var adjusted = calendar
        adjusted.timeZone = timeZone

        let components = adjusted.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func weeklyKey(for date: Date, timeZone: TimeZone) -> String {
        let calendar = Calendar(identifier: .gregorian)
        var adjusted = calendar
        adjusted.timeZone = timeZone

        let startOfDay = adjusted.startOfDay(for: date)
        let weekday = adjusted.component(.weekday, from: startOfDay)
        let offset = (weekday + 5) % 7
        guard let monday = adjusted.date(byAdding: .day, value: -offset, to: startOfDay) else {
            return dailyKey(for: date, timeZone: timeZone)
        }

        let components = adjusted.dateComponents([.year, .month, .day], from: monday)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
