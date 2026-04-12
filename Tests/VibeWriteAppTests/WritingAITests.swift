import XCTest
import VibeWriteShared
@testable import VibeWriteApp

@MainActor
final class WritingAITests: XCTestCase {
    func testConfigurationUsesBundleValuesAndFallsBackToStubWhenMissing() {
        let configuration = WritingAIConfiguration.configuration(from: [
            "VIBEWRITE_AI_DEFAULT_MODE": "real",
            "VIBEWRITE_AI_PROVIDER": "minimax",
            "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
            "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
            "MINIMAX_TEXT_BASE_URL": "https://api.minimaxi.com",
            "MINIMAX_METADATA_ROUTE": "text01_json_schema",
            "MINIMAX_API_KEY": "bundle-key-123"
        ])

        XCTAssertEqual(configuration.mode, .real)
        XCTAssertEqual(configuration.provider, "minimax")
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://api.minimaxi.com/anthropic")
        XCTAssertEqual(configuration.textBaseURL.absoluteString, "https://api.minimaxi.com")
        XCTAssertEqual(configuration.model, "MiniMax-M2.5-highspeed")
        XCTAssertEqual(configuration.metadataRoute, .text01JsonSchema)
        XCTAssertEqual(configuration.metadataModel, "MiniMax-Text-01")
        XCTAssertEqual(configuration.apiKey, "bundle-key-123")
        XCTAssertTrue(configuration.shouldUseRealClient)

        let overriddenConfiguration = WritingAIConfiguration.configuration(
            from: [
                "VIBEWRITE_AI_DEFAULT_MODE": "real",
                "MINIMAX_METADATA_ROUTE": "current",
                "MINIMAX_API_KEY": "bundle-key-123"
            ],
            environment: [
                "VIBEWRITE_AI_MODE": "stub",
                "MINIMAX_METADATA_ROUTE": "text01_json_schema",
                "MINIMAX_API_KEY": "env-key-456"
            ]
        )

        XCTAssertEqual(overriddenConfiguration.mode, .stub)
        XCTAssertEqual(overriddenConfiguration.metadataRoute, .text01JsonSchema)
        XCTAssertEqual(overriddenConfiguration.apiKey, "env-key-456")

        let cleanLaunchConfiguration = WritingAIConfiguration.configuration(
            from: [
                "VIBEWRITE_AI_DEFAULT_MODE": "real",
                "VIBEWRITE_AI_PROVIDER": "minimax",
                "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
                "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
                "MINIMAX_TEXT_BASE_URL": "https://api.minimaxi.com",
                "MINIMAX_API_KEY": "bundle-key-123"
            ],
            environment: [
                "VIBEWRITE_AI_MODE": "stub",
                "MINIMAX_API_KEY": "env-key-456",
                "MINIMAX_BASE_URL": "https://example.invalid"
            ]
        )

        XCTAssertEqual(cleanLaunchConfiguration.mode, .stub)
        XCTAssertEqual(cleanLaunchConfiguration.metadataRoute, .current)
        XCTAssertEqual(cleanLaunchConfiguration.metadataModel, "MiniMax-M2.5-highspeed")

        let ignoredOverrideConfiguration = WritingAIConfiguration.configuration(
            from: [
                "VIBEWRITE_AI_DEFAULT_MODE": "real",
                "VIBEWRITE_AI_PROVIDER": "minimax",
                "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
                "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
                "MINIMAX_TEXT_BASE_URL": "https://api.minimaxi.com",
                "MINIMAX_API_KEY": "bundle-key-123"
            ],
            environment: [:]
        )
        XCTAssertEqual(ignoredOverrideConfiguration.mode, .real)
        XCTAssertEqual(ignoredOverrideConfiguration.provider, "minimax")
        XCTAssertEqual(ignoredOverrideConfiguration.baseURL.absoluteString, "https://api.minimaxi.com/anthropic")
        XCTAssertEqual(ignoredOverrideConfiguration.textBaseURL.absoluteString, "https://api.minimaxi.com")
        XCTAssertEqual(ignoredOverrideConfiguration.model, "MiniMax-M2.5-highspeed")
        XCTAssertEqual(ignoredOverrideConfiguration.metadataRoute, .current)
        XCTAssertEqual(ignoredOverrideConfiguration.metadataModel, "MiniMax-M2.5-highspeed")
        XCTAssertEqual(ignoredOverrideConfiguration.apiKey, "bundle-key-123")
        XCTAssertTrue(ignoredOverrideConfiguration.shouldUseRealClient)

        let fallbackClient = WritingAIClientFactory.makeDefaultClient(
            configuration: WritingAIConfiguration.configuration(from: [:])
        )

        XCTAssertTrue(fallbackClient is StubWritingAIClient)
    }

    func testBackendGatewayConfigurationUsesBundleValuesAndFactorySelectsBackendClientByDefault() async throws {
        let configuration = BackendGatewayConfiguration.configuration(
            from: [
                "VIBEWRITE_BACKEND_DEFAULT_MODE": "real",
                "VIBEWRITE_BACKEND_BASE_URL": "http://127.0.0.1:8080",
                "CFBundleShortVersionString": "3.2.1",
                "CFBundleVersion": "321"
            ]
        )

        XCTAssertEqual(configuration.mode, .real)
        XCTAssertEqual(configuration.baseURL.absoluteString, "http://127.0.0.1:8080")
        XCTAssertEqual(configuration.appVersion, "3.2.1 321")
        XCTAssertEqual(configuration.platform, "macOS")
        XCTAssertFalse(configuration.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let tempStoreURL = try makeBackendGatewayTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: tempStoreURL.deletingLastPathComponent())
        }

        let backendClient = BackendGatewayClientFactory.makeDefaultClient(
            configuration: configuration,
            identityStore: BackendGatewayIdentityStore(storageURL: tempStoreURL)
        )
        XCTAssertTrue(backendClient is BackendWritingAIClient)

