import Foundation
import Fluent
import VibeWriteShared

final class DeviceRecordModel: Model, @unchecked Sendable {
    static let schema = "devices"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "installation_id")
    var installationId: String

    @Field(key: "installation_hash")
    var installationHash: String

    @Field(key: "device_token_hash")
    var deviceTokenHash: String

    @Field(key: "device_token_ciphertext")
    var deviceTokenCiphertext: String

    @Field(key: "status")
    var statusRaw: String

    @Field(key: "first_seen_at")
    var firstSeenAt: Date

    @Field(key: "last_seen_at")
    var lastSeenAt: Date

    @Field(key: "token_issued_at")
    var tokenIssuedAt: Date

    @OptionalField(key: "blocked_at")
    var blockedAt: Date?

    @OptionalField(key: "block_reason")
    var blockReason: String?

    init() {}

    init(
        installationId: String,
        installationHash: String,
        deviceTokenHash: String,
        deviceTokenCiphertext: String,
        status: DeviceStatus,
        firstSeenAt: Date,
        lastSeenAt: Date,
        tokenIssuedAt: Date,
        blockedAt: Date?,
        blockReason: String?
    ) {
        self.installationId = installationId
        self.installationHash = installationHash
        self.deviceTokenHash = deviceTokenHash
        self.deviceTokenCiphertext = deviceTokenCiphertext
        self.statusRaw = status.rawValue
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.tokenIssuedAt = tokenIssuedAt
        self.blockedAt = blockedAt
        self.blockReason = blockReason
    }

    var status: DeviceStatus {
        get { DeviceStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var snapshot: DeviceSnapshot {
        DeviceSnapshot(
            installationId: installationId,
            deviceToken: "",
            status: status,
            firstSeenAt: firstSeenAt,
            lastSeenAt: lastSeenAt,
            tokenIssuedAt: tokenIssuedAt,
            blockedAt: blockedAt,
            blockReason: blockReason
        )
    }
}

final class RequestLogRecordModel: Model, @unchecked Sendable {
    static let schema = "request_logs"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "request_id")
    var requestId: String

    @Field(key: "installation_id")
    var installationId: String

    @Field(key: "action")
    var actionRaw: String

    @Field(key: "status")
    var statusRaw: String

    @OptionalField(key: "error_code")
    var errorCode: String?

    @Field(key: "provider")
    var provider: String

    @Field(key: "model")
    var model: String

    @Field(key: "duration_ms")
    var durationMs: Int

    @Field(key: "token_in")
    var tokenIn: Int

    @Field(key: "token_out")
    var tokenOut: Int

    @Field(key: "created_at")
    var createdAt: Date

    init() {}

    init(entry: RequestLogEntry) {
        self.requestId = entry.requestId
        self.installationId = entry.installationId
        self.actionRaw = entry.action.rawValue
        self.statusRaw = entry.status.rawValue
        self.errorCode = entry.errorCode
        self.provider = entry.provider
        self.model = entry.model
        self.durationMs = entry.durationMs
        self.tokenIn = entry.tokenIn
        self.tokenOut = entry.tokenOut
        self.createdAt = entry.createdAt
    }

    var entry: RequestLogEntry {
        RequestLogEntry(
            requestId: requestId,
            installationId: installationId,
            action: WritingAIAction(rawValue: actionRaw) ?? .startDraft,
            status: RequestLogStatus(rawValue: statusRaw) ?? .accepted,
            errorCode: errorCode,
            provider: provider,
            model: model,
            durationMs: durationMs,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            createdAt: createdAt
        )
    }
}

final class QuotaRuleRecordModel: Model, @unchecked Sendable {
    static let schema = "quota_rules"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "config_key")
    var configKey: String

    @Field(key: "daily_limit")
    var dailyLimit: Int

    @Field(key: "weekly_limit")
    var weeklyLimit: Int

    @Field(key: "updated_at")
    var updatedAt: Date

    @OptionalField(key: "updated_by")
    var updatedBy: String?

    init() {}

    init(configKey: String = "current", limit: QuotaLimit, updatedAt: Date, updatedBy: String? = nil) {
        self.configKey = configKey
        self.dailyLimit = limit.dailyLimit
        self.weeklyLimit = limit.weeklyLimit
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    var limit: QuotaLimit {
        QuotaLimit(dailyLimit: dailyLimit, weeklyLimit: weeklyLimit)
    }
}

