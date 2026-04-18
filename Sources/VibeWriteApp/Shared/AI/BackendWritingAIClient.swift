import Foundation
import VibeWriteShared

enum BackendGatewayClientFactory {
    static func makeDefaultClient(
        configuration: BackendGatewayConfiguration = .current(),
        identityStore: BackendGatewayIdentityStore? = nil,
        session: URLSession = .shared
    ) -> any WritingAIClient {
        VibeWriteLog.ai.info(
            "Resolved backend gateway configuration mode=\(configuration.mode.rawValue, privacy: .public) baseURL=\(configuration.baseURL.absoluteString, privacy: .public) appVersion=\(configuration.appVersion, privacy: .public) platform=\(configuration.platform, privacy: .public) deviceName=\(configuration.deviceName.vibewriteLogPreview(maxLength: 40), privacy: .public)"
        )

        if !configuration.shouldUseRealClient {
            VibeWriteLog.ai.notice("AI client selected: StubWritingAIClient")
            return StubWritingAIClient()
        }

        VibeWriteLog.ai.notice("AI client selected: BackendWritingAIClient")
        return BackendWritingAIClient(
            configuration: configuration,
            identityStore: identityStore ?? BackendGatewayIdentityStore(),
            session: session
        )
    }
}

final class BackendWritingAIClient: WritingAIClient, @unchecked Sendable {
    private let configuration: BackendGatewayConfiguration
    private let identityStore: BackendGatewayIdentityStore
    private let session: URLSession

