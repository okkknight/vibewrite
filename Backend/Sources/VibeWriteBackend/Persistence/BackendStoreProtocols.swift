import Foundation
import VibeWriteShared

protocol VibeWriteDeviceRegistryStore: Sendable {
    func bootstrap(installationId: String) async throws -> DeviceBootstrapResult
    func validateDevice(installationId: String, deviceToken: String) async throws -> DeviceAccessDecision
    func block(installationId: String, reason: String?) async throws -> DeviceSnapshot
    func unblock(installationId: String) async throws -> DeviceSnapshot
    func activeDeviceCount() async throws -> Int
    func snapshot() async throws -> [DeviceSnapshot]
    func snapshot(for installationId: String) async throws -> DeviceSnapshot?
}

protocol VibeWriteQuotaLedgerStore: Sendable {
    func evaluateAndConsumeIfAllowed(installationId: String) async throws -> QuotaLedgerDecision
    func currentLimit() async throws -> QuotaLimit
    func updateLimit(dailyLimit: Int?, weeklyLimit: Int?) async throws
    func currentUsageSnapshot() async throws -> QuotaLedgerSnapshot
    func usageSnapshot(for installationId: String) async throws -> QuotaUsageSnapshot
    func snapshotUsage() async throws -> [QuotaUsageSnapshot]
}

protocol VibeWriteRequestLogStore: Sendable {
    func append(_ entry: RequestLogEntry) async throws
    func snapshot() async throws -> [RequestLogEntry]
    func query(_ query: RequestLogQuery) async throws -> RequestLogQueryResult
    func summary(matching query: RequestLogQuery) async throws -> RequestLogSummary
}

protocol VibeWriteAdminSecretStore: Sendable {
    func authenticate(username: String, password: String) async throws -> Bool
    func providerApiKey() async throws -> String?
    func secretCurrentSnapshot() async throws -> AdminSecretStore.Snapshot
    func secretSnapshotResponse() async throws -> AdminSecretsResponse
    func updateSecrets(
        providerApiKey: String?,
        adminUsername: String?,
        adminPassword: String?
    ) async throws
}

protocol VibeWriteAdminSystemPromptStore: Sendable {
    func systemPromptSnapshotResponse() async throws -> AdminSystemPromptResponse
    func systemPromptCurrentSnapshot() async throws -> AdminSystemPromptStore.Snapshot
    func updateSystemPrompt(
        templateBody: String?,
        actionRulesJson: String?,
        modelContextRulesJson: String?
    ) async throws
}

protocol VibeWriteAdminSessionStore: Sendable {
    func issueSession() async throws -> String
    func isAuthenticated(sessionToken: String?) async throws -> Bool
    func logout(sessionToken: String?) async throws
}

protocol BackendPersistenceBootstrapper: Sendable {
    func prepare() async throws
}