final class QuotaUsageDailyRecordModel: Model, @unchecked Sendable {
    static let schema = "quota_usage_daily"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "installation_id")
    var installationId: String

    @Field(key: "usage_date")
    var usageDate: String

    @Field(key: "used_requests")
    var usedRequests: Int

    @Field(key: "updated_at")
    var updatedAt: Date

    init() {}

    init(installationId: String, usageDate: String, usedRequests: Int, updatedAt: Date) {
        self.installationId = installationId
        self.usageDate = usageDate
        self.usedRequests = usedRequests
        self.updatedAt = updatedAt
    }
}

final class QuotaUsageWeeklyRecordModel: Model, @unchecked Sendable {
    static let schema = "quota_usage_weekly"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "installation_id")
    var installationId: String

    @Field(key: "week_start_date")
    var weekStartDate: String

    @Field(key: "used_requests")
    var usedRequests: Int

    @Field(key: "updated_at")
    var updatedAt: Date

    init() {}

    init(installationId: String, weekStartDate: String, usedRequests: Int, updatedAt: Date) {
        self.installationId = installationId
        self.weekStartDate = weekStartDate
        self.usedRequests = usedRequests
        self.updatedAt = updatedAt
    }
}

final class SecretConfigRecordModel: Model, @unchecked Sendable {
    static let schema = "secret_configs"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "config_key")
    var configKey: String

    @Field(key: "secret_ciphertext")
    var secretCiphertext: String

    @Field(key: "updated_at")
    var updatedAt: Date

    @OptionalField(key: "updated_by")
    var updatedBy: String?

    @Field(key: "enabled")
    var enabled: Bool

    init() {}

    init(configKey: String = "current", secretCiphertext: String, updatedAt: Date, updatedBy: String? = nil, enabled: Bool = true) {
        self.configKey = configKey
        self.secretCiphertext = secretCiphertext
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.enabled = enabled
    }
}

final class SystemPromptConfigRecordModel: Model, @unchecked Sendable {
    static let schema = "system_prompt_configs"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "config_key")
    var configKey: String

    @Field(key: "template_body")
    var templateBody: String

    @Field(key: "action_rules_json")
    var actionRulesJson: String

    @Field(key: "model_context_rules_json")
    var modelContextRulesJson: String

    @Field(key: "updated_at")
    var updatedAt: Date

    @OptionalField(key: "updated_by")
    var updatedBy: String?

    init() {}

    init(
        configKey: String = "current",
        templateBody: String,
        actionRulesJson: String,
        modelContextRulesJson: String,
        updatedAt: Date,
        updatedBy: String? = nil
    ) {
        self.configKey = configKey
        self.templateBody = templateBody
        self.actionRulesJson = actionRulesJson
        self.modelContextRulesJson = modelContextRulesJson
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }
}

final class AdminSessionRecordModel: Model, @unchecked Sendable {
    static let schema = "admin_sessions"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "session_id_hash")
    var sessionIdHash: String

    @Field(key: "created_at")
    var createdAt: Date

    @Field(key: "expires_at")
    var expiresAt: Date

    @Field(key: "last_seen_at")
    var lastSeenAt: Date

    @OptionalField(key: "revoked_at")
    var revokedAt: Date?

    init() {}

    init(
        sessionIdHash: String,
        createdAt: Date,
        expiresAt: Date,
        lastSeenAt: Date,
        revokedAt: Date? = nil
    ) {
        self.sessionIdHash = sessionIdHash
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.lastSeenAt = lastSeenAt
        self.revokedAt = revokedAt
    }
}

struct BackendSecretPayload: Codable, Sendable, Equatable {
    let providerApiKey: String?
    let adminUsername: String
    let adminPassword: String
}
