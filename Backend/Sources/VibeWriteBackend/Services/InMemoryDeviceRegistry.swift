import Foundation

enum DeviceAccessDecision: Sendable, Equatable {
    case valid
    case blocked
    case unauthorized
}

struct DeviceBootstrapResult: Sendable, Equatable {
    let deviceToken: String
    let deviceStatus: DeviceStatus
}

struct DeviceSnapshot: Sendable, Equatable {
    let installationId: String
    let deviceToken: String
    let status: DeviceStatus
    let firstSeenAt: Date
    let lastSeenAt: Date
    let tokenIssuedAt: Date
    let blockedAt: Date?
    let blockReason: String?
}

actor InMemoryDeviceRegistry: VibeWriteDeviceRegistryStore {
    private struct DeviceRecord: Sendable {
        let installationId: String
        var deviceToken: String
        var status: DeviceStatus
        var firstSeenAt: Date
        var lastSeenAt: Date
        var tokenIssuedAt: Date
        var blockedAt: Date?
        var blockReason: String?
    }

    private let clock: any VibeWriteClock
    private var devicesByInstallationId: [String: DeviceRecord] = [:]

    init(
        clock: any VibeWriteClock = SystemVibeWriteClock()
    ) {
        self.clock = clock
    }

    func bootstrap(installationId: String) -> DeviceBootstrapResult {
        let now = clock.now()
        let record = touchRecord(for: installationId, now: now)
        return DeviceBootstrapResult(
            deviceToken: record.deviceToken,
            deviceStatus: record.status
        )
    }

    func validateDevice(installationId: String, deviceToken: String) -> DeviceAccessDecision {
        guard var record = devicesByInstallationId[installationId], record.deviceToken == deviceToken else {
            return .unauthorized
        }

        record.lastSeenAt = clock.now()
        devicesByInstallationId[installationId] = record
        return record.status == .blocked ? .blocked : .valid
    }

    func block(installationId: String, reason: String? = nil) -> DeviceSnapshot {
        let now = clock.now()
        var record = ensureRecord(for: installationId, now: now)
        record.status = .blocked
        record.blockedAt = now
        record.blockReason = normalizedBlockReason(reason)
        devicesByInstallationId[installationId] = record
        return snapshot(from: record)
    }

    func unblock(installationId: String) -> DeviceSnapshot {
        let now = clock.now()
        var record = ensureRecord(for: installationId, now: now)
        record.status = .active
        record.blockedAt = nil
        record.blockReason = nil
        devicesByInstallationId[installationId] = record
        return snapshot(from: record)
    }

    func activeDeviceCount() -> Int {
        devicesByInstallationId.values.filter { $0.status == .active }.count
    }

    func snapshot() -> [DeviceSnapshot] {
        devicesByInstallationId.values
            .map(snapshot(from:))
            .sorted { lhs, rhs in
                if lhs.lastSeenAt != rhs.lastSeenAt {
                    return lhs.lastSeenAt > rhs.lastSeenAt
                }

                return lhs.installationId < rhs.installationId
            }
    }

    func snapshot(for installationId: String) -> DeviceSnapshot? {
        devicesByInstallationId[installationId].map(snapshot(from:))
    }

    private func ensureRecord(for installationId: String, now: Date) -> DeviceRecord {
        if let existing = devicesByInstallationId[installationId] {
            return existing
        }

        let record = DeviceRecord(
            installationId: installationId,
            deviceToken: Self.makeDeviceToken(),
            status: .active,
            firstSeenAt: now,
            lastSeenAt: now,
            tokenIssuedAt: now,
            blockedAt: nil,
            blockReason: nil
        )
        devicesByInstallationId[installationId] = record
        return record
    }

    private func touchRecord(for installationId: String, now: Date) -> DeviceRecord {
        if let existing = devicesByInstallationId[installationId] {
            var record = existing
            record.lastSeenAt = now
            devicesByInstallationId[installationId] = record
            return record
        }

        let record = DeviceRecord(
            installationId: installationId,
            deviceToken: Self.makeDeviceToken(),
            status: .active,
            firstSeenAt: now,
            lastSeenAt: now,
            tokenIssuedAt: now,
            blockedAt: nil,
            blockReason: nil
        )
        devicesByInstallationId[installationId] = record
        return record
    }

    private func snapshot(from record: DeviceRecord) -> DeviceSnapshot {
        DeviceSnapshot(
            installationId: record.installationId,
            deviceToken: record.deviceToken,
            status: record.status,
            firstSeenAt: record.firstSeenAt,
            lastSeenAt: record.lastSeenAt,
            tokenIssuedAt: record.tokenIssuedAt,
            blockedAt: record.blockedAt,
            blockReason: record.blockReason
        )
    }

    private func normalizedBlockReason(_ reason: String?) -> String {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "manual" : trimmed
    }

    private static func makeDeviceToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
