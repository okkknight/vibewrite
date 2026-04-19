import Foundation
import XCTest
@testable import VibeWriteBackend
import VibeWriteShared

final class BackendAIProviderClientTests: XCTestCase {
    func testProseRequestPreservesLeadingAndInternalParagraphBreaks() async throws {
        let request = WritingAIRequest(
            action: .continueWriting,
            project: makeRequest().project,
            userMessage: "继续往下写",
            selectionText: nil,
            kind: .prose
        )

        let responseJSON = """
        {
          "content": [
            { "type": "text", "text": "\\n\\n第一段。\\n\\n第二段。\\n" }
          ]
        }
        """

        let session = makeSession { urlRequest in
            XCTAssertTrue(urlRequest.url?.path.hasSuffix("/v1/messages") ?? false)
            let response = HTTPURLResponse(
                url: urlRequest.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let client = MiniMaxBackendAIProviderClient(session: session)
        let proseText = try await client.generateProseText(
            for: request,
            messages: [],
            configuration: makeConfiguration(metadataRoute: .current),
            apiKey: "provider-key"
        )

        XCTAssertEqual(proseText, "\n\n第一段。\n\n第二段。\n")
    }

    func testCurrentRouteMetadataFallsBackWhenToolCallIsMissing() async throws {
        let request = makeRequest()
        let responseJSON = """
        {
          "content": [
            { "type": "text", "text": "not metadata json" }
          ]
        }
        """

        let session = makeSession { urlRequest in
            XCTAssertTrue(urlRequest.url?.path.hasSuffix("/v1/messages") ?? false)
            let response = HTTPURLResponse(
                url: urlRequest.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let client = MiniMaxBackendAIProviderClient(session: session)
        let metadata = try await client.generateMetadata(
            for: request,
            messages: [],
            configuration: makeConfiguration(metadataRoute: .current),
            apiKey: "provider-key"
        )

        XCTAssertEqual(metadata.localSummary, "本地摘要")
        XCTAssertEqual(metadata.globalSynopsis, "全局梗概")
        XCTAssertEqual(metadata.nextFocus, "继续往下写")
        XCTAssertEqual(metadata.suggestionChips, ["继续写", "编辑这段"])
    }

    func testAnthropicStreamParserHandlesTextAndStopEvents() throws {
        let textDeltaEvent = AnthropicStreamParser.events(
            eventType: "content_block_delta",
            dataLines: [
                #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"第一段。"}}"#
            ]
        )

        let thinkingDeltaEvent = AnthropicStreamParser.events(
            eventType: "content_block_delta",
            dataLines: [
                #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"用户要求"}}"#
            ]
        )

        let stopEvent = AnthropicStreamParser.events(
            eventType: "message_stop",
            dataLines: []
        )

        XCTAssertEqual(textDeltaEvent, [.textDelta("第一段。")])
        XCTAssertEqual(thinkingDeltaEvent, [])
        XCTAssertEqual(stopEvent, [.completed])
    }

    private func makeRequest() -> WritingAIRequest {
        WritingAIRequest(
            action: .continueWriting,
            project: WritingProjectSnapshot(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
                automationKey: "backend.metadata.fallback",
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
            ),
            userMessage: "继续往下写",
            selectionText: nil,
            kind: .metadata
        )
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

    private func makeSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = handler
        return URLSession(configuration: configuration)
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