        let stubConfiguration = BackendGatewayConfiguration.configuration(
            from: [:],
            environment: ["VIBEWRITE_BACKEND_MODE": "stub"]
        )
        let stubClient = BackendGatewayClientFactory.makeDefaultClient(configuration: stubConfiguration)
        XCTAssertTrue(stubClient is StubWritingAIClient)
    }

    func testBackendGatewayIdentityStorePersistsInstallationIdAndDeviceToken() async throws {
        let storageURL = try makeBackendGatewayTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let store = BackendGatewayIdentityStore(storageURL: storageURL)
        let initialSnapshot = await store.snapshotValue()

        XCTAssertEqual(initialSnapshot.schemaVersion, 1)
        XCTAssertFalse(initialSnapshot.installationId.isEmpty)
        XCTAssertNil(initialSnapshot.deviceToken)

        await store.updateDeviceToken("device-token-123")

        let updatedSnapshot = await store.snapshotValue()
        XCTAssertEqual(updatedSnapshot.installationId, initialSnapshot.installationId)
        XCTAssertEqual(updatedSnapshot.deviceToken, "device-token-123")

        let reopenedStore = BackendGatewayIdentityStore(storageURL: storageURL)
        let reopenedSnapshot = await reopenedStore.snapshotValue()
        XCTAssertEqual(reopenedSnapshot.installationId, initialSnapshot.installationId)
        XCTAssertEqual(reopenedSnapshot.deviceToken, "device-token-123")
    }

    func testBackendGatewayClientBootstrapsAndCachesDeviceToken() async throws {
        let storageURL = try makeBackendGatewayTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let identityStore = BackendGatewayIdentityStore(storageURL: storageURL)
        let requestsLock = NSLock()
        var recordedPaths: [String] = []
        var bootstrapCount = 0
        var writeCount = 0
        let prompt = "写一篇关于成年人孤独感的公众号文章"
        let project = WritingProject.quickStart(
            prompt: prompt,
            mode: .collaboration,
            automationKey: "gateway.cache.demo"
        )
        let request = WritingAIRequest(
            action: .startDraft,
            project: project.aiSnapshot,
            userMessage: prompt,
            selectionText: nil
        )

        let session = makeAnthropicMockSession { request in
            requestsLock.lock()
            defer { requestsLock.unlock() }

            recordedPaths.append(request.url?.path ?? "")

            switch request.url?.path {
            case "/v3/client/bootstrap":
                bootstrapCount += 1
                let token = bootstrapCount == 1 ? "device-token-1" : "device-token-2"
                let body = try JSONEncoder().encode(
                    BackendGatewayBootstrapResponseEnvelope(
                        deviceToken: token,
                        deviceStatus: "active",
                        quotaSummary: .init(dailyLimit: 50, weeklyLimit: 200)
                    )
                )
                return (self.makeHTTPResponse(statusCode: 200), body)

            case "/v3/writes/start":
                writeCount += 1
                let envelope = try self.decodeBackendGatewayWriteEnvelope(from: request)
                XCTAssertEqual(envelope.deviceToken, "device-token-1")
                let backendRequest = self.makeBackendGatewayWritingRequest(from: envelope)
                let response = WritingProjectResponseBuilder.response(
                    for: backendRequest,
                    documentText: MockWritingEngine.streamedDocumentText(for: backendRequest),
                    metadata: MockWritingEngine.completionMetadata(for: backendRequest)
                )
                let body = try JSONEncoder().encode(response)
                return (self.makeHTTPResponse(statusCode: 200), body)

            default:
                XCTFail("Unexpected backend gateway request path \(request.url?.path ?? "nil")")
                return (self.makeHTTPResponse(statusCode: 500), Data())
            }
        }

        let client = BackendWritingAIClient(
            configuration: BackendGatewayConfiguration.configuration(
                from: [
                    "VIBEWRITE_BACKEND_DEFAULT_MODE": "real",
                    "VIBEWRITE_BACKEND_BASE_URL": "http://127.0.0.1:8080"
                ]
            ),
            identityStore: identityStore,
            session: session
        )

        let firstResponse = try await client.generateResponse(for: request)
        XCTAssertFalse(firstResponse.documentText.isEmpty)

        let secondResponse = try await client.generateResponse(for: request)
        XCTAssertFalse(secondResponse.documentText.isEmpty)
        XCTAssertEqual(firstResponse.documentText, secondResponse.documentText)

        let snapshot = await identityStore.snapshotValue()
        XCTAssertEqual(snapshot.deviceToken, "device-token-1")
        XCTAssertEqual(bootstrapCount, 1)
        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(recordedPaths, ["/v3/client/bootstrap", "/v3/writes/start", "/v3/writes/start"])
    }

    func testBackendGatewayClientRetriesBootstrapAfterUnauthorized() async throws {
        let storageURL = try makeBackendGatewayTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let identityStore = BackendGatewayIdentityStore(storageURL: storageURL)
        let requestsLock = NSLock()
        var recordedPaths: [String] = []
        var bootstrapCount = 0
        var writeCount = 0
        let prompt = "写一篇关于成年人孤独感的公众号文章"
        let project = WritingProject.quickStart(
            prompt: prompt,
            mode: .collaboration,
            automationKey: "gateway.retry.demo"
        )
        let request = WritingAIRequest(
            action: .startDraft,
            project: project.aiSnapshot,
            userMessage: prompt,
            selectionText: nil
        )

        let session = makeAnthropicMockSession { request in
            requestsLock.lock()
            defer { requestsLock.unlock() }

            recordedPaths.append(request.url?.path ?? "")

            switch request.url?.path {
            case "/v3/client/bootstrap":
                bootstrapCount += 1
                let token = bootstrapCount == 1 ? "device-token-1" : "device-token-2"
                let body = try JSONEncoder().encode(
                    BackendGatewayBootstrapResponseEnvelope(
                        deviceToken: token,
                        deviceStatus: "active",
                        quotaSummary: .init(dailyLimit: 50, weeklyLimit: 200)
                    )
                )
                return (self.makeHTTPResponse(statusCode: 200), body)

            case "/v3/writes/start":
                writeCount += 1
                let envelope = try self.decodeBackendGatewayWriteEnvelope(from: request)
                if writeCount == 1 {
                    XCTAssertEqual(envelope.deviceToken, "device-token-1")
                    return (self.makeHTTPResponse(statusCode: 401), Data())
                }

                XCTAssertEqual(envelope.deviceToken, "device-token-2")
                let backendRequest = self.makeBackendGatewayWritingRequest(from: envelope)
                let response = WritingProjectResponseBuilder.response(
                    for: backendRequest,
                    documentText: MockWritingEngine.streamedDocumentText(for: backendRequest),
                    metadata: MockWritingEngine.completionMetadata(for: backendRequest)
                )
                let body = try JSONEncoder().encode(response)
                return (self.makeHTTPResponse(statusCode: 200), body)

            default:
                XCTFail("Unexpected backend gateway request path \(request.url?.path ?? "nil")")
                return (self.makeHTTPResponse(statusCode: 500), Data())
            }
        }

        let client = BackendWritingAIClient(
            configuration: BackendGatewayConfiguration.configuration(
                from: [
                    "VIBEWRITE_BACKEND_DEFAULT_MODE": "real",
                    "VIBEWRITE_BACKEND_BASE_URL": "http://127.0.0.1:8080"
                ]
            ),
            identityStore: identityStore,
            session: session
        )

        let response = try await client.generateResponse(for: request)
        XCTAssertFalse(response.documentText.isEmpty)

        let snapshot = await identityStore.snapshotValue()
        XCTAssertEqual(snapshot.deviceToken, "device-token-2")
        XCTAssertEqual(bootstrapCount, 2)
        XCTAssertEqual(writeCount, 2)
        XCTAssertEqual(recordedPaths, ["/v3/client/bootstrap", "/v3/writes/start", "/v3/client/bootstrap", "/v3/writes/start"])
    }

    func testBackendGatewayClientMapsNetworkUnavailableErrors() async throws {
        let storageURL = try makeBackendGatewayTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let identityStore = BackendGatewayIdentityStore(storageURL: storageURL)
        let session = makeAnthropicMockSession { _ in
            throw URLError(.notConnectedToInternet)
        }

        let client = BackendWritingAIClient(
            configuration: BackendGatewayConfiguration.configuration(
                from: [
                    "VIBEWRITE_BACKEND_DEFAULT_MODE": "real",
                    "VIBEWRITE_BACKEND_BASE_URL": "http://127.0.0.1:8080"
                ]
            ),
            identityStore: identityStore,
            session: session
        )

        let prompt = "写一篇关于成年人孤独感的公众号文章"
        let project = WritingProject.quickStart(
            prompt: prompt,
            mode: .collaboration,
            automationKey: "gateway.offline.demo"
        )
        let request = WritingAIRequest(
            action: .startDraft,
            project: project.aiSnapshot,
            userMessage: prompt,
            selectionText: nil
        )

        do {
            _ = try await client.generateResponse(for: request)
            XCTFail("Expected the backend gateway client to map the network failure")
        } catch let error as WritingAIClientError {
            switch error {
            case .networkUnavailable(let message):
                XCTAssertTrue(message.contains("后端"))
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStreamingConfigurationUsesBundleValuesAndEnvironmentOverrides() {
        let configuration = WritingStreamingConfiguration.configuration(from: [
            "VIBEWRITE_STREAMING_FRAME_INTERVAL_MS": "20",
            "VIBEWRITE_STREAMING_CHARACTERS_PER_SECOND": "480",
            "VIBEWRITE_STREAMING_INITIAL_BURST_CHARACTERS": "24",
            "VIBEWRITE_STREAMING_MINIMUM_CHARACTERS_PER_TICK": "3",
            "VIBEWRITE_STREAMING_MAXIMUM_CHARACTERS_PER_TICK": "15"
        ])

        XCTAssertEqual(configuration.frameInterval, 0.02, accuracy: 0.0001)
        XCTAssertEqual(configuration.charactersPerSecond, 480)
        XCTAssertEqual(configuration.initialBurstCharacters, 24)
        XCTAssertEqual(configuration.minimumCharactersPerTick, 3)
        XCTAssertEqual(configuration.maximumCharactersPerTick, 15)
        XCTAssertEqual(configuration.charactersPerTickBudget, 9)

        let overriddenConfiguration = WritingStreamingConfiguration.configuration(
            from: [
                "VIBEWRITE_STREAMING_FRAME_INTERVAL_MS": "20",
                "VIBEWRITE_STREAMING_CHARACTERS_PER_SECOND": "480"
            ],
            environment: [
                "VIBEWRITE_STREAMING_CHARACTERS_PER_SECOND": "900"
            ]
        )

        XCTAssertEqual(overriddenConfiguration.charactersPerSecond, 900)
    }

    func testPromptBuilderSeparatesProseAndMetadataPrompts() {
        let prompt = "写一篇关于成年人孤独感的公众号文章"
        let project = WritingProject.quickStart(
            prompt: prompt,
            mode: .discussion,
            automationKey: "project.prompt.dedup"
        )
        let request = WritingAIRequest(
            action: .startDraft,
            project: project.aiSnapshot,
            userMessage: prompt,
            selectionText: nil
        )

        let messages = WritingAIPromptBuilder().messages(
            for: request,
            provider: "minimax",
            model: "MiniMax-M2.5-highspeed"
        )

        let systemPrompt = messages.first?.content ?? ""
        let userPrompt = messages.last?.content ?? ""
        XCTAssertTrue(systemPrompt.contains("Output only prose text for the requested action"))
        XCTAssertFalse(systemPrompt.contains("[[VIBEWRITE_METADATA]]"))
        XCTAssertFalse(systemPrompt.contains("summary, nextFocus, suggestionChips"))
        XCTAssertFalse(systemPrompt.contains("A response is incomplete until the metadata block is present."))
        XCTAssertFalse(systemPrompt.contains("Every response must end with exactly one metadata block."))
        XCTAssertTrue(userPrompt.contains("Action: startDraft"))
        XCTAssertTrue(userPrompt.contains("User message: \(prompt)"))
        XCTAssertFalse(userPrompt.contains("[[VIBEWRITE_METADATA]]"))
        XCTAssertFalse(userPrompt.contains("Required output shape:"))
        XCTAssertFalse(userPrompt.contains("exactly one JSON object with summary, nextFocus, and suggestionChips"))
        XCTAssertFalse(userPrompt.contains("exactly 3 concise suggestion chips"))
        XCTAssertFalse(userPrompt.contains("assistantMessage"))
        XCTAssertFalse(userPrompt.contains("Respond with only the writing text"))

        let metadataRequest = WritingAIRequest(
            action: .startDraft,
            project: project.aiSnapshot,
            userMessage: prompt,
            selectionText: nil,
            kind: .metadata
        )
        let metadataMessages = WritingAIPromptBuilder().messages(
            for: metadataRequest,
            provider: "minimax",
            model: "MiniMax-M2.5-highspeed",
            metadataRoute: .current
        )

        let metadataSystemPrompt = metadataMessages.first?.content ?? ""
        let metadataUserPrompt = metadataMessages.last?.content ?? ""
        XCTAssertTrue(metadataSystemPrompt.contains("metadata-only response builder"))
        XCTAssertTrue(metadataSystemPrompt.contains("emit_metadata"))
        XCTAssertTrue(metadataSystemPrompt.contains("only valid response is a single `emit_metadata` tool call"))
        XCTAssertTrue(metadataSystemPrompt.contains("Return suggestionChips as the primary output"))
        XCTAssertTrue(metadataSystemPrompt.contains("Keep the global synopsis short and stable"))
        XCTAssertFalse(metadataSystemPrompt.contains("[[VIBEWRITE_METADATA]]"))
        XCTAssertTrue(metadataUserPrompt.contains("Action: startDraft metadata"))
        XCTAssertTrue(metadataUserPrompt.contains("Completed prose:"))
        XCTAssertTrue(metadataUserPrompt.contains("Use the `emit_metadata` tool"))
        XCTAssertTrue(metadataUserPrompt.contains("Return exactly one `emit_metadata` tool call and nothing else."))
        XCTAssertTrue(metadataUserPrompt.contains("Make suggestionChips the most concrete part of the response; keep globalSynopsis short and stable."))
        XCTAssertTrue(metadataUserPrompt.contains("Return exactly 3 concise suggestion chips."))

        let textSchemaMetadataMessages = WritingAIPromptBuilder().messages(
            for: metadataRequest,
            provider: "minimax",
            model: "MiniMax-Text-01",
            metadataRoute: .text01JsonSchema
        )
        let textSchemaSystemPrompt = textSchemaMetadataMessages.first?.content ?? ""
        let textSchemaUserPrompt = textSchemaMetadataMessages.last?.content ?? ""
        XCTAssertTrue(textSchemaSystemPrompt.contains("metadata-only response builder"))
        XCTAssertTrue(textSchemaSystemPrompt.contains("Return only the metadata for the completed prose"))
        XCTAssertTrue(textSchemaSystemPrompt.contains("Return suggestionChips as the primary output"))
        XCTAssertTrue(textSchemaSystemPrompt.contains("Keep the global synopsis short and stable"))
        XCTAssertFalse(textSchemaSystemPrompt.contains("emit_metadata"))
        XCTAssertTrue(textSchemaUserPrompt.contains("Return localSummary, globalSynopsis, nextFocus, and suggestionChips only."))
        XCTAssertTrue(textSchemaUserPrompt.contains("Make suggestionChips the most concrete part of the response; keep globalSynopsis short and stable."))
        XCTAssertFalse(textSchemaUserPrompt.contains("Use the `emit_metadata` tool"))
    }

    func testContinueWritingPromptRequestsConcreteSuggestionChips() {
        let headParagraphs = (1...30).map { index in
            "前文第\(index)段用来铺陈背景和细节，保证总长度足够长以触发尾部截取窗口，并且让更早的内容必须被裁掉。"
        }
        let tailParagraphs = [
            "尾部第一段需要把节奏慢下来，并留下余味。",
            "尾部第二段要真正作为继续写的起点。"
        ]
        let documentText = (headParagraphs + tailParagraphs).joined(separator: "\n\n")
        let context = ProjectContext(
            intentSummary: "当前要把结尾收紧，并保持人物气口一致。",
            styleConstraints: ["克制", "平静", "非鸡汤"],
            currentGoal: "继续推进结尾",
            recentDecisions: ["不重写前文", "保留余味"],
            workingMemory: ["人物已经进入收束阶段", "后面只需要再往前推一点"],
            nextFocus: "补一段收束"
        )
        let project = WritingProject(
            title: "续写测试",
            prompt: "写一篇关于成年人孤独感的公众号文章",
            mode: .collaboration,
            localSummary: "给人看的局部摘要可以保留原样",
            globalSynopsis: "给模型看的全局摘要要更短、更偏状态",
            context: context,
            conversation: [],
            documentText: documentText,
            suggestionChips: ["继续写", "编辑这段", "补一段"]
        ).aiSnapshot
        let request = WritingAIRequest(
            action: .continueWriting,
            project: project,
            userMessage: "继续往下写",
            selectionText: nil
        )

        let messages = WritingAIPromptBuilder().messages(
            for: request,
            provider: "minimax",
            model: "MiniMax-M2.5-highspeed"
        )

        let systemPrompt = messages.first?.content ?? ""
        let userPrompt = messages.last?.content ?? ""

        XCTAssertTrue(systemPrompt.contains("Output only prose text for the requested action"))
        XCTAssertFalse(systemPrompt.contains("[[VIBEWRITE_METADATA]]"))
        XCTAssertTrue(systemPrompt.contains("Advance the passage only a little; do not turn this into a full ending or a fully closed paragraph."))
        XCTAssertTrue(systemPrompt.contains("Leave a small amount of forward momentum for the next step."))
        XCTAssertTrue(userPrompt.contains("Global synopsis:"))
        XCTAssertTrue(userPrompt.contains("Document tail:"))
        XCTAssertTrue(userPrompt.contains("给模型看的全局摘要要更短、更偏状态"))
        XCTAssertTrue(userPrompt.contains("尾部第二段要真正作为继续写的起点。"))
        XCTAssertTrue(userPrompt.contains("Do not restart from the beginning of the article."))
        XCTAssertTrue(userPrompt.contains("Advance the passage only a little; do not turn this into a full ending or a fully closed paragraph."))
        XCTAssertTrue(userPrompt.contains("Leave a small amount of forward momentum for the next step."))
        XCTAssertTrue(userPrompt.contains("Keep the continuation brief so the next move still feels natural."))
        XCTAssertFalse(userPrompt.contains("Project state:"))
        XCTAssertFalse(userPrompt.contains("Current goal:"))
        XCTAssertFalse(userPrompt.contains("Next focus:"))
        XCTAssertFalse(userPrompt.contains("Style constraints:"))
        XCTAssertFalse(userPrompt.contains("Current document:"))
        XCTAssertFalse(userPrompt.contains("[[VIBEWRITE_METADATA]]"))
        XCTAssertFalse(userPrompt.contains("Required output shape:"))
        XCTAssertFalse(userPrompt.contains("exactly one JSON object with localSummary, globalSynopsis, nextFocus, and suggestionChips"))
        XCTAssertFalse(userPrompt.contains("Respond with only the writing text"))

        let metadataRequest = WritingAIRequest(
            action: .continueWriting,
            project: project,
            userMessage: "继续往下写",
            selectionText: nil,
            kind: .metadata
        )
        let metadataMessages = WritingAIPromptBuilder().messages(
            for: metadataRequest,
            provider: "minimax",
            model: "MiniMax-M2.5-highspeed",
            metadataRoute: .current
        )
        let metadataSystemPrompt = metadataMessages.first?.content ?? ""
        let metadataUserPrompt = metadataMessages.last?.content ?? ""
        XCTAssertTrue(metadataSystemPrompt.contains("metadata-only response builder"))
        XCTAssertTrue(metadataSystemPrompt.contains("Describe the completed正文 as the local summary"))
        XCTAssertTrue(metadataUserPrompt.contains("Action: continueWriting metadata"))
        XCTAssertTrue(metadataUserPrompt.contains("Completed prose:"))
        XCTAssertTrue(metadataUserPrompt.contains("Current global synopsis:"))
        XCTAssertTrue(metadataUserPrompt.contains("Use the `emit_metadata` tool"))
        XCTAssertTrue(metadataUserPrompt.contains("Return exactly 3 concise suggestion chips."))
    }

    func testRemoteClientMetadataUsesStructuredToolOutput() async throws {
        let configuration = WritingAIConfiguration.configuration(from: [
            "VIBEWRITE_AI_DEFAULT_MODE": "real",
            "VIBEWRITE_AI_PROVIDER": "minimax",
            "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
            "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
            "MINIMAX_METADATA_ROUTE": "current",
            "MINIMAX_API_KEY": "bundle-key-123"
        ])

        let session = makeAnthropicMockSession { request in
            let body = try XCTUnwrap(self.requestBodyData(from: request))
            let payload = try JSONDecoder().decode(AnthropicRequestEnvelope.self, from: body)

            XCTAssertFalse(payload.stream)
            XCTAssertEqual(payload.model, "MiniMax-M2.5-highspeed")
            XCTAssertEqual(payload.tools?.first?.name, "emit_metadata")
            XCTAssertEqual(payload.toolChoice?.type, "tool")
            XCTAssertEqual(payload.toolChoice?.name, "emit_metadata")
            XCTAssertEqual(payload.tools?.first?.inputSchema.required, ["localSummary", "globalSynopsis", "nextFocus", "suggestionChips"])
            XCTAssertEqual(payload.tools?.first?.inputSchema.properties.suggestionChips.minItems, 3)
            XCTAssertEqual(payload.tools?.first?.inputSchema.properties.suggestionChips.maxItems, 3)
            XCTAssertFalse(payload.system.contains("[[VIBEWRITE_METADATA]]"))
            XCTAssertTrue(payload.system.contains("emit_metadata"))

            let response = """
            {
              "content": [
                {
                  "type": "tool_use",
                  "id": "toolu_01",
                  "name": "emit_metadata",
                  "input": {
                    "localSummary": "已生成开头",
                    "globalSynopsis": "已生成总览",
                    "nextFocus": "继续推进第一段",
                    "suggestionChips": ["继续写", "编辑这段", "补一段"]
                  }
                }
              ]
            }
            """

            return (
                self.makeHTTPResponse(statusCode: 200, headerFields: ["Content-Type": "application/json"]),
                response.data(using: .utf8)!
            )
        }

        let client = RemoteWritingAIClient(configuration: configuration, session: session)
        let project = WritingProject(
            title: "结构化建议测试",
            prompt: "写一篇关于成年人孤独感的公众号文章",
            mode: .collaboration,
            localSummary: "给人看的局部摘要可以保留原样",
            globalSynopsis: "给模型看的全局摘要要更短、更偏状态",
            context: ProjectContext(
                intentSummary: "当前要把结尾收紧，并保持人物气口一致。",
                styleConstraints: ["克制", "平静", "非鸡汤"],
                currentGoal: "继续推进结尾",
                recentDecisions: ["不重写前文", "保留余味"],
                workingMemory: ["人物已经进入收束阶段", "后面只需要再往前推一点"],
                nextFocus: "补一段收束"
            ),
            conversation: [],
            documentText: "前文第一段。\n\n前文第二段。",
            suggestionChips: ["继续写", "编辑这段", "补一段"]
        ).aiSnapshot
        let request = WritingAIRequest(
            action: .continueWriting,
            project: project,
            userMessage: "继续往下写",
            selectionText: nil,
            kind: .metadata
        )

        let response = try await client.generateResponse(for: request)

        XCTAssertEqual(response.documentText, request.project.documentText)
        XCTAssertEqual(response.localSummary, "已生成开头")
        XCTAssertEqual(response.globalSynopsis, "已生成总览")
        XCTAssertEqual(response.nextFocus, "继续推进第一段")
        XCTAssertEqual(response.suggestionChips, ["继续写", "编辑这段", "补一段"])
    }

    func testRemoteClientUsesWiderMaxTokensAndDocumentTailForContinueWriting() async throws {
        let configuration = WritingAIConfiguration.configuration(from: [
            "VIBEWRITE_AI_DEFAULT_MODE": "real",
            "VIBEWRITE_AI_PROVIDER": "minimax",
            "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
            "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
            "MINIMAX_METADATA_ROUTE": "current",
            "MINIMAX_API_KEY": "bundle-key-123"
        ])

        let session = makeAnthropicMockSession { request in
            let body = try XCTUnwrap(self.requestBodyData(from: request))
            let payload = try JSONDecoder().decode(AnthropicRequestEnvelope.self, from: body)

            XCTAssertEqual(payload.maxTokens, 1536)
            XCTAssertEqual(payload.model, "MiniMax-M2.5-highspeed")
            XCTAssertTrue(payload.system.contains("Output only prose text for the requested action"))
            XCTAssertFalse(payload.messages.first?.content.first?.text.contains("Project state:") ?? true)
            XCTAssertFalse(payload.messages.first?.content.first?.text.contains("Current goal:") ?? true)
            XCTAssertFalse(payload.messages.first?.content.first?.text.contains("Next focus:") ?? true)
            XCTAssertFalse(payload.messages.first?.content.first?.text.contains("Style constraints:") ?? true)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Document tail:") ?? false)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Advance the passage only a little; do not turn this into a full ending or a fully closed paragraph.") ?? false)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Leave a small amount of forward momentum for the next step.") ?? false)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Keep the continuation brief so the next move still feels natural.") ?? false)
            XCTAssertFalse(payload.system.contains("[[VIBEWRITE_METADATA]]"))
            XCTAssertFalse(payload.messages.first?.content.first?.text.contains("Required output shape:") ?? true)

            let response = """
            event: message_start
            data: {"type":"message_start"}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"续写正文。"}}

            event: message_stop
            data: {"type":"message_stop"}
            """

            return (
                self.makeHTTPResponse(
                    statusCode: 200,
                    headerFields: ["Content-Type": "text/event-stream"]
                ),
                response.data(using: .utf8)!
            )
        }

        let client = RemoteWritingAIClient(configuration: configuration, session: session)
        let project = WritingProject(
            title: "续写测试",
            prompt: "写一篇关于成年人孤独感的公众号文章",
            mode: .collaboration,
            localSummary: "给人看的局部摘要可以保留原样",
            globalSynopsis: "给模型看的全局摘要要更短、更偏状态",
            context: ProjectContext(
                intentSummary: "当前要把结尾收紧，并保持人物气口一致。",
                styleConstraints: ["克制", "平静", "非鸡汤"],
                currentGoal: "继续推进结尾",
                recentDecisions: ["不重写前文", "保留余味"],
                workingMemory: ["人物已经进入收束阶段", "后面只需要再往前推一点"],
                nextFocus: "补一段收束"
            ),
            conversation: [],
            documentText: "前文第一段。\n\n前文第二段。",
            suggestionChips: ["继续写", "编辑这段", "补一段"]
        ).aiSnapshot
        let request = WritingAIRequest(
            action: .continueWriting,
            project: project,
            userMessage: "继续往下写",
            selectionText: nil
        )

        var finalResponse: WritingAIResponse?
        for try await event in client.streamResponse(for: request) {
            if case .completed(let response) = event {
                finalResponse = response
            }
        }

        XCTAssertEqual(finalResponse?.documentText, "前文第一段。\n\n前文第二段。续写正文。")
        XCTAssertTrue(finalResponse?.localSummary.isEmpty ?? false)
        XCTAssertTrue(finalResponse?.globalSynopsis.isEmpty ?? false)
        XCTAssertTrue(finalResponse?.nextFocus.isEmpty ?? false)
        XCTAssertTrue(finalResponse?.suggestionChips.isEmpty ?? false)
    }

    func testRemoteClientUsesWiderMaxTokensForStartDraft() async throws {
        let configuration = WritingAIConfiguration.configuration(from: [
            "VIBEWRITE_AI_DEFAULT_MODE": "real",
            "VIBEWRITE_AI_PROVIDER": "minimax",
            "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
            "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
            "MINIMAX_METADATA_ROUTE": "current",
            "MINIMAX_API_KEY": "bundle-key-123"
        ])

        let session = makeAnthropicMockSession { request in
            let body = try XCTUnwrap(self.requestBodyData(from: request))
            let payload = try JSONDecoder().decode(AnthropicRequestEnvelope.self, from: body)

            XCTAssertEqual(payload.maxTokens, 2048)
            XCTAssertEqual(payload.model, "MiniMax-M2.5-highspeed")
            XCTAssertTrue(payload.system.contains("Output only prose text for the requested action"))
            XCTAssertFalse(payload.system.contains("[[VIBEWRITE_METADATA]]"))
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Action: startDraft") ?? false)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("User message: 写一篇关于成年人孤独感的公众号文章") ?? false)

            let response = """
            event: message_start
            data: {"type":"message_start"}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"成年人真正感到孤独的时候，未必是在深夜。"}}

            event: message_stop
            data: {"type":"message_stop"}
            """

            return (
                self.makeHTTPResponse(
                    statusCode: 200,
                    headerFields: ["Content-Type": "text/event-stream"]
                ),
                response.data(using: .utf8)!
            )
        }

        let client = RemoteWritingAIClient(configuration: configuration, session: session)
        let request = WritingAIRequest(
            action: .startDraft,
            project: WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot,
            userMessage: "写一篇关于成年人孤独感的公众号文章",
            selectionText: nil
        )

        var finalResponse: WritingAIResponse?
        for try await event in client.streamResponse(for: request) {
            if case .completed(let response) = event {
                finalResponse = response
            }
        }

        XCTAssertEqual(finalResponse?.documentText, "成年人真正感到孤独的时候，未必是在深夜。")
        XCTAssertTrue(finalResponse?.localSummary.isEmpty ?? false)
        XCTAssertTrue(finalResponse?.globalSynopsis.isEmpty ?? false)
        XCTAssertTrue(finalResponse?.nextFocus.isEmpty ?? false)
        XCTAssertTrue(finalResponse?.suggestionChips.isEmpty ?? false)
    }

    func testRemoteClientMetadataCurrentRouteUsesStructuredToolOutput() async throws {
        let configuration = WritingAIConfiguration.configuration(from: [
            "VIBEWRITE_AI_DEFAULT_MODE": "real",
            "VIBEWRITE_AI_PROVIDER": "minimax",
            "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
            "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
            "MINIMAX_METADATA_ROUTE": "current",
            "MINIMAX_API_KEY": "bundle-key-123"
        ])

        let session = makeAnthropicMockSession { request in
            let body = try XCTUnwrap(self.requestBodyData(from: request))
            let payload = try JSONDecoder().decode(AnthropicRequestEnvelope.self, from: body)

            XCTAssertFalse(payload.stream)
            XCTAssertEqual(payload.model, "MiniMax-M2.5-highspeed")
            XCTAssertEqual(payload.tools?.first?.name, "emit_metadata")
            XCTAssertEqual(payload.toolChoice?.type, "tool")
            XCTAssertEqual(payload.toolChoice?.name, "emit_metadata")
            XCTAssertEqual(payload.tools?.first?.inputSchema.required, ["localSummary", "globalSynopsis", "nextFocus", "suggestionChips"])
            XCTAssertEqual(payload.tools?.first?.inputSchema.properties.suggestionChips.minItems, 3)
            XCTAssertEqual(payload.tools?.first?.inputSchema.properties.suggestionChips.maxItems, 3)
            XCTAssertTrue(payload.system.contains("metadata-only response builder"))
            XCTAssertFalse(payload.system.contains("[[VIBEWRITE_METADATA]]"))
            XCTAssertTrue(payload.system.contains("emit_metadata"))
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Action: startDraft metadata") ?? false)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Completed prose:") ?? false)

            let response = """
            {
              "content": [
                {
                  "type": "tool_use",
                  "id": "toolu_01",
                  "name": "emit_metadata",
                  "input": {
                    "localSummary": "已生成开头",
                    "globalSynopsis": "已生成总览",
                    "nextFocus": "继续推进第一段",
                    "suggestionChips": ["继续写", "编辑这段", "补一段"]
                  }
                }
              ]
            }
            """

            return (
                self.makeHTTPResponse(statusCode: 200, headerFields: ["Content-Type": "application/json"]),
                response.data(using: .utf8)!
            )
        }

        let client = RemoteWritingAIClient(configuration: configuration, session: session)
        let request = WritingAIRequest(
            action: .startDraft,
            project: WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot,
            userMessage: "写一篇关于成年人孤独感的公众号文章",
            selectionText: nil,
            kind: .metadata
        )

        var finalResponse: WritingAIResponse?
        for try await event in client.streamResponse(for: request) {
            if case .completed(let response) = event {
                finalResponse = response
            }
        }

        XCTAssertEqual(finalResponse?.localSummary, "已生成开头")
        XCTAssertEqual(finalResponse?.globalSynopsis, "已生成总览")
        XCTAssertEqual(finalResponse?.nextFocus, "继续推进第一段")
        XCTAssertEqual(finalResponse?.suggestionChips, ["继续写", "编辑这段", "补一段"])
        XCTAssertEqual(finalResponse?.documentText, request.project.documentText)
    }

    func testRemoteClientMetadataTextRouteUsesJsonSchemaOutput() async throws {
        let configuration = WritingAIConfiguration.configuration(from: [
            "VIBEWRITE_AI_DEFAULT_MODE": "real",
            "VIBEWRITE_AI_PROVIDER": "minimax",
            "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
            "MINIMAX_TEXT_BASE_URL": "https://api.minimaxi.com",
            "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
            "MINIMAX_METADATA_ROUTE": "text01_json_schema",
            "MINIMAX_API_KEY": "bundle-key-123"
        ])

        let session = makeAnthropicMockSession { request in
            let body = try XCTUnwrap(self.requestBodyData(from: request))
            let payload = try JSONDecoder().decode(MiniMaxTextRequestEnvelope.self, from: body)

            XCTAssertEqual(request.url?.absoluteString, "https://api.minimaxi.com/v1/text/chatcompletion_v2")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bundle-key-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(payload.model, "MiniMax-Text-01")
            XCTAssertFalse(payload.stream)
            XCTAssertEqual(payload.maxCompletionTokens, 512)
            XCTAssertEqual(payload.temperature, 0.1, accuracy: 0.0001)
            XCTAssertEqual(payload.responseFormat.type, "json_schema")
            XCTAssertEqual(payload.responseFormat.jsonSchema.name, "writing_ai_metadata")
            XCTAssertTrue(payload.responseFormat.jsonSchema.strict)
            XCTAssertEqual(payload.responseFormat.jsonSchema.schema.required, ["localSummary", "globalSynopsis", "nextFocus", "suggestionChips"])
            XCTAssertEqual(payload.messages.count, 2)
            XCTAssertEqual(payload.messages.first?.role, "system")
            XCTAssertEqual(payload.messages.first?.name, "MiniMax AI")
            XCTAssertTrue(payload.messages.first?.content.contains("metadata-only response builder") ?? false)
            XCTAssertEqual(payload.messages.last?.role, "user")
            XCTAssertEqual(payload.messages.last?.name, "用户")
            XCTAssertTrue(payload.messages.last?.content.contains("Action: startDraft metadata") ?? false)
            XCTAssertTrue(payload.messages.last?.content.contains("Return localSummary, globalSynopsis, nextFocus, and suggestionChips only.") ?? false)
            XCTAssertFalse(payload.messages.last?.content.contains("emit_metadata") ?? true)

            let response = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\"localSummary\\":\\"已生成开头\\",\\"globalSynopsis\\":\\"已生成总览\\",\\"nextFocus\\":\\"继续推进第一段\\",\\"suggestionChips\\":[\\"继续写\\",\\"编辑这段\\",\\"补一段\\"]}"
                  }
                }
              ],
              "base_resp": {
                "status_code": 0,
                "status_msg": ""
              }
            }
            """

            return (
                self.makeHTTPResponse(statusCode: 200, headerFields: ["Content-Type": "application/json"]),
                response.data(using: .utf8)!
            )
        }

        let client = RemoteWritingAIClient(configuration: configuration, session: session)
        let request = WritingAIRequest(
            action: .startDraft,
            project: WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot,
            userMessage: "写一篇关于成年人孤独感的公众号文章",
            selectionText: nil,
            kind: .metadata
        )

        let finalResponse = try await client.generateResponse(for: request)

        XCTAssertEqual(finalResponse.documentText, request.project.documentText)
        XCTAssertEqual(finalResponse.localSummary, "已生成开头")
        XCTAssertEqual(finalResponse.globalSynopsis, "已生成总览")
        XCTAssertEqual(finalResponse.nextFocus, "继续推进第一段")
        XCTAssertEqual(finalResponse.suggestionChips, ["继续写", "编辑这段", "补一段"])
    }

    func testStreamingPreviewRendererStartsContinuationFromRevealOffset() async {
        let configuration = WritingStreamingConfiguration.configuration(
            from: [
                "VIBEWRITE_STREAMING_FRAME_INTERVAL_MS": "16",
                "VIBEWRITE_STREAMING_CHARACTERS_PER_SECOND": "120",
                "VIBEWRITE_STREAMING_INITIAL_BURST_CHARACTERS": "1",
                "VIBEWRITE_STREAMING_MINIMUM_CHARACTERS_PER_TICK": "1",
                "VIBEWRITE_STREAMING_MAXIMUM_CHARACTERS_PER_TICK": "1"
            ]
        )

        var renders: [String] = []
        let renderer = WritingStreamingPreviewRenderer(configuration: configuration) { renderedText in
            renders.append(renderedText)
        }

        renderer.updateTargetText("abcdef", revealFromCharacterCount: 4)
        renderer.markStreamCompleted()
        await renderer.waitForCompletion()

        XCTAssertEqual(renders.first, "abcde")
        XCTAssertEqual(renders.last, "abcdef")
    }

    func testStreamingPreviewRendererKeepsFinishingOneCharacterAtATime() async {
        let configuration = WritingStreamingConfiguration.configuration(
            from: [
                "VIBEWRITE_STREAMING_FRAME_INTERVAL_MS": "16",
                "VIBEWRITE_STREAMING_CHARACTERS_PER_SECOND": "60",
                "VIBEWRITE_STREAMING_INITIAL_BURST_CHARACTERS": "1",
                "VIBEWRITE_STREAMING_MINIMUM_CHARACTERS_PER_TICK": "1",
                "VIBEWRITE_STREAMING_MAXIMUM_CHARACTERS_PER_TICK": "1"
            ]
        )

        var renders: [String] = []
        let renderer = WritingStreamingPreviewRenderer(configuration: configuration) { renderedText in
            renders.append(renderedText)
        }

        renderer.updateTargetText("abcd")
        renderer.markStreamCompleted()
        await renderer.waitForCompletion()

        XCTAssertEqual(renders, ["a", "ab", "abc", "abcd"])
    }

    func testRemoteClientUsesAnthropicCompatibleRequestAndStreamsTextDeltas() async throws {
        let configuration = WritingAIConfiguration.configuration(from: [
            "VIBEWRITE_AI_DEFAULT_MODE": "real",
            "VIBEWRITE_AI_PROVIDER": "minimax",
            "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
            "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
            "MINIMAX_API_KEY": "bundle-key-123"
        ])

        let session = makeAnthropicMockSession { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.minimaxi.com/anthropic/v1/messages")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "bundle-key-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try XCTUnwrap(self.requestBodyData(from: request))
            let payload = try JSONDecoder().decode(AnthropicRequestEnvelope.self, from: body)

            XCTAssertEqual(payload.model, "MiniMax-M2.5-highspeed")
            XCTAssertTrue(payload.system.contains("Output only prose text for the requested action"))
            XCTAssertFalse(payload.system.contains("[[VIBEWRITE_METADATA]]"))
            XCTAssertEqual(payload.messages.count, 1)
            XCTAssertEqual(payload.messages.first?.role, "user")
            XCTAssertEqual(payload.messages.first?.content.first?.type, "text")
            XCTAssertEqual(payload.messages.first?.content.first?.text.contains("Action: startDraft"), true)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("User message: 写一篇关于成年人孤独感的公众号文章") ?? false)
            XCTAssertTrue(payload.stream)
            XCTAssertFalse(payload.messages.first?.content.first?.text.contains("[[VIBEWRITE_METADATA]]") ?? true)

            let response = """
            event: message_start
            data: {"type":"message_start"}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"成年人真正感到孤独的时候，未必是在深夜。"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"更多时候，是在一个很普通的傍晚。"}}

            event: message_stop
            data: {"type":"message_stop"}

            """

            return (
                self.makeHTTPResponse(
                    statusCode: 200,
                    headerFields: ["Content-Type": "text/event-stream"]
                ),
                response.data(using: .utf8)!
            )
        }

        let client = RemoteWritingAIClient(configuration: configuration, session: session)
        let request = WritingAIRequest(
            action: .startDraft,
            project: WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot,
            userMessage: "写一篇关于成年人孤独感的公众号文章",
            selectionText: nil
        )

        var deltas: [String] = []
        var finalResponse: WritingAIResponse?

        for try await event in client.streamResponse(for: request) {
            switch event {
            case .textDelta(let text):
                deltas.append(text)
            case .completed(let response):
                finalResponse = response
            }
        }

        XCTAssertFalse(deltas.isEmpty)
        XCTAssertEqual(
            deltas.joined().trimmingCharacters(in: .whitespacesAndNewlines),
            "成年人真正感到孤独的时候，未必是在深夜。更多时候，是在一个很普通的傍晚。"
        )
        XCTAssertEqual(finalResponse?.documentText, "成年人真正感到孤独的时候，未必是在深夜。更多时候，是在一个很普通的傍晚。")
        XCTAssertEqual(finalResponse?.mode, .collaboration)
        XCTAssertTrue(finalResponse?.localSummary.isEmpty ?? false)
        XCTAssertTrue(finalResponse?.globalSynopsis.isEmpty ?? false)
        XCTAssertTrue(finalResponse?.nextFocus.isEmpty ?? false)
        XCTAssertTrue(finalResponse?.suggestionChips.isEmpty ?? false)
        XCTAssertFalse(finalResponse?.assistantMessage.isEmpty ?? true)
    }

    func testResponseBuilderDoesNotInventMetadataWhenModelDoesNotReturnIt() {
        let project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot
        let request = WritingAIRequest(
            action: .continueWriting,
            project: project,
            userMessage: "继续往下写",
            selectionText: nil
        )

        let response = WritingProjectResponseBuilder.response(
            for: request,
            documentText: "新的正文",
            metadata: nil
        )

        XCTAssertEqual(response.localSummary, "")
        XCTAssertEqual(response.globalSynopsis, "")
        XCTAssertEqual(response.nextFocus, "")
        XCTAssertEqual(response.suggestionChips, [])
    }

    func testStubAIProducesStructuredDraftResponse() async throws {
        let request = WritingAIRequest(
            action: .startDraft,
            project: WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot,
            userMessage: "写一篇关于成年人孤独感的公众号文章",
            selectionText: nil
        )

        let response = try await StubWritingAIClient().generateResponse(for: request)

        XCTAssertFalse(response.documentText.isEmpty)
        XCTAssertFalse(response.assistantMessage.isEmpty)
        XCTAssertEqual(response.mode, .collaboration)
        XCTAssertTrue(response.suggestionChips.isEmpty)
    }

    func testStubAIStreamProducesIncrementalTextDeltas() async throws {
        let request = WritingAIRequest(
            action: .continueWriting,
            project: WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot,
            userMessage: "继续往下写",
            selectionText: nil
        )

        var deltas: [String] = []
        var finalResponse: WritingAIResponse?

        for try await event in StubWritingAIClient().streamResponse(for: request) {
            switch event {
            case .textDelta(let delta):
                deltas.append(delta)
            case .completed(let response):
                finalResponse = response
            }
        }

        XCTAssertGreaterThan(deltas.count, 1)
        XCTAssertFalse(deltas.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotNil(finalResponse)
        XCTAssertTrue(finalResponse?.documentText.hasPrefix(request.project.documentText) ?? false)
    }

    func testResponseDecoderParsesFencedJSONString() throws {
        let raw = """
        ```json
        {
          "assistantMessage": "我已经起草完了。",
          "documentText": "正文",
          "localSummary": "摘要",
          "globalSynopsis": "全局摘要",
          "intentSummary": "意图",
          "styleConstraints": ["克制"],
          "currentGoal": "目标",
          "recentDecisions": ["决策"],
          "workingMemory": ["记忆"],
          "nextFocus": "下一步",
          "suggestionChips": ["继续"],
          "mode": "collaboration"
        }
        ```
        """

        let response = try WritingAIResponseDecoder.decode(from: raw)

        XCTAssertEqual(response.documentText, "正文")
        XCTAssertEqual(response.mode, .collaboration)
        XCTAssertEqual(response.suggestionChips, ["继续"])
    }

    func testApplyingAIResponseUpdatesProjectContext() {
        var project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!
        let response = WritingAIResponse(
            assistantMessage: "继续推进",
            documentText: "新的正文",
            localSummary: "新的局部摘要",
            globalSynopsis: "新的全局摘要",
            intentSummary: "新的意图",
            styleConstraints: ["克制", "平静"],
            currentGoal: "新的目标",
            recentDecisions: ["新的决策"],
            workingMemory: ["新的记忆"],
            nextFocus: "新的下一步",
            suggestionChips: ["继续展开"],
            mode: .collaboration
        )

        project.apply(aiResponse: response, documentText: "新的正文")

        XCTAssertEqual(project.documentText, "新的正文")
        XCTAssertEqual(project.currentGoal, "新的目标")
        XCTAssertEqual(project.intentSummary, "新的意图")
        XCTAssertEqual(project.suggestionChips, ["继续展开"])
        XCTAssertEqual(project.mode, .collaboration)
        XCTAssertEqual(project.conversation.last?.text, "继续推进")
    }

    func testApplyingEditResponsePreservesExistingSuggestionChips() {
        var project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!
        let originalSuggestionChips = project.suggestionChips
        let response = WritingAIResponse(
            assistantMessage: "继续推进",
            documentText: "新的正文",
            localSummary: "新的局部摘要",
            globalSynopsis: "新的全局摘要",
            intentSummary: "新的意图",
            styleConstraints: ["克制", "平静"],
            currentGoal: "新的目标",
            recentDecisions: ["新的决策"],
            workingMemory: ["新的记忆"],
            nextFocus: "新的下一步",
            suggestionChips: ["编辑后建议 1", "编辑后建议 2"],
            mode: .collaboration
        )

        project.applyEditingResponse(response, documentText: "新的正文")

        XCTAssertEqual(project.documentText, "新的正文")
        XCTAssertEqual(project.currentGoal, "新的目标")
        XCTAssertEqual(project.intentSummary, "新的意图")
        XCTAssertEqual(project.suggestionChips, originalSuggestionChips)
        XCTAssertEqual(project.mode, .collaboration)
        XCTAssertEqual(project.conversation.last?.text, "继续推进")
    }

    func testStartDraftPromptBuilderKeepsUserMessageVisibleToModel() {
        let prompt = "写一篇关于成年人孤独感的公众号文章"
        let project = WritingProject.quickStart(
            prompt: prompt,
            mode: .discussion,
            automationKey: "project.prompt.dedup"
        )
        let request = WritingAIRequest(
            action: .startDraft,
            project: project.aiSnapshot,
            userMessage: prompt,
            selectionText: nil
        )

        let messages = WritingAIPromptBuilder().messages(
            for: request,
            provider: "minimax",
            model: "MiniMax-M2.5-highspeed"
        )

        let userPrompt = messages.last?.content ?? ""
        let occurrences = userPrompt.components(separatedBy: prompt).count - 1

        XCTAssertEqual(occurrences, 1)
        XCTAssertTrue(userPrompt.contains("User message: \(prompt)"))
    }

    func testRemoteClientMapsInvalidApiKeyToFriendlyConfigurationError() async throws {
        let configuration = WritingAIConfiguration.configuration(from: [
            "VIBEWRITE_AI_DEFAULT_MODE": "real",
            "VIBEWRITE_AI_PROVIDER": "minimax",
            "MINIMAX_BASE_URL": "https://example.com",
            "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
            "MINIMAX_API_KEY": "bundle-key-123"
        ])

        let session = makeMockSession(
            statusCode: 401,
            body: """
            {
              "error": {
                "message": "invalid api key (2049)"
              }
            }
            """.data(using: .utf8)!
        )

        let client = RemoteWritingAIClient(configuration: configuration, session: session)
        let request = WritingAIRequest(
            action: .startDraft,
            project: WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot,
            userMessage: "写一篇关于成年人孤独感的公众号文章",
            selectionText: nil
        )

        do {
            _ = try await client.generateResponse(for: request)
            XCTFail("Expected the client to reject the invalid key")
        } catch let error as WritingAIClientError {
            switch error {
            case .invalidConfiguration(let message):
                XCTAssertTrue(message.contains("API key 无效"))
                XCTAssertFalse(message.contains("2049"))
            default:
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeAnthropicMockSession(
        responseHandler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.responseHandler = responseHandler

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeMockSession(statusCode: Int, body: Data) -> URLSession {
        makeAnthropicMockSession { _ in
            (
                self.makeHTTPResponse(statusCode: statusCode),
                body
            )
        }
    }

    private func makeHTTPResponse(
        statusCode: Int,
        headerFields: [String: String] = ["Content-Type": "application/json"]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.minimaxi.com/anthropic/v1/messages")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headerFields
        )!
    }

    private func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var buffer = [UInt8](repeating: 0, count: 1024)
        var data = Data()

        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            if readCount < 0 {
                return nil
            }

            if readCount == 0 {
                break
            }

            data.append(buffer, count: readCount)
        }

        return data
    }

    private func makeBackendGatewayTempStorageURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("backend-gateway-identity.json")
    }

    private func decodeBackendGatewayWriteEnvelope(from request: URLRequest) throws -> BackendGatewayWriteEnvelopeSnapshot {
        let body = try XCTUnwrap(requestBodyData(from: request))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackendGatewayWriteEnvelopeSnapshot.self, from: body)
    }

    private func makeBackendGatewayWritingRequest(from envelope: BackendGatewayWriteEnvelopeSnapshot) -> WritingAIRequest {
        WritingAIRequest(
            action: envelope.action,
            project: envelope.project,
            userMessage: envelope.userMessage,
            selectionText: envelope.selectionText,
            selectionRange: envelope.selectionRange,
            kind: envelope.kind
        )
    }
}

private struct BackendGatewayWriteEnvelopeSnapshot: Decodable {
    let installationId: String
    let deviceToken: String
    let requestId: String
    let action: WritingAIAction
    let kind: WritingAIRequestKind
    let project: WritingProjectSnapshot
    let userMessage: String?
    let selectionText: String?
    let selectionRange: WritingTextSelectionRange?
}

private struct BackendGatewayBootstrapResponseEnvelope: Codable {
    let deviceToken: String
    let deviceStatus: String
    let quotaSummary: BackendGatewayQuotaSummaryEnvelope
}

private struct BackendGatewayQuotaSummaryEnvelope: Codable {
    let dailyLimit: Int
    let weeklyLimit: Int
}

private struct MiniMaxTextRequestEnvelope: Decodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxCompletionTokens: Int
    let stream: Bool
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
        case stream
        case responseFormat = "response_format"
    }

    struct Message: Decodable {
        let role: String
        let name: String?
        let content: String
    }

    struct ResponseFormat: Decodable {
        let type: String
        let jsonSchema: JSONSchema

        enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }
    }

    struct JSONSchema: Decodable {
        let name: String
        let strict: Bool
        let schema: Schema
    }

    struct Schema: Decodable {
        let type: String
        let required: [String]
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let responseHandler = Self.responseHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, body) = try responseHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct AnthropicRequestEnvelope: Decodable {
    let model: String
    let system: String
    let messages: [Message]
    let maxTokens: Int
    let stream: Bool
    let tools: [Tool]?
    let toolChoice: ToolChoice?

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case maxTokens = "max_tokens"
        case stream
        case tools
        case toolChoice = "tool_choice"
    }

    struct Message: Decodable {
        let role: String
        let content: [Content]
    }

    struct Content: Decodable {
        let type: String
        let text: String
    }

    struct Tool: Decodable {
        let name: String
        let description: String
        let inputSchema: InputSchema

        enum CodingKeys: String, CodingKey {
            case name
            case description
            case inputSchema = "input_schema"
        }
    }

    struct ToolChoice: Decodable {
        let type: String
        let name: String
    }

    struct InputSchema: Decodable {
        let type: String
        let properties: Properties
        let required: [String]
        let additionalProperties: Bool

        struct Properties: Decodable {
            let localSummary: StringProperty
            let globalSynopsis: StringProperty
            let nextFocus: StringProperty
            let suggestionChips: SuggestionChipsProperty
        }

        struct StringProperty: Decodable {
            let type: String
            let description: String
        }

        struct SuggestionChipsProperty: Decodable {
            let type: String
            let description: String
            let items: Items
            let minItems: Int
            let maxItems: Int

            struct Items: Decodable {
                let type: String
            }
        }
    }
}
