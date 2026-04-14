import Fluent
import Vapor

struct CreateDeviceRecordsMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(DeviceRecordModel.schema)
            .id()
            .field("installation_id", .string, .required)
            .field("installation_hash", .string, .required)
            .field("device_token_hash", .string, .required)
            .field("device_token_ciphertext", .string, .required)
            .field("status", .string, .required)
            .field("first_seen_at", .datetime, .required)
            .field("last_seen_at", .datetime, .required)
            .field("token_issued_at", .datetime, .required)
            .field("blocked_at", .datetime)
            .field("block_reason", .string)
            .unique(on: "installation_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(DeviceRecordModel.schema).delete()
    }
}

struct CreateRequestLogsMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(RequestLogRecordModel.schema)
            .id()
            .field("request_id", .string, .required)
            .field("installation_id", .string, .required)
            .field("action", .string, .required)
            .field("status", .string, .required)
            .field("error_code", .string)
            .field("provider", .string, .required)
            .field("model", .string, .required)
            .field("duration_ms", .int, .required)
            .field("token_in", .int, .required)
            .field("token_out", .int, .required)
            .field("created_at", .datetime, .required)
            .unique(on: "request_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(RequestLogRecordModel.schema).delete()
    }
}

struct CreateQuotaRulesMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(QuotaRuleRecordModel.schema)
            .id()
            .field("config_key", .string, .required)
            .field("daily_limit", .int, .required)
            .field("weekly_limit", .int, .required)
            .field("updated_at", .datetime, .required)
            .field("updated_by", .string)
            .unique(on: "config_key")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(QuotaRuleRecordModel.schema).delete()
    }
}

struct CreateQuotaUsageDailyMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(QuotaUsageDailyRecordModel.schema)
            .id()
            .field("installation_id", .string, .required)
            .field("usage_date", .string, .required)
            .field("used_requests", .int, .required)
            .field("updated_at", .datetime, .required)
            .unique(on: "installation_id", "usage_date")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(QuotaUsageDailyRecordModel.schema).delete()
    }
}

struct CreateQuotaUsageWeeklyMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(QuotaUsageWeeklyRecordModel.schema)
            .id()
            .field("installation_id", .string, .required)
            .field("week_start_date", .string, .required)
            .field("used_requests", .int, .required)
            .field("updated_at", .datetime, .required)
            .unique(on: "installation_id", "week_start_date")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(QuotaUsageWeeklyRecordModel.schema).delete()
    }
}

struct CreateSecretConfigsMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(SecretConfigRecordModel.schema)
            .id()
            .field("config_key", .string, .required)
            .field("secret_ciphertext", .string, .required)
            .field("updated_at", .datetime, .required)
            .field("updated_by", .string)
            .field("enabled", .bool, .required)
            .unique(on: "config_key")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(SecretConfigRecordModel.schema).delete()
    }
}

struct CreateSystemPromptConfigsMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(SystemPromptConfigRecordModel.schema)
            .id()
            .field("config_key", .string, .required)
            .field("template_body", .string, .required)
            .field("action_rules_json", .string, .required)
            .field("model_context_rules_json", .string, .required)
            .field("updated_at", .datetime, .required)
            .field("updated_by", .string)
            .unique(on: "config_key")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(SystemPromptConfigRecordModel.schema).delete()
    }
}

struct CreateAdminSessionsMigration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(AdminSessionRecordModel.schema)
            .id()
            .field("session_id_hash", .string, .required)
            .field("created_at", .datetime, .required)
            .field("expires_at", .datetime, .required)
            .field("last_seen_at", .datetime, .required)
            .field("revoked_at", .datetime)
            .unique(on: "session_id_hash")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(AdminSessionRecordModel.schema).delete()
    }
}

enum BackendDatabaseMigrationPlan {
    static func register(_ app: Application) {
        app.migrations.add(CreateDeviceRecordsMigration())
        app.migrations.add(CreateRequestLogsMigration())
        app.migrations.add(CreateQuotaRulesMigration())
        app.migrations.add(CreateQuotaUsageDailyMigration())
        app.migrations.add(CreateQuotaUsageWeeklyMigration())
        app.migrations.add(CreateSecretConfigsMigration())
        app.migrations.add(CreateSystemPromptConfigsMigration())
        app.migrations.add(CreateAdminSessionsMigration())
    }
}
