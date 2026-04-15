import Foundation
import XCTest
@testable import VibeWriteBackend
import VibeWriteShared

final class BackendAIExecutorTests: XCTestCase {
    func testMetadataFailureFallsBackToExistingProjectMetadata() async throws {
        let configuration = makeConfiguration(metadataRoute: .current)
        let secretStore = AdminSecretStore(
            providerApiKey: "provider-key",
            adminUsername: "admin",
            adminPassword: "password"
        )
        let systemPromptStore = AdminSystemPromptStore(
            snapshot: AdminSystemPromptSeed.makeSnapshot(clock: BackendAIExecutorTestClock(date: Date(timeIntervalSince1970: 1_710_000_000)))
        )
        let executor = BackendAIExecutor(
            configuration: configuration,
            providerClient: ThrowingMetadataProviderClient(),
            secretStore: secretStore,
            systemPromptStore: systemPromptStore
        )

        let request = WriteRequestEnvelope(
            installationId: "installation-fallback-001",
            deviceToken: "token-fallback-001",
            requestId: "request-fallback-001",
            action: .continueWriting,
            kind: .prose,
            project: sampleProjectSnapshot(),
            userMessage: "继续写下去",
            selectionText: "开头正文",
            selectionRange: WritingTextSelectionRange(location: 0, length: 4)
        )

        let response = try await executor.execute(for: request)

        XCTAssertEqual(
            response.documentText,
            """
            开头正文
            接下来可以顺着这个主线，再补一段更自然的推进。
            """
        )
        XCTAssertEqual(response.localSummary, request.project.localSummary)
        XCTAssertEqual(response.globalSynopsis, request.project.globalSynopsis)
        XCTAssertEqual(response.nextFocus, request.project.context.nextFocus)
        XCTAssertEqual(response.suggestionChips, request.project.suggestionChips)
        XCTAssertEqual(response.assistantMessage, "我接着往下写了一段，让主线继续往前走。")
    }

    private func makeConfiguration(metadataRoute: BackendAIConfiguration.MetadataRoute) -> BackendAIConfiguration {
        BackendAIConfiguration(
            mode: .real,
            provider: "minimax",
            baseURL: URL(string: "https://api.minimaxi.com/anthropic")!,
            textBaseURL: URL(string: "https://api.minimaxi.com")!,
            model: "MiniMax-M2.5-highspeed",
            metadataRoute: metadataRoute
        )
    }

    private func sampleProjectSnapshot() -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000041") ?? UUID(),
            automationKey: "task41",
            title: "写作任务",
            prompt: "继续写下去",
            mode: .collaboration,
            localSummary: "旧本地摘要",
            globalSynopsis: "旧全局梗概",
            context: ProjectContext(
                intentSummary: "先继续正文",
                styleConstraints: ["克制", "平静"],
                currentGoal: "续写下一段",
                recentDecisions: ["先写开头"],
                workingMemory: ["正文仍在推进"],
                nextFocus: "继续展开"
            ),
            conversation: [
                ConversationMessage(role: .user, text: "继续写下去", timestamp: "2026-04-15T00:00:00Z")
            ],
            documentText: "开头正文",
            suggestionChips: ["继续", "收紧"],
            updatedAt: Date(timeIntervalSince1970: 1_719_000_000)
        )
    }
}

private struct ThrowingMetadataProviderClient: BackendAIProviderClient {
    func generateProseText(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> String {
        return """
        
        接下来可以顺着这个主线，再补一段更自然的推进。
        """
    }

    func generateMetadata(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> WritingAICompletionMetadata {
        throw BackendAIError.providerError("AI metadata response did not include the expected tool call.")
    }
}

private struct BackendAIExecutorTestClock: VibeWriteClock, @unchecked Sendable {
    let dateValue: Date

    init(date: Date) {
        self.dateValue = date
    }

    func now() -> Date {
        dateValue
    }
}
