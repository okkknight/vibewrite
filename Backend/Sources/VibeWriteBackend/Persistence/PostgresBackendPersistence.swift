import Foundation
import Fluent
import Vapor
import VibeWriteShared

actor PostgresBackendPersistence: BackendPersistenceBootstrapper,
    VibeWriteDeviceRegistryStore,
    VibeWriteQuotaLedgerStore,
    VibeWriteRequestLogStore,
    VibeWriteAdminSecretStore,
    VibeWriteAdminSystemPromptStore,
    VibeWriteAdminSessionStore
{
    private let app: Application
    private let clock: any VibeWriteClock
    private let secretCipher: BackendSecretCipher
    private let adminSecretSeed: AdminSecretStore.Snapshot
    private let systemPromptSeed: AdminSystemPromptStore.Snapshot

    init(
        app: Application,
        clock: any VibeWriteClock,
        secretCipher: BackendSecretCipher,
        adminSecretSeed: AdminSecretStore.Snapshot,
        systemPromptSeed: AdminSystemPromptStore.Snapshot
    ) {
        self.app = app
        self.clock = clock
        self.secretCipher = secretCipher
        self.adminSecretSeed = adminSecretSeed
        self.systemPromptSeed = systemPromptSeed
    }

    func prepare() async throws {
        try await app.autoMigrate()
        try await seedQuotaRulesIfNeeded()
        try await seedSecretConfigIfNeeded()
        try await seedSystemPromptConfigIfNeeded()
    }

    // MARK: Device Registry

    func bootstrap(installationId: String) async throws -> DeviceBootstrapResult {
        let now = clock.now()
        let installationHash = secretCipher.digest(installationId)

        if let record = try await loadDevice(installationId: installationId) {
            record.lastSeenAt = now
            try await record.save(on: app.db)
            let token = try secretCipher.decrypt(record.deviceTokenCiphertext, as: String.self)
            return DeviceBootstrapResult(deviceToken: token, deviceStatus: record.status)
        }

        let deviceToken = Self.makeDeviceToken()
        let record = DeviceRecordModel(
            installationId: installationId,
            installationHash: installationHash,
            deviceTokenHash: secretCipher.digest(deviceToken),
            deviceTokenCiphertext: try secretCipher.encrypt(deviceToken),
            status: .active,
            firstSeenAt: now,
            lastSeenAt: now,
            tokenIssuedAt: now,
            blockedAt: nil,
            blockReason: nil
        )
        try await record.create(on: app.db)
        return DeviceBootstrapResult(deviceToken: deviceToken, deviceStatus: .active)
    }

    func validateDevice(installationId: String, deviceToken: String) async throws -> DeviceAccessDecision {
        guard let record = try await loadDevice(installationId: installationId) else {
            return .unauthorized
        }

        guard record.deviceTokenHash == secretCipher.digest(deviceToken) else {
            return .unauthorized
        }

        record.lastSeenAt = clock.now()
        try await record.save(on: app.db)
        return record.status == .blocked ? .blocked : .valid
    }

    func block(installationId: String, reason: String?) async throws -> DeviceSnapshot {
        let now = clock.now()
        let record = try await ensureDeviceRecord(installationId: installationId, now: now)
        record.status = .blocked
        record.blockedAt = now
        record.blockReason = Self.normalizedBlockReason(reason)
        try await record.save(on: app.db)
        return try snapshot(from: record)
    }

    func unblock(installationId: String) async throws -> DeviceSnapshot {
        let now = clock.now()
        let record = try await ensureDeviceRecord(installationId: installationId, now: now)
        record.status = .active
        record.blockedAt = nil
        record.blockReason = nil
        try await record.save(on: app.db)
        return try snapshot(from: record)
    }

    func activeDeviceCount() async throws -> Int {
        try await DeviceRecordModel.query(on: app.db)
            .filter(\.$statusRaw == DeviceStatus.active.rawValue)
            .count()
    }

    func snapshot() async throws -> [DeviceSnapshot] {
        let records = try await DeviceRecordModel.query(on: app.db)
            .sort(\.$lastSeenAt, .descending)
            .all()
        return try records.map(snapshot(from:))
    }

    func snapshot(for installationId: String) async throws -> DeviceSnapshot? {
        guard let record = try await loadDevice(installationId: installationId) else {
            return nil
        }

        return try snapshot(from: record)
    }

    // MARK: Quota Ledger

    func evaluateAndConsumeIfAllowed(installationId: String) async throws -> QuotaLedgerDecision {
        let now = clock.now()
        let limit = try await currentLimit()
        let dayKey = BackendTimeBuckets.dailyKey(for: now)
        let weekKey = BackendTimeBuckets.weeklyKey(for: now)

        return try await app.db.transaction { database in
            let daily = try await self.loadDailyUsage(
                installationId: installationId,
                usageDate: dayKey,
                database: database
            )
            let weekly = try await self.loadWeeklyUsage(
                installationId: installationId,
                weekStartDate: weekKey,
                database: database
            )

            guard daily.usedRequests < limit.dailyLimit,
                  weekly.usedRequests < limit.weeklyLimit else {
                return .quotaExceeded
            }

            daily.usedRequests += 1
            daily.updatedAt = now
            weekly.usedRequests += 1
            weekly.updatedAt = now

            try await daily.save(on: database)
            try await weekly.save(on: database)
            return .allowed
        }
    }

    func currentLimit() async throws -> QuotaLimit {
        if let record = try await QuotaRuleRecordModel.query(on: app.db)
            .filter(\.$configKey == "current")
            .first() {
            return record.limit
        }

        return .default
    }

    func updateLimit(dailyLimit: Int?, weeklyLimit: Int?) async throws {
        guard dailyLimit != nil || weeklyLimit != nil else {
            return
        }

        let now = clock.now()
        let record = try await loadOrCreateQuotaRule(now: now)
        record.dailyLimit = dailyLimit ?? record.dailyLimit
        record.weeklyLimit = weeklyLimit ?? record.weeklyLimit
        record.updatedAt = now
        try await record.save(on: app.db)
    }

    func currentUsageSnapshot() async throws -> QuotaLedgerSnapshot {
        let limit = try await currentLimit()
        let now = clock.now()
        let dailyKey = BackendTimeBuckets.dailyKey(for: now)
        let weeklyKey = BackendTimeBuckets.weeklyKey(for: now)

        let dailyRows = try await QuotaUsageDailyRecordModel.query(on: app.db)
            .filter(\.$usageDate == dailyKey)
            .all()
        let weeklyRows = try await QuotaUsageWeeklyRecordModel.query(on: app.db)
            .filter(\.$weekStartDate == weeklyKey)
            .all()

        return QuotaLedgerSnapshot(
            limit: limit,
            limitUpdatedAt: try await quotaRuleUpdatedAt(),
            totalDailyUsed: dailyRows.reduce(0) { $0 + $1.usedRequests },
            totalWeeklyUsed: weeklyRows.reduce(0) { $0 + $1.usedRequests },
            usageByInstallationId: mergeUsageSnapshots(
                dailyRows: dailyRows,
                weeklyRows: weeklyRows,
                currentDateKey: dailyKey,
                currentWeekKey: weeklyKey
            )
        )
    }

    func usageSnapshot(for installationId: String) async throws -> QuotaUsageSnapshot {
        let now = clock.now()
        let dailyKey = BackendTimeBuckets.dailyKey(for: now)
        let weeklyKey = BackendTimeBuckets.weeklyKey(for: now)
        let dailyRow = try await QuotaUsageDailyRecordModel.query(on: app.db)
            .filter(\.$installationId == installationId)
            .filter(\.$usageDate == dailyKey)
            .first()
        let weeklyRow = try await QuotaUsageWeeklyRecordModel.query(on: app.db)
            .filter(\.$installationId == installationId)
            .filter(\.$weekStartDate == weeklyKey)
            .first()

        return QuotaUsageSnapshot(
            installationId: installationId,
            dailyUsed: dailyRow?.usedRequests ?? 0,
            weeklyUsed: weeklyRow?.usedRequests ?? 0
        )
    }

    func snapshotUsage() async throws -> [QuotaUsageSnapshot] {
        let now = clock.now()
        let dailyKey = BackendTimeBuckets.dailyKey(for: now)
        let weeklyKey = BackendTimeBuckets.weeklyKey(for: now)
        let dailyRows = try await QuotaUsageDailyRecordModel.query(on: app.db)
            .filter(\.$usageDate == dailyKey)
            .all()
        let weeklyRows = try await QuotaUsageWeeklyRecordModel.query(on: app.db)
            .filter(\.$weekStartDate == weeklyKey)
            .all()

        return mergeUsageSnapshots(
            dailyRows: dailyRows,
            weeklyRows: weeklyRows,
            currentDateKey: dailyKey,
            currentWeekKey: weeklyKey
        )
    }

    // MARK: Request Logs

    func append(_ entry: RequestLogEntry) async throws {
        try await RequestLogRecordModel(entry: entry).create(on: app.db)
    }

    func snapshot() async throws -> [RequestLogEntry] {
        let models = try await RequestLogRecordModel.query(on: app.db)
            .sort(\.$createdAt, .ascending)
            .all()
        return models.map(\.entry)
    }

    func query(_ query: RequestLogQuery) async throws -> RequestLogQueryResult {
        let database = app.db
        var builder = RequestLogRecordModel.query(on: database)

        if let installationId = query.installationId {
            builder = builder.filter(\.$installationId == installationId)
        }

        if let action = query.action {
            builder = builder.filter(\.$actionRaw == action.rawValue)
        }

        if let status = query.status {
            builder = builder.filter(\.$statusRaw == status.rawValue)
        }

        if let errorCode = query.errorCode {
            builder = builder.filter(\.$errorCode == errorCode)
        }

        if let createdAtRange = query.createdAtRange {
            builder = builder.filter(\.$createdAt >= createdAtRange.lowerBound)
            builder = builder.filter(\.$createdAt <= createdAtRange.upperBound)
        }

        let models = try await builder.sort(\.$createdAt, .descending).all()
        let entries = models.map(\.entry)
        return RequestLogQueryResult(entries: entries, summary: RequestLogSummary(entries: entries))
    }

    func summary(matching query: RequestLogQuery) async throws -> RequestLogSummary {
        try await self.query(query).summary
    }

    // MARK: Admin Secrets

    func authenticate(username: String, password: String) async throws -> Bool {
        let snapshot = try await secretCurrentSnapshot()
        return snapshot.adminUsername == username && snapshot.adminPassword == password
    }

    func providerApiKey() async throws -> String? {
        try await secretCurrentSnapshot().providerApiKey
    }

    func secretCurrentSnapshot() async throws -> AdminSecretStore.Snapshot {
        try await loadSecretSnapshot()
    }

    func secretSnapshotResponse() async throws -> AdminSecretsResponse {
        let snapshot = try await loadSecretSnapshot()
        return AdminSecretsResponse(
            providerApiKeyConfigured: snapshot.providerApiKeyConfigured,
            adminUsername: snapshot.adminUsername,
            adminPasswordConfigured: snapshot.adminPasswordConfigured,
            updatedAt: AdminDateCodec.string(from: snapshot.updatedAt)
        )
    }

    func updateSecrets(
        providerApiKey: String? = nil,
        adminUsername: String? = nil,
        adminPassword: String? = nil
    ) async throws {
        guard providerApiKey != nil || adminUsername != nil || adminPassword != nil else {
            return
        }

        let now = clock.now()
        let snapshot = try await loadSecretSnapshot()
        let updated = AdminSecretStore.Snapshot(
            providerApiKey: providerApiKey ?? snapshot.providerApiKey,
            adminUsername: adminUsername ?? snapshot.adminUsername,
            adminPassword: adminPassword ?? snapshot.adminPassword,
            updatedAt: now
        )
        try await saveSecretSnapshot(updated)
    }

    // MARK: System Prompt

    func systemPromptSnapshotResponse() async throws -> AdminSystemPromptResponse {
        let snapshot = try await loadSystemPromptSnapshot()
        return AdminSystemPromptResponse(
            templateBody: snapshot.templateBody,
            actionRulesJson: snapshot.actionRulesJson,
            modelContextRulesJson: snapshot.modelContextRulesJson,
            updatedAt: AdminDateCodec.string(from: snapshot.updatedAt)
        )
    }

    func systemPromptCurrentSnapshot() async throws -> AdminSystemPromptStore.Snapshot {
        try await loadSystemPromptSnapshot()
    }

    func updateSystemPrompt(
        templateBody: String? = nil,
        actionRulesJson: String? = nil,
        modelContextRulesJson: String? = nil
    ) async throws {
        if let actionRulesJson {
            try AdminSystemPromptStore.validateJSON(actionRulesJson, field: "actionRulesJson")
        }

        if let modelContextRulesJson {
            try AdminSystemPromptStore.validateJSON(modelContextRulesJson, field: "modelContextRulesJson")
        }

        guard templateBody != nil || actionRulesJson != nil || modelContextRulesJson != nil else {
            return
        }

        let now = clock.now()
        let snapshot = try await loadSystemPromptSnapshot()
        let updated = AdminSystemPromptStore.Snapshot(
            templateBody: templateBody ?? snapshot.templateBody,
            actionRulesJson: actionRulesJson ?? snapshot.actionRulesJson,
            modelContextRulesJson: modelContextRulesJson ?? snapshot.modelContextRulesJson,
            updatedAt: now
        )
        try await saveSystemPromptSnapshot(updated, updatedBy: "admin")
    }

    // MARK: Admin Sessions

    func issueSession() async throws -> String {
        let now = clock.now()
        let sessionToken = Self.makeSessionToken()
        let record = AdminSessionRecordModel(
            sessionIdHash: secretCipher.digest(sessionToken),
            createdAt: now,
            expiresAt: now.addingTimeInterval(60 * 60 * 24 * 365 * 10),
            lastSeenAt: now,
            revokedAt: nil
        )
        try await record.create(on: app.db)
        return sessionToken
    }

    func isAuthenticated(sessionToken: String?) async throws -> Bool {
        guard let sessionToken else {
            return false
        }

        let sessionHash = secretCipher.digest(sessionToken)
        guard let record = try await AdminSessionRecordModel.query(on: app.db)
            .filter(\.$sessionIdHash == sessionHash)
            .first() else {
            return false
        }

        guard record.revokedAt == nil, record.expiresAt > clock.now() else {
            return false
        }

        record.lastSeenAt = clock.now()
        try await record.save(on: app.db)
        return true
    }

    func logout(sessionToken: String?) async throws {
        guard let sessionToken else {
            return
        }

        let sessionHash = secretCipher.digest(sessionToken)
        guard let record = try await AdminSessionRecordModel.query(on: app.db)
            .filter(\.$sessionIdHash == sessionHash)
            .first() else {
            return
        }

        record.revokedAt = clock.now()
        try await record.save(on: app.db)
    }

    // MARK: Bootstrapping helpers

    private func seedQuotaRulesIfNeeded() async throws {
        guard let record = try await QuotaRuleRecordModel.query(on: app.db).filter(\.$configKey == "current").first() else {
            try await QuotaRuleRecordModel(
                configKey: "current",
                limit: .default,
                updatedAt: clock.now(),
                updatedBy: nil
            ).create(on: app.db)
            return
        }

        if shouldUpgradeLegacyQuotaSeed(record) {
            record.dailyLimit = QuotaLimit.default.dailyLimit
            record.weeklyLimit = QuotaLimit.default.weeklyLimit
            record.updatedAt = clock.now()
            record.updatedBy = nil
            try await record.save(on: app.db)
        }
    }

    private func seedSecretConfigIfNeeded() async throws {
        if try await SecretConfigRecordModel.query(on: app.db).filter(\.$configKey == "current").first() != nil {
            _ = try await loadSecretSnapshot()
            return
        }

        try await saveSecretSnapshot(adminSecretSeed)
    }

    private func seedSystemPromptConfigIfNeeded() async throws {
        guard let record = try await SystemPromptConfigRecordModel.query(on: app.db)
            .filter(\.$configKey == "current")
            .first() else {
            try await saveSystemPromptSnapshot(systemPromptSeed)
            return
        }

        if shouldUpgradeLegacySystemPromptSeed(record) {
            try await saveSystemPromptSnapshot(systemPromptSeed)
            return
        }

        _ = try await loadSystemPromptSnapshot()
    }

    private func loadDevice(installationId: String) async throws -> DeviceRecordModel? {
        try await DeviceRecordModel.query(on: app.db)
            .filter(\.$installationId == installationId)
            .first()
    }

    private func ensureDeviceRecord(installationId: String, now: Date) async throws -> DeviceRecordModel {
        if let record = try await loadDevice(installationId: installationId) {
            return record
        }

        let deviceToken = Self.makeDeviceToken()
        let record = DeviceRecordModel(
            installationId: installationId,
            installationHash: secretCipher.digest(installationId),
            deviceTokenHash: secretCipher.digest(deviceToken),
            deviceTokenCiphertext: try secretCipher.encrypt(deviceToken),
            status: .active,
            firstSeenAt: now,
            lastSeenAt: now,
            tokenIssuedAt: now,
            blockedAt: nil,
            blockReason: nil
        )
        try await record.create(on: app.db)
        return record
    }

    private func snapshot(from record: DeviceRecordModel) throws -> DeviceSnapshot {
        DeviceSnapshot(
            installationId: record.installationId,
            deviceToken: try secretCipher.decrypt(record.deviceTokenCiphertext, as: String.self),
            status: record.status,
            firstSeenAt: record.firstSeenAt,
            lastSeenAt: record.lastSeenAt,
            tokenIssuedAt: record.tokenIssuedAt,
            blockedAt: record.blockedAt,
            blockReason: record.blockReason
        )
    }

    private func loadOrCreateQuotaRule(now: Date) async throws -> QuotaRuleRecordModel {
        if let record = try await QuotaRuleRecordModel.query(on: app.db)
            .filter(\.$configKey == "current")
            .first() {
            return record
        }

        let record = QuotaRuleRecordModel(configKey: "current", limit: .default, updatedAt: now)
        try await record.create(on: app.db)
        return record
    }

    private func quotaRuleUpdatedAt() async throws -> Date {
        if let record = try await QuotaRuleRecordModel.query(on: app.db)
            .filter(\.$configKey == "current")
            .first() {
            return record.updatedAt
        }

        return clock.now()
    }

    private func loadDailyUsage(
        installationId: String,
        usageDate: String,
        database: any Database
    ) async throws -> QuotaUsageDailyRecordModel {
        if let record = try await QuotaUsageDailyRecordModel.query(on: database)
            .filter(\.$installationId == installationId)
            .filter(\.$usageDate == usageDate)
            .first() {
            return record
        }

        let record = QuotaUsageDailyRecordModel(
            installationId: installationId,
            usageDate: usageDate,
            usedRequests: 0,
            updatedAt: clock.now()
        )
        try await record.create(on: database)
        return record
    }

    private func loadWeeklyUsage(
        installationId: String,
        weekStartDate: String,
        database: any Database
    ) async throws -> QuotaUsageWeeklyRecordModel {
        if let record = try await QuotaUsageWeeklyRecordModel.query(on: database)
            .filter(\.$installationId == installationId)
            .filter(\.$weekStartDate == weekStartDate)
            .first() {
            return record
        }

        let record = QuotaUsageWeeklyRecordModel(
            installationId: installationId,
            weekStartDate: weekStartDate,
            usedRequests: 0,
            updatedAt: clock.now()
        )
        try await record.create(on: database)
        return record
    }

    private func mergeUsageSnapshots(
        dailyRows: [QuotaUsageDailyRecordModel],
        weeklyRows: [QuotaUsageWeeklyRecordModel],
        currentDateKey: String,
        currentWeekKey: String
    ) -> [QuotaUsageSnapshot] {
        let dailyMap = Dictionary(
            uniqueKeysWithValues: dailyRows
                .filter { $0.usageDate == currentDateKey }
                .map { ($0.installationId, $0.usedRequests) }
        )
        let weeklyMap = Dictionary(
            uniqueKeysWithValues: weeklyRows
                .filter { $0.weekStartDate == currentWeekKey }
                .map { ($0.installationId, $0.usedRequests) }
        )
        let installationIds = Set(dailyMap.keys).union(weeklyMap.keys).sorted()

        return installationIds.map { installationId in
            QuotaUsageSnapshot(
                installationId: installationId,
                dailyUsed: dailyMap[installationId] ?? 0,
                weeklyUsed: weeklyMap[installationId] ?? 0
            )
        }
    }

    private func loadSecretSnapshot() async throws -> AdminSecretStore.Snapshot {
        guard let record = try await SecretConfigRecordModel.query(on: app.db)
            .filter(\.$configKey == "current")
            .first() else {
            throw Abort(.internalServerError, reason: "Missing secret config row.")
        }

        guard record.enabled else {
            throw Abort(.forbidden, reason: "Secret config is disabled.")
        }

        return try secretCipher.decrypt(record.secretCiphertext, as: BackendSecretPayload.self).snapshot(updatedAt: record.updatedAt)
    }

    private func saveSecretSnapshot(_ snapshot: AdminSecretStore.Snapshot) async throws {
        let record = try await SecretConfigRecordModel.query(on: app.db)
            .filter(\.$configKey == "current")
            .first() ?? SecretConfigRecordModel(
                configKey: "current",
                secretCiphertext: "",
                updatedAt: snapshot.updatedAt,
                updatedBy: nil,
                enabled: true
            )
        record.secretCiphertext = try secretCipher.encrypt(
            BackendSecretPayload(
                providerApiKey: snapshot.providerApiKey,
                adminUsername: snapshot.adminUsername,
                adminPassword: snapshot.adminPassword
            )
        )
        record.updatedAt = snapshot.updatedAt
        record.enabled = true
        if record.id == nil {
            try await record.create(on: app.db)
        } else {
            try await record.save(on: app.db)
        }
    }

    private func loadSystemPromptSnapshot() async throws -> AdminSystemPromptStore.Snapshot {
        guard let record = try await SystemPromptConfigRecordModel.query(on: app.db)
            .filter(\.$configKey == "current")
            .first() else {
            throw Abort(.internalServerError, reason: "Missing system prompt config row.")
        }

        return AdminSystemPromptStore.Snapshot(
            templateBody: record.templateBody,
            actionRulesJson: record.actionRulesJson,
            modelContextRulesJson: record.modelContextRulesJson,
            updatedAt: record.updatedAt
        )
    }

    private func saveSystemPromptSnapshot(_ snapshot: AdminSystemPromptStore.Snapshot, updatedBy: String? = nil) async throws {
        let record = try await SystemPromptConfigRecordModel.query(on: app.db)
            .filter(\.$configKey == "current")
            .first() ?? SystemPromptConfigRecordModel(
                configKey: "current",
                templateBody: snapshot.templateBody,
                actionRulesJson: snapshot.actionRulesJson,
                modelContextRulesJson: snapshot.modelContextRulesJson,
                updatedAt: snapshot.updatedAt,
                updatedBy: nil
            )
        record.templateBody = snapshot.templateBody
        record.actionRulesJson = snapshot.actionRulesJson
        record.modelContextRulesJson = snapshot.modelContextRulesJson
        record.updatedAt = snapshot.updatedAt
        record.updatedBy = updatedBy
        if record.id == nil {
            try await record.create(on: app.db)
        } else {
            try await record.save(on: app.db)
        }
    }

    private func shouldUpgradeLegacySystemPromptSeed(_ record: SystemPromptConfigRecordModel) -> Bool {
        record.updatedBy == nil && record.actionRulesJson.contains("[[VIBEWRITE_METADATA]]")
    }

    private func shouldUpgradeLegacyQuotaSeed(_ record: QuotaRuleRecordModel) -> Bool {
        record.dailyLimit == QuotaLimit.legacyDefault.dailyLimit
            && record.weeklyLimit == QuotaLimit.legacyDefault.weeklyLimit
    }

    private static func normalizedBlockReason(_ reason: String?) -> String {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "manual" : trimmed
    }

    private static func makeDeviceToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func makeSessionToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

private extension BackendSecretPayload {
    func snapshot(updatedAt: Date) -> AdminSecretStore.Snapshot {
        AdminSecretStore.Snapshot(
            providerApiKey: providerApiKey,
            adminUsername: adminUsername,
            adminPassword: adminPassword,
            updatedAt: updatedAt
        )
    }
}
