import XCTest
@testable import VibeWriteApp

@MainActor
final class WritingAITests: XCTestCase {
    func testConfigurationUsesBundleValuesAndFallsBackToStubWhenMissing() {
        let configuration = WritingAIConfiguration.configuration(from: [
            "VIBEWRITE_AI_DEFAULT_MODE": "real",
            "VIBEWRITE_AI_PROVIDER": "minimax",
            "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
            "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
            "MINIMAX_API_KEY": "bundle-key-123"
        ])

        XCTAssertEqual(configuration.mode, .real)
        XCTAssertEqual(configuration.provider, "minimax")
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://api.minimaxi.com/anthropic")
        XCTAssertEqual(configuration.model, "MiniMax-M2.5-highspeed")
        XCTAssertEqual(configuration.apiKey, "bundle-key-123")
        XCTAssertTrue(configuration.shouldUseRealClient)

        let overriddenConfiguration = WritingAIConfiguration.configuration(
            from: [
                "VIBEWRITE_AI_DEFAULT_MODE": "real",
                "MINIMAX_API_KEY": "bundle-key-123"
            ],
            environment: [
                "VIBEWRITE_AI_MODE": "stub",
                "MINIMAX_API_KEY": "env-key-456"
            ]
        )

        XCTAssertEqual(overriddenConfiguration.mode, .stub)
        XCTAssertEqual(overriddenConfiguration.apiKey, "env-key-456")

        let cleanLaunchConfiguration = WritingAIConfiguration.configuration(
            from: [
                "VIBEWRITE_AI_DEFAULT_MODE": "real",
                "VIBEWRITE_AI_PROVIDER": "minimax",
                "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
                "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
                "MINIMAX_API_KEY": "bundle-key-123"
            ],
            environment: [
                "VIBEWRITE_AI_MODE": "stub",
                "MINIMAX_API_KEY": "env-key-456",
                "MINIMAX_BASE_URL": "https://example.invalid"
            ]
        )

        XCTAssertEqual(cleanLaunchConfiguration.mode, .stub)

        let ignoredOverrideConfiguration = WritingAIConfiguration.configuration(
            from: [
                "VIBEWRITE_AI_DEFAULT_MODE": "real",
                "VIBEWRITE_AI_PROVIDER": "minimax",
                "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
                "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
                "MINIMAX_API_KEY": "bundle-key-123"
            ],
            environment: [:]
        )
        XCTAssertEqual(ignoredOverrideConfiguration.mode, .real)
        XCTAssertEqual(ignoredOverrideConfiguration.provider, "minimax")
        XCTAssertEqual(ignoredOverrideConfiguration.baseURL.absoluteString, "https://api.minimaxi.com/anthropic")
        XCTAssertEqual(ignoredOverrideConfiguration.model, "MiniMax-M2.5-highspeed")
        XCTAssertEqual(ignoredOverrideConfiguration.apiKey, "bundle-key-123")
        XCTAssertTrue(ignoredOverrideConfiguration.shouldUseRealClient)

        let fallbackClient = WritingAIClientFactory.makeDefaultClient(
            configuration: WritingAIConfiguration.configuration(from: [:])
        )

        XCTAssertTrue(fallbackClient is StubWritingAIClient)
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

    func testPromptBuilderUsesShortOutputProtocol() {
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
            model: "MiniMax-M2.7"
        )

        let systemPrompt = messages.first?.content ?? ""
        let userPrompt = messages.last?.content ?? ""
        XCTAssertTrue(systemPrompt.contains("Output the writing text first"))
        XCTAssertTrue(systemPrompt.contains("[[VIBEWRITE_METADATA]]"))
        XCTAssertTrue(systemPrompt.contains("summary, nextFocus, suggestionChips"))
        XCTAssertTrue(systemPrompt.contains("Chinese writing tasks"))
        XCTAssertTrue(userPrompt.contains("Action: startDraft"))
        XCTAssertTrue(userPrompt.contains("User message: \(prompt)"))
        XCTAssertTrue(userPrompt.contains("[[VIBEWRITE_METADATA]]"))
        XCTAssertTrue(userPrompt.contains("summary, nextFocus, and suggestionChips"))
        XCTAssertTrue(userPrompt.contains("Chinese writing tasks"))
        XCTAssertFalse(userPrompt.contains("assistantMessage"))
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
            summary: "给人看的摘要可以保留原样",
            continuationSummary: "给模型看的压缩摘要要更短、更偏状态",
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
            model: "MiniMax-M2.7"
        )

        let systemPrompt = messages.first?.content ?? ""
        let userPrompt = messages.last?.content ?? ""

