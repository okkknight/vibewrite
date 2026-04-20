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
        if request.kind == .metadata {
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let response = try await generateResponse(for: request)
                        continuation.yield(.completed(response))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let installationId = await identityStore.installationId()
                    let deviceToken = try await resolvedDeviceToken(installationId: installationId)
                    let preparedRequest = try makeWriteRequest(
                        request,
                        installationId: installationId,
                        deviceToken: deviceToken,
                        accept: "application/x-ndjson"
                    )

                    let (bytes, response) = try await session.bytes(for: preparedRequest.urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        logWriteRequestOutcome(
                            request: request,
                            requestId: preparedRequest.requestId,
                            statusCode: nil,
                            responseBytes: 0,
                            responsePreview: nil,
                            requestBytes: preparedRequest.requestBodyBytes,
                            projectBytes: preparedRequest.projectBytes,
                            payloadFingerprint: preparedRequest.payloadFingerprint
                        )
                        throw WritingAIClientError.requestFailed("后端写作请求没有返回 HTTP 响应。")
                    }

                    logWriteRequestOutcome(
                        request: request,
                        requestId: preparedRequest.requestId,
                        statusCode: httpResponse.statusCode,
                        responseBytes: 0,
                        responsePreview: nil,
                        requestBytes: preparedRequest.requestBodyBytes,
                        projectBytes: preparedRequest.projectBytes,
                        payloadFingerprint: preparedRequest.payloadFingerprint
                    )

                    guard (200...299).contains(httpResponse.statusCode) else {
                        let data = try await Self.collectData(from: bytes)
                        if httpResponse.statusCode == 401 {
                            await identityStore.clearDeviceToken()
                        }
                        logWriteRequestOutcome(
                            request: request,
                            requestId: preparedRequest.requestId,
                            statusCode: httpResponse.statusCode,
                            responseBytes: data.count,
                            responsePreview: data.vibewriteResponsePreview(maxLength: 240),
                            requestBytes: preparedRequest.requestBodyBytes,
                            projectBytes: preparedRequest.projectBytes,
                            payloadFingerprint: preparedRequest.payloadFingerprint
                        )
                        throw mapHTTPError(
                            statusCode: httpResponse.statusCode,
                            body: data,
                            fallbackMessage: "后端写作请求失败（HTTP \(httpResponse.statusCode)）。"
                        )
                    }

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            continue
                        }

                        let event = try decodeStreamEvent(from: trimmed)
                        continuation.yield(event)
                    }

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
        let preparedRequest = try makeWriteRequest(
            request,
            installationId: installationId,
            deviceToken: deviceToken,
            accept: "application/json"
        )
        return try await sendWriteRequest(
            request,
            preparedRequest: preparedRequest
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
        let requestBodyData = try JSONEncoder.vibeWriteBackendGatewayRequestEncoder.encode(requestBody)
        let urlRequest = makeURLRequest(
            pathComponents: ["v3", "client", "bootstrap"],
            bodyData: requestBodyData
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
        preparedRequest: BackendGatewayPreparedWriteRequest
    ) async throws -> WritingAIResponse {
        let (data, response) = try await performRequest(preparedRequest.urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            logWriteRequestOutcome(
                request: request,
                requestId: preparedRequest.requestId,
                statusCode: nil,
                responseBytes: data.count,
                responsePreview: data.vibewriteResponsePreview(maxLength: 240),
                requestBytes: preparedRequest.requestBodyBytes,
                projectBytes: preparedRequest.projectBytes,
                payloadFingerprint: preparedRequest.payloadFingerprint
            )
            throw WritingAIClientError.requestFailed("后端写作请求没有返回 HTTP 响应。")
        }

        logWriteRequestOutcome(
            request: request,
            requestId: preparedRequest.requestId,
            statusCode: httpResponse.statusCode,
            responseBytes: data.count,
            responsePreview: httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 ? data.vibewriteResponsePreview(maxLength: 240) : nil,
            requestBytes: preparedRequest.requestBodyBytes,
            projectBytes: preparedRequest.projectBytes,
            payloadFingerprint: preparedRequest.payloadFingerprint
        )

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
        body: T,
        accept: String = "application/json"
    ) throws -> URLRequest {
        let bodyData = try JSONEncoder.vibeWriteBackendGatewayRequestEncoder.encode(body)
        return makeURLRequest(pathComponents: pathComponents, bodyData: bodyData, accept: accept)
    }

    private func makeURLRequest(
        pathComponents: [String],
        bodyData: Data,
        accept: String = "application/json"
    ) -> URLRequest {
        let url = pathComponents.reduce(configuration.baseURL) { partialResult, component in
            partialResult.appendingPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.httpBody = bodyData
        return request
    }

    private func makeWriteRequest(
        _ request: WritingAIRequest,
        installationId: String,
        deviceToken: String,
        accept: String
    ) throws -> BackendGatewayPreparedWriteRequest {
        let requestId = UUID().uuidString.lowercased()
        let requestBody = BackendGatewayWriteEnvelope(
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: requestId,
            action: request.action,
            kind: request.kind,
            project: request.project,
            userMessage: request.userMessage,
            selectionText: request.selectionText,
            selectionRange: request.selectionRange
        )
        let requestBodyData = try JSONEncoder.vibeWriteBackendGatewayRequestEncoder.encode(requestBody)
        let projectData = try JSONEncoder.vibeWriteBackendGatewayRequestEncoder.encode(request.project)
        let payloadFingerprint = requestBodyData.vibewriteRequestFingerprint()
        logWriteRequestMetrics(
            request: request,
            requestId: requestId,
            requestBodyBytes: requestBodyData.count,
            projectBytes: projectData.count,
            payloadFingerprint: payloadFingerprint
        )

        return BackendGatewayPreparedWriteRequest(
            urlRequest: makeURLRequest(
                pathComponents: ["v3", "writes", routeComponent(for: request.action)],
                bodyData: requestBodyData,
                accept: accept
            ),
            requestId: requestId,
            requestBodyBytes: requestBodyData.count,
            projectBytes: projectData.count,
            payloadFingerprint: payloadFingerprint
        )
    }

    private func decodeStreamEvent(from rawLine: String) throws -> WritingAIStreamEvent {
        guard let data = rawLine.data(using: .utf8) else {
            throw WritingAIClientError.invalidResponse("后端流式响应无法转换为 UTF-8。")
        }

        do {
            return try JSONDecoder.vibeWriteBackendGatewayResponseDecoder.decode(WritingAIStreamEvent.self, from: data)
        } catch {
            throw WritingAIClientError.invalidResponse("后端流式响应格式无效。")
        }
    }

    private static func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
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

    private func logWriteRequestMetrics(
        request: WritingAIRequest,
        requestId: String,
        requestBodyBytes: Int,
        projectBytes: Int,
        payloadFingerprint: String
    ) {
        let documentTextBytes = request.project.documentText.utf8.count
        let conversationBytes = request.project.conversation.reduce(0) { partialResult, message in
            partialResult + message.text.utf8.count
        }
        let conversationCount = request.project.conversation.count
        let globalSynopsisBytes = request.project.globalSynopsis.utf8.count
        let localSummaryBytes = request.project.localSummary.utf8.count
        let intentSummaryBytes = request.project.context.intentSummary.utf8.count
        let currentGoalBytes = request.project.context.currentGoal.utf8.count
        let nextFocusBytes = request.project.context.nextFocus.utf8.count
        let workingMemoryBytes = request.project.context.workingMemory.reduce(0) { partialResult, value in
            partialResult + value.utf8.count
        }
        let recentDecisionsBytes = request.project.context.recentDecisions.reduce(0) { partialResult, value in
            partialResult + value.utf8.count
        }
        let styleConstraintsBytes = request.project.context.styleConstraints.reduce(0) { partialResult, value in
            partialResult + value.utf8.count
        }
        let userMessageBytes = request.userMessage?.utf8.count ?? 0
        let selectionTextBytes = request.selectionText?.utf8.count ?? 0
        let suggestionChipsBytes = request.project.suggestionChips.reduce(0) { partialResult, value in
            partialResult + value.utf8.count
        }

        VibeWriteLog.ai.info(
            "backend write request metrics action=\(request.action.rawValue, privacy: .public) kind=\(request.kind.rawValue, privacy: .public) requestId=\(requestId, privacy: .public) payloadFingerprint=\(payloadFingerprint, privacy: .public) envelopeBytes=\(requestBodyBytes, privacy: .public) projectBytes=\(projectBytes, privacy: .public) documentBytes=\(documentTextBytes, privacy: .public) conversationBytes=\(conversationBytes, privacy: .public) conversationCount=\(conversationCount, privacy: .public) globalSynopsisBytes=\(globalSynopsisBytes, privacy: .public) localSummaryBytes=\(localSummaryBytes, privacy: .public) intentSummaryBytes=\(intentSummaryBytes, privacy: .public) currentGoalBytes=\(currentGoalBytes, privacy: .public) nextFocusBytes=\(nextFocusBytes, privacy: .public) workingMemoryBytes=\(workingMemoryBytes, privacy: .public) recentDecisionsBytes=\(recentDecisionsBytes, privacy: .public) styleConstraintsBytes=\(styleConstraintsBytes, privacy: .public) suggestionChipsBytes=\(suggestionChipsBytes, privacy: .public) userMessageBytes=\(userMessageBytes, privacy: .public) selectionTextBytes=\(selectionTextBytes, privacy: .public)"
        )
    }

    private func logWriteRequestOutcome(
        request: WritingAIRequest,
        requestId: String,
        statusCode: Int?,
        responseBytes: Int,
        responsePreview: String?,
        requestBytes: Int,
        projectBytes: Int,
        payloadFingerprint: String
    ) {
        let statusText = statusCode.map { String($0) } ?? "nil"
        let responsePreviewText = responsePreview ?? "nil"
        if let responsePreview, !responsePreview.isEmpty {
            VibeWriteLog.ai.warning(
                "backend write response action=\(request.action.rawValue, privacy: .public) kind=\(request.kind.rawValue, privacy: .public) requestId=\(requestId, privacy: .public) payloadFingerprint=\(payloadFingerprint, privacy: .public) statusCode=\(statusText, privacy: .public) responseBytes=\(responseBytes, privacy: .public) responsePreview=\(responsePreview, privacy: .public) requestBytes=\(requestBytes, privacy: .public) projectBytes=\(projectBytes, privacy: .public)"
            )
            return
        }

        VibeWriteLog.ai.info(
            "backend write response action=\(request.action.rawValue, privacy: .public) kind=\(request.kind.rawValue, privacy: .public) requestId=\(requestId, privacy: .public) payloadFingerprint=\(payloadFingerprint, privacy: .public) statusCode=\(statusText, privacy: .public) responseBytes=\(responseBytes, privacy: .public) responsePreview=\(responsePreviewText, privacy: .public) requestBytes=\(requestBytes, privacy: .public) projectBytes=\(projectBytes, privacy: .public)"
        )
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

private struct BackendGatewayPreparedWriteRequest {
    let urlRequest: URLRequest
    let requestId: String
    let requestBodyBytes: Int
    let projectBytes: Int
    let payloadFingerprint: String
}

private extension Data {
    func vibewriteRequestFingerprint() -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in self {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16, uppercase: false)
    }

    func vibewriteResponsePreview(maxLength: Int) -> String {
        guard let rawText = String(data: self, encoding: .utf8) else {
            return "\(count) bytes non-UTF8"
        }

        let collapsed = rawText.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.isEmpty {
            return "\(count) bytes empty"
        }
        if collapsed.count <= maxLength {
            return collapsed
        }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }
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
