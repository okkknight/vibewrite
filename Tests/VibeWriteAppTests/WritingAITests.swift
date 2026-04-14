import XCTest
import VibeWriteShared
@testable import VibeWriteApp

@MainActor
final class WritingAITests: XCTestCase {
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
