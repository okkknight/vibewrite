import Foundation
import XCTest
@testable import VibeWriteBackend
import VibeWriteShared

final class CodexBackendAIProviderClientTests: XCTestCase {
    func testGenerateProseTextParsesAgentMessageFromCodexJsonl() async throws {
        let runner = FakeCodexRunner(
            result: CodexCommandResult(
                stdout: """
                {"type":"thread.started","thread_id":"thread_1"}
                {"type":"turn.started"}
                {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"第一段。\\n\\n第二段。"}}
                {"type":"turn.completed","usage":{"output_tokens":12}}
                """,
                stderr: "",
                terminationStatus: 0
            )
        )
        let client = CodexBackendAIProviderClient(commandRunner: runner)
        let configuration = makeConfiguration()
        let request = makeRequest(kind: .prose)
        let messages = [
            WritingAIChatMessage(role: .system, content: "System policy"),
            WritingAIChatMessage(role: .user, content: "请继续写")
        ]

        let proseText = try await client.generateProseText(
            for: request,
            messages: messages,
            configuration: configuration,
            apiKey: ""
        )

        XCTAssertEqual(proseText, "第一段。\n\n第二段。")

        let invocations = await runner.recordedInvocations()
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].model, "gpt-test-model")
        XCTAssertTrue(invocations[0].prompt.contains("SYSTEM"))
        XCTAssertTrue(invocations[0].prompt.contains("USER"))
        XCTAssertTrue(invocations[0].prompt.contains("Do not use tools, browse files, or run commands."))
        XCTAssertTrue(invocations[0].prompt.contains("System policy"))
        XCTAssertTrue(invocations[0].prompt.contains("请继续写"))
    }

    func testGenerateMetadataFallsBackWhenCodexOutputIsNotJson() async throws {
        let runner = FakeCodexRunner(
            result: CodexCommandResult(
                stdout: """
                {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"not json"}}
                """,
                stderr: "",
                terminationStatus: 0
            )
        )
        let client = CodexBackendAIProviderClient(commandRunner: runner)
        let configuration = makeConfiguration()
        let request = makeMetadataRequest()
        let messages = [
            WritingAIChatMessage(role: .system, content: "Return JSON only."),
            WritingAIChatMessage(role: .user, content: "请生成元数据")
        ]

        let metadata = try await client.generateMetadata(
            for: request,
            messages: messages,
            configuration: configuration,
            apiKey: ""
        )

        XCTAssertEqual(metadata.localSummary, request.project.localSummary)
        XCTAssertEqual(metadata.globalSynopsis, request.project.globalSynopsis)
        XCTAssertEqual(metadata.nextFocus, request.project.context.nextFocus)
        XCTAssertEqual(metadata.suggestionChips, request.project.suggestionChips)
    }

    func testBackendAIConfigurationResolvesCodexModelFromCodexHome() throws {
        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexHome = tempRoot.appendingPathComponent(".codex", isDirectory: true)
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        let configURL = codexHome.appendingPathComponent("config.toml")
        try """
        model = "gpt-temp-model"
        model_reasoning_effort = "high"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let configuration = BackendAIConfiguration.current(
            environment: [
                "CODEX_HOME": codexHome.path,
                "VIBEWRITE_AI_PROVIDER": "codex"
            ],
            launchArguments: [],
            isTesting: false
        )

        XCTAssertEqual(configuration.provider, "codex")
        XCTAssertEqual(configuration.model, "gpt-temp-model")
        XCTAssertEqual(configuration.metadataRoute, .current)
    }

    private func makeConfiguration() -> BackendAIConfiguration {
        BackendAIConfiguration(
            mode: .real,
            provider: "codex",
            baseURL: URL(string: "https://example.com")!,
            textBaseURL: URL(string: "https://example.com/text")!,
            model: "gpt-test-model",
            metadataRoute: .current
        )
    }

    private func makeRequest(kind: WritingAIRequestKind) -> WritingAIRequest {
        WritingAIRequest(
            action: .continueWriting,
            project: sampleProjectSnapshot(),
            userMessage: "继续往下写",
            selectionText: nil,
            kind: kind
        )
    }

    private func makeMetadataRequest() -> WritingAIRequest {
        WritingAIRequest(
            action: .continueWriting,
            project: sampleProjectSnapshot(),
            userMessage: "继续往下写",
            selectionText: nil,
            kind: .metadata
        )
    }

    private func sampleProjectSnapshot() -> WritingProjectSnapshot {
        WritingProjectSnapshot(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
            automationKey: "backend.codex.test",
            title: "测试",
            prompt: "继续往下写",
            mode: .collaboration,
            localSummary: "本地摘要",
            globalSynopsis: "全局梗概",
            context: ProjectContext(
                intentSummary: "意图",
                styleConstraints: ["克制", "平静"],
                currentGoal: "目标",
                recentDecisions: ["决策"],
                workingMemory: ["记忆"],
                nextFocus: "继续往下写"
            ),
            conversation: [],
            documentText: "开头正文",
            suggestionChips: ["继续写", "编辑这段"],
            updatedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
    }
}

private actor FakeCodexRunner: CodexCommandRunning {
    struct Invocation: Sendable, Equatable {
        let prompt: String
        let model: String
    }

    private let result: CodexCommandResult
    private var invocations: [Invocation] = []

    init(result: CodexCommandResult) {
        self.result = result
    }

    func run(prompt: String, model: String) async throws -> CodexCommandResult {
        invocations.append(Invocation(prompt: prompt, model: model))
        return result
    }

    func recordedInvocations() -> [Invocation] {
        invocations
    }
}