    init(
        configuration: BackendGatewayConfiguration,
        identityStore: BackendGatewayIdentityStore = BackendGatewayIdentityStore(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.identityStore = identityStore
        self.session = session
    }

    func streamResponse(for request: WritingAIRequest) -> AsyncThrowingStream<WritingAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await generateResponse(for: request)
                    if request.kind == .metadata {
                        continuation.yield(.completed(response))
                        continuation.finish()
                        return
                    }

                    let streamedText = streamedTextDelta(for: request, documentText: response.documentText)
                    let chunks = MockWritingEngine.streamChunks(for: streamedText)

                    if chunks.isEmpty {
                        continuation.yield(.completed(response))
                        continuation.finish()
                        return
                    }

                    for (index, chunk) in chunks.enumerated() {
                        continuation.yield(.textDelta(chunk))
                        if index < chunks.count - 1 {
                            try await Task.sleep(nanoseconds: 85_000_000)
                        }
                    }

                    continuation.yield(.completed(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamedTextDelta(
        for request: WritingAIRequest,
        documentText: String
    ) -> String {
        switch request.action {
        case .startDraft:
            return documentText

        case .continueWriting:
            let prefix = request.project.documentText
            guard documentText.hasPrefix(prefix) else {
                return documentText
            }
            return String(documentText.dropFirst(prefix.count))

        case .edit:
            guard let selectionRange = request.selectionRange,
                  let targetRange = selectionRange.range(in: request.project.documentText) else {
                return documentText
            }

            let prefix = String(request.project.documentText[..<targetRange.lowerBound])
            let suffix = String(request.project.documentText[targetRange.upperBound...])
            guard documentText.hasPrefix(prefix), documentText.hasSuffix(suffix) else {
                return documentText
            }

            let lowerBound = documentText.index(documentText.startIndex, offsetBy: prefix.count)
            let upperBound = documentText.index(documentText.endIndex, offsetBy: -suffix.count)
            return String(documentText[lowerBound..<upperBound])
        }
    }

    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        do {
            return try await performWriteRequest(for: request)
        } catch is BackendGatewayUnauthorizedError {
            await identityStore.clearDeviceToken()
            return try await performWriteRequest(for: request)
        }
    }

    private func performWriteRequest(for request: WritingAIRequest) async throws -> WritingAIResponse {
        let installationId = await identityStore.installationId()
        let deviceToken = try await resolvedDeviceToken(installationId: installationId)
        return try await sendWriteRequest(
            request,
            installationId: installationId,
            deviceToken: deviceToken
        )
    }

    private func resolvedDeviceToken(installationId: String) async throws -> String {
        if let deviceToken = await identityStore.deviceToken() {
            return deviceToken
        }

        return try await bootstrapDevice(installationId: installationId)
    }

    private func bootstrapDevice(installationId: String) async throws -> String {
        let requestBody = BackendGatewayBootstrapRequest(
            installationId: installationId,
            appVersion: configuration.appVersion,
            platform: configuration.platform,
            deviceName: configuration.deviceName
        )
        let urlRequest = try makeURLRequest(
            pathComponents: ["v3", "client", "bootstrap"],
            body: requestBody
        )

        let (data, response) = try await performRequest(urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WritingAIClientError.requestFailed("后端 bootstrap 请求没有返回 HTTP 响应。")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapHTTPError(statusCode: httpResponse.statusCode, body: data, fallbackMessage: "后端 bootstrap 失败（HTTP \(httpResponse.statusCode)）。")
        }

        let decodedResponse: BackendGatewayBootstrapResponse
        do {
            decodedResponse = try JSONDecoder.vibeWriteBackendGatewayResponseDecoder.decode(BackendGatewayBootstrapResponse.self, from: data)
        } catch {
            throw WritingAIClientError.invalidResponse("后端 bootstrap 响应格式无效。")
        }

        let deviceToken = decodedResponse.deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceToken.isEmpty else {
            throw WritingAIClientError.invalidResponse("后端 bootstrap 没有返回有效的 deviceToken。")
        }

        await identityStore.updateDeviceToken(deviceToken)
        return deviceToken
    }

    private func sendWriteRequest(
        _ request: WritingAIRequest,
        installationId: String,
        deviceToken: String
    ) async throws -> WritingAIResponse {
        let requestBody = BackendGatewayWriteEnvelope(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: UUID().uuidString.lowercased(),
            action: request.action,
            kind: request.kind,
            project: request.project,
            userMessage: request.userMessage,
            selectionText: request.selectionText,
            selectionRange: request.selectionRange
        )

        let urlRequest = try makeURLRequest(
            pathComponents: ["v3", "writes", routeComponent(for: request.action)],
            body: requestBody
        )

        let (data, response) = try await performRequest(urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WritingAIClientError.requestFailed("后端写作请求没有返回 HTTP 响应。")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw BackendGatewayUnauthorizedError()
            }

            throw mapHTTPError(
                statusCode: httpResponse.statusCode,
                body: data,
                fallbackMessage: "后端写作请求失败（HTTP \(httpResponse.statusCode)）。"
            )
        }

        do {
            return try JSONDecoder.vibeWriteBackendGatewayResponseDecoder.decode(WritingAIResponse.self, from: data)
        } catch {
            throw WritingAIClientError.invalidResponse("后端写作响应格式无效。")
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled {
                throw CancellationError()
            }
            throw WritingAIClientError.networkUnavailable("后端暂时不可用，请检查网络连接。")
        } catch {
            throw WritingAIClientError.requestFailed("后端请求失败：\(error.localizedDescription)")
        }
    }

    private func makeURLRequest<T: Encodable>(
        pathComponents: [String],
        body: T
    ) throws -> URLRequest {
        let url = pathComponents.reduce(configuration.baseURL) { partialResult, component in
            partialResult.appendingPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder.vibeWriteBackendGatewayRequestEncoder.encode(body)
        return request
    }

    private func routeComponent(for action: WritingAIAction) -> String {
        switch action {
        case .startDraft:
            return "start"
        case .continueWriting:
            return "continue"
        case .edit:
            return "edit"
        }
    }

    private func mapHTTPError(
        statusCode: Int,
        body: Data,
        fallbackMessage: String
    ) -> WritingAIClientError {
        if statusCode == 401 {
            return .requestFailed("后端身份凭证已失效，请重新 bootstrap。")
        }

        if statusCode == 429 {
            return .requestFailed("后端写作请求已超出当前限制，请稍后再试。")
        }

        let rawText = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rawText.isEmpty, rawText.count < 240 {
            return .requestFailed("\(fallbackMessage) \(rawText)")
        }

        return .requestFailed(fallbackMessage)
    }
}

private struct BackendGatewayBootstrapRequest: Codable {
    let installationId: String
    let appVersion: String
    let platform: String
    let deviceName: String
}

private struct BackendGatewayBootstrapResponse: Codable {
    let deviceToken: String
    let deviceStatus: String
    let quotaSummary: BackendGatewayQuotaSummary
}

private struct BackendGatewayQuotaSummary: Codable {
    let dailyLimit: Int
    let weeklyLimit: Int
}

private struct BackendGatewayWriteEnvelope: Codable {
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

private struct BackendGatewayUnauthorizedError: Error {}

private extension JSONEncoder {
    static var vibeWriteBackendGatewayRequestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var vibeWriteBackendGatewayResponseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
