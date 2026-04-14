import Foundation

struct QuotaLimit: Sendable, Equatable {
    let dailyLimit: Int
    let weeklyLimit: Int

    static let `default` = QuotaLimit(dailyLimit: 50, weeklyLimit: 200)
}

struct QuotaUsageSnapshot: Sendable, Equatable {
    let installationId: String
    let dailyUsed: Int
    let weeklyUsed: Int
}

struct QuotaLedgerSnapshot: Sendable, Equatable {
    let limit: QuotaLimit
    let limitUpdatedAt: Date
    let totalDailyUsed: Int
    let totalWeeklyUsed: Int
    let usageByInstallationId: [QuotaUsageSnapshot]
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

actor InMemoryQuotaLedger: VibeWriteQuotaLedgerStore {
    private struct Usage: Sendable {
        var dailyKey: String
        var dailyCount: Int
        var weeklyKey: String
        var weeklyCount: Int
    }

    private let clock: any VibeWriteClock
    private let timeZone: TimeZone
    private var limit: QuotaLimit
    private var limitUpdatedAt: Date
    private var usageByInstallationId: [String: Usage] = [:]

    init(
        limit: QuotaLimit = .default,
        clock: any VibeWriteClock = SystemVibeWriteClock(),
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    ) {
        self.limit = limit
        self.clock = clock
        self.timeZone = timeZone
        self.limitUpdatedAt = clock.now()
    }

    func evaluateAndConsumeIfAllowed(installationId: String) -> QuotaLedgerDecision {
        let now = clock.now()
        let usage = normalizedUsage(for: installationId, now: now)

        guard usage.dailyCount < limit.dailyLimit,
              usage.weeklyCount < limit.weeklyLimit else {
            return .quotaExceeded
        }

        var updatedUsage = usage
        updatedUsage.dailyCount += 1
        updatedUsage.weeklyCount += 1
        usageByInstallationId[installationId] = updatedUsage
        return .allowed
    }

    func currentLimit() -> QuotaLimit {
        limit
    }

    func updateLimit(dailyLimit: Int? = nil, weeklyLimit: Int? = nil) {
        guard dailyLimit != nil || weeklyLimit != nil else {
            return
        }

        limit = QuotaLimit(
            dailyLimit: dailyLimit ?? limit.dailyLimit,
            weeklyLimit: weeklyLimit ?? limit.weeklyLimit
        )
        limitUpdatedAt = clock.now()
    }

    func currentUsageSnapshot() -> QuotaLedgerSnapshot {
        let usageSnapshots = snapshotUsage()
        return QuotaLedgerSnapshot(
            limit: limit,
            limitUpdatedAt: limitUpdatedAt,
            totalDailyUsed: usageSnapshots.reduce(into: 0) { $0 += $1.dailyUsed },
            totalWeeklyUsed: usageSnapshots.reduce(into: 0) { $0 += $1.weeklyUsed },
            usageByInstallationId: usageSnapshots
        )
    }

    func usageSnapshot(for installationId: String) -> QuotaUsageSnapshot {
        let usage = normalizedUsage(for: installationId, now: clock.now())
        return QuotaUsageSnapshot(
            installationId: installationId,
            dailyUsed: usage.dailyCount,
            weeklyUsed: usage.weeklyCount
        )
    }

    func snapshotUsage() -> [QuotaUsageSnapshot] {
        let now = clock.now()
        return usageByInstallationId.keys
            .sorted()
            .map { installationId in
                let usage = normalizedUsage(for: installationId, now: now)
                return QuotaUsageSnapshot(
                    installationId: installationId,
                    dailyUsed: usage.dailyCount,
                    weeklyUsed: usage.weeklyCount
                )
            }
    }

    private func normalizedUsage(for installationId: String, now: Date) -> Usage {
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

        usageByInstallationId[installationId] = usage
        return usage
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