        XCTAssertTrue(systemPrompt.contains("When the action is \"continueWriting\""))
        XCTAssertTrue(systemPrompt.contains("prefer 3 concise chips"))
        XCTAssertTrue(userPrompt.contains("Document summary:"))
        XCTAssertTrue(userPrompt.contains("Document tail:"))
        XCTAssertTrue(userPrompt.contains("Project state:"))
        XCTAssertTrue(userPrompt.contains("给模型看的压缩摘要要更短、更偏状态"))
        XCTAssertTrue(userPrompt.contains("尾部第二段要真正作为继续写的起点。"))
        XCTAssertTrue(userPrompt.contains("Current goal: 继续推进结尾"))
        XCTAssertTrue(userPrompt.contains("Next focus: 补一段收束"))
        XCTAssertTrue(userPrompt.contains("Style constraints: 克制 · 平静 · 非鸡汤"))
        XCTAssertFalse(userPrompt.contains("前文第1段用来铺陈背景和细节"))
        XCTAssertFalse(userPrompt.contains("Current document:"))
        XCTAssertTrue(userPrompt.contains("For continueWriting, return 3 concise suggestion chips"))
        XCTAssertTrue(userPrompt.contains("should follow the current正文 naturally"))
    }

    func testRemoteClientUsesWiderMaxTokensAndProjectStateForContinueWriting() async throws {
        let configuration = WritingAIConfiguration.configuration(from: [
            "VIBEWRITE_AI_DEFAULT_MODE": "real",
            "VIBEWRITE_AI_PROVIDER": "minimax",
            "MINIMAX_BASE_URL": "https://api.minimaxi.com/anthropic",
            "MINIMAX_MODEL": "MiniMax-M2.5-highspeed",
            "MINIMAX_API_KEY": "bundle-key-123"
        ])

        let session = makeAnthropicMockSession { request in
            let body = try XCTUnwrap(self.requestBodyData(from: request))
            let payload = try JSONDecoder().decode(AnthropicRequestEnvelope.self, from: body)

            XCTAssertEqual(payload.maxTokens, 1536)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Project state:") ?? false)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Current goal:") ?? false)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Next focus:") ?? false)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Style constraints:") ?? false)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("Document tail:") ?? false)

            let response = """
            event: message_start
            data: {"type":"message_start"}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"续写正文。\\n\\n[[VIBEWRITE_METADATA]]\\n{\\\"summary\\\":\\\"新的摘要\\\",\\\"nextFocus\\\":\\\"下一步\\\",\\\"suggestionChips\\\":[\\\"继续写\\\",\\\"编辑这段\\\",\\\"补一段\\\"]}"}}

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
            summary: "给人看的摘要可以保留原样",
            continuationSummary: "给模型看的压缩摘要要更短、更偏状态",
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

        XCTAssertEqual(finalResponse?.summary, "新的摘要")
        XCTAssertEqual(finalResponse?.nextFocus, "下一步")
        XCTAssertEqual(finalResponse?.suggestionChips, ["继续写", "编辑这段", "补一段"])
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
            XCTAssertTrue(payload.system.contains("Output the writing text first"))
            XCTAssertTrue(payload.system.contains("[[VIBEWRITE_METADATA]]"))
            XCTAssertEqual(payload.messages.count, 1)
            XCTAssertEqual(payload.messages.first?.role, "user")
            XCTAssertEqual(payload.messages.first?.content.first?.type, "text")
            XCTAssertEqual(payload.messages.first?.content.first?.text.contains("Action: startDraft"), true)
            XCTAssertTrue(payload.messages.first?.content.first?.text.contains("User message: 写一篇关于成年人孤独感的公众号文章") ?? false)
            XCTAssertTrue(payload.stream)

            let response = """
            event: message_start
            data: {"type":"message_start"}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"成年人真正感到孤独的时候，未必是在深夜。"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"更多时候，是在一个很普通的傍晚。\\n\\n[[VIBEWRITE_METADATA]]\\n{\\\"summary\\\":\\\"已生成第一稿，正在收紧开头\\\",\\\"nextFocus\\\":\\\"继续推进第一段\\\",\\\"suggestionChips\\\":[\\\"继续写\\\",\\\"编辑这段\\\",\\\"补一段\\\"]}"}}

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
        XCTAssertEqual(finalResponse?.summary, "已生成第一稿，正在收紧开头")
        XCTAssertEqual(finalResponse?.nextFocus, "继续推进第一段")
        XCTAssertEqual(finalResponse?.suggestionChips, ["继续写", "编辑这段", "补一段"])
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

        XCTAssertEqual(response.summary, "")
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
          "summary": "摘要",
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
            summary: "新的摘要",
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
            model: "MiniMax-M2.7"
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
            "MINIMAX_MODEL": "MiniMax-M2.7",
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

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case maxTokens = "max_tokens"
        case stream
    }

    struct Message: Decodable {
        let role: String
        let content: [Content]
    }

    struct Content: Decodable {
        let type: String
        let text: String
    }
}
