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
    private static let preferredContinueWindowCharacterCount = 1_200
    private static let maximumContinueWindowCharacterCount = 1_500
    private static let focusedEditWindowCharacterCount = 1_200
    private static let maximumFocusedEditWindowCharacterCount = 1_800
    private static let expandedEditWindowCharacterCount = 2_200
    private static let maximumExpandedEditWindowCharacterCount = 2_800
    private static let expandedEditSelectionThreshold = 500
    private static let expandedEditKeywords = [
        "全文", "整篇", "全篇", "整体", "统一", "前后呼应", "前后照应",
        "通篇", "人称", "时态", "伏笔", "回收", "语气统一", "整体语气"
    ]

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
                            contextBytes: preparedRequest.contextBytes,
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
                        contextBytes: preparedRequest.contextBytes,
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
                            contextBytes: preparedRequest.contextBytes,
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

                        let event = try decodeStreamEvent(from: trimmed, originalRequest: request)
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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
                contextBytes: preparedRequest.contextBytes,
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
            contextBytes: preparedRequest.contextBytes,
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
            let gatewayResponse = try JSONDecoder.vibeWriteBackendGatewayResponseDecoder.decode(WritingGatewayResponse.self, from: data)
            return try translatedResponse(from: gatewayResponse, originalRequest: request)
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
        let requestBody = try gatewayEnvelope(
            for: request,
            installationId: installationId,
            deviceToken: deviceToken,
            requestId: requestId
        )
        let requestBodyData = try JSONEncoder.vibeWriteBackendGatewayRequestEncoder.encode(requestBody)
        let contextData = try JSONEncoder.vibeWriteBackendGatewayRequestEncoder.encode(requestBody)
        let payloadFingerprint = requestBodyData.vibewriteRequestFingerprint()
        logWriteRequestMetrics(
            request: request,
            envelope: requestBody,
            requestId: requestId,
            requestBodyBytes: requestBodyData.count,
            contextBytes: contextData.count,
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
            contextBytes: contextData.count,
            payloadFingerprint: payloadFingerprint
        )
    }

    private func gatewayEnvelope(
        for request: WritingAIRequest,
        installationId: String,
        deviceToken: String,
        requestId: String
    ) throws -> WritingGatewayWriteEnvelope {
        switch request.action {
        case .startDraft:
            return WritingGatewayWriteEnvelope(
                installationId: installationId,
                deviceToken: deviceToken,
                requestId: requestId,
                action: request.action,
                kind: request.kind,
                startProject: request.project,
                userMessage: request.userMessage
            )

        case .continueWriting:
            return WritingGatewayWriteEnvelope(
                installationId: installationId,
                deviceToken: deviceToken,
                requestId: requestId,
                action: request.action,
                kind: request.kind,
                sessionContext: gatewaySessionContext(for: request.project),
                continueWindow: continueWindow(for: request.project.documentText),
                userMessage: request.userMessage
            )

        case .edit:
            return WritingGatewayWriteEnvelope(
                installationId: installationId,
                deviceToken: deviceToken,
                requestId: requestId,
                action: request.action,
                kind: request.kind,
                sessionContext: gatewaySessionContext(for: request.project),
                editWindow: try editWindow(for: request),
                userMessage: request.userMessage
            )
        }
    }

    private func translatedResponse(
        from gatewayResponse: WritingGatewayResponse,
        originalRequest: WritingAIRequest
    ) throws -> WritingAIResponse {
        let resolvedDocumentText: String
        switch originalRequest.action {
        case .startDraft:
            if originalRequest.kind == .prose {
                guard let documentText = gatewayResponse.documentText else {
                    throw WritingAIClientError.invalidResponse("后端起稿响应缺少完整正文。")
                }
                resolvedDocumentText = documentText
            } else {
                resolvedDocumentText = originalRequest.project.documentText
            }

        case .continueWriting:
            if let appendedText = gatewayResponse.appendedText {
                resolvedDocumentText = originalRequest.project.documentText + appendedText
            } else {
                resolvedDocumentText = originalRequest.project.documentText
            }

        case .edit:
            if let replacementText = gatewayResponse.replacementText {
                guard let targetRange = originalRequest.selectionRange?.range(in: originalRequest.project.documentText) else {
                    throw WritingAIClientError.invalidResponse("后端编辑响应缺少可用的本地选区。")
                }

                var revisedDocument = originalRequest.project.documentText
                revisedDocument.replaceSubrange(targetRange, with: replacementText)
                resolvedDocumentText = revisedDocument
            } else {
                resolvedDocumentText = originalRequest.project.documentText
            }
        }

        return WritingAIResponse(
            assistantMessage: gatewayResponse.assistantMessage,
            documentText: resolvedDocumentText,
            localSummary: gatewayResponse.localSummary,
            globalSynopsis: gatewayResponse.globalSynopsis,
            intentSummary: gatewayResponse.intentSummary,
            styleConstraints: gatewayResponse.styleConstraints,
            currentGoal: gatewayResponse.currentGoal,
            recentDecisions: gatewayResponse.recentDecisions,
            workingMemory: gatewayResponse.workingMemory,
            nextFocus: gatewayResponse.nextFocus,
            suggestionChips: gatewayResponse.suggestionChips,
            mode: gatewayResponse.mode
        )
    }

    func decodeStreamEvent(
        from rawLine: String,
        originalRequest: WritingAIRequest
    ) throws -> WritingAIStreamEvent {
        guard let data = rawLine.data(using: .utf8) else {
            throw WritingAIClientError.invalidResponse("后端流式响应无法转换为 UTF-8。")
        }

        do {
            let event = try JSONDecoder.vibeWriteBackendGatewayResponseDecoder.decode(WritingGatewayStreamEvent.self, from: data)
            switch event {
            case .textDelta(let delta):
                return .textDelta(delta)
            case .completed(let response):
                return .completed(try translatedResponse(from: response, originalRequest: originalRequest))
            }
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

    private func gatewaySessionContext(for project: WritingProjectSnapshot) -> WritingGatewaySessionContext {
        WritingGatewaySessionContext(
            title: project.title,
            prompt: project.prompt,
            mode: project.mode,
            localSummary: project.localSummary,
            globalSynopsis: project.globalSynopsis,
            context: project.context,
            suggestionChips: project.suggestionChips
        )
    }

    private func continueWindow(for documentText: String) -> WritingGatewayTailWindow {
        let trimmed = documentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return WritingGatewayTailWindow(
                tailText: "",
                totalCharacterCount: 0,
                tailCharacterCount: 0,
                isTruncated: false
            )
        }

        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let tailText: String
        if paragraphs.isEmpty {
            tailText = String(trimmed.suffix(Self.maximumContinueWindowCharacterCount))
        } else {
            var selected: [String] = []
            var characterCount = 0
            for paragraph in paragraphs.reversed() {
                selected.insert(paragraph, at: 0)
                characterCount += paragraph.count
                if characterCount >= Self.preferredContinueWindowCharacterCount && selected.count >= 2 {
                    break
                }
            }

            let joined = selected.joined(separator: "\n\n")
            if joined.count <= Self.maximumContinueWindowCharacterCount {
                tailText = joined
            } else {
                tailText = String(joined.suffix(Self.maximumContinueWindowCharacterCount))
            }
        }

        return WritingGatewayTailWindow(
            tailText: tailText,
            totalCharacterCount: trimmed.count,
            tailCharacterCount: tailText.count,
            isTruncated: tailText != trimmed
        )
    }

    private func editWindow(for request: WritingAIRequest) throws -> WritingGatewayEditWindow {
        guard let selectionRange = request.selectionRange,
              let targetRange = selectionRange.range(in: request.project.documentText) else {
            throw WritingAIClientError.requestFailed("当前编辑请求缺少有效选区。")
        }

        let selectionText = String(request.project.documentText[targetRange])
        guard !selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WritingAIClientError.requestFailed("当前编辑请求缺少有效选区。")
        }

        let strategy = resolvedEditWindowStrategy(for: request, selectionText: selectionText)
        let preferredCharacterCount = strategy == .focused
            ? Self.focusedEditWindowCharacterCount
            : Self.expandedEditWindowCharacterCount
        let maximumCharacterCount = strategy == .focused
            ? Self.maximumFocusedEditWindowCharacterCount
            : Self.maximumExpandedEditWindowCharacterCount

        let documentText = request.project.documentText
        let selectionCount = selectionText.count
        let remainingBudget = max(preferredCharacterCount - selectionCount, 0)
        let lowerBound = boundedLowerIndex(
            in: documentText,
            around: targetRange.lowerBound,
            characterCount: remainingBudget / 2
        )
        let upperBound = boundedUpperIndex(
            in: documentText,
            around: targetRange.upperBound,
            characterCount: remainingBudget - (remainingBudget / 2)
        )

        let expandedLowerBound = expandLowerBoundToParagraphBreak(
            in: documentText,
            currentLowerBound: lowerBound,
            targetUpperBound: upperBound,
            maximumCharacterCount: maximumCharacterCount
        )
        let expandedUpperBound = expandUpperBoundToParagraphBreak(
            in: documentText,
            currentUpperBound: upperBound,
            targetLowerBound: expandedLowerBound,
            maximumCharacterCount: maximumCharacterCount
        )

        let beforeContextText = String(documentText[expandedLowerBound..<targetRange.lowerBound])
        let afterContextText = String(documentText[targetRange.upperBound..<expandedUpperBound])
        let windowText = beforeContextText + selectionText + afterContextText

        return WritingGatewayEditWindow(
            beforeContextText: beforeContextText,
            selectionText: selectionText,
            afterContextText: afterContextText,
            totalCharacterCount: documentText.count,
            windowCharacterCount: windowText.count,
            strategy: strategy
        )
    }

    private func resolvedEditWindowStrategy(
        for request: WritingAIRequest,
        selectionText: String
    ) -> WritingGatewayEditWindowStrategy {
        let message = request.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if selectionText.count >= Self.expandedEditSelectionThreshold {
            return .expanded
        }
        if Self.expandedEditKeywords.contains(where: { message.contains($0) }) {
            return .expanded
        }
        let paragraphCount = selectionText.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        if paragraphCount >= 3 {
            return .expanded
        }
        return .focused
    }

    private func boundedLowerIndex(
        in text: String,
        around anchor: String.Index,
        characterCount: Int
    ) -> String.Index {
        text.index(anchor, offsetBy: -characterCount, limitedBy: text.startIndex) ?? text.startIndex
    }

    private func boundedUpperIndex(
        in text: String,
        around anchor: String.Index,
        characterCount: Int
    ) -> String.Index {
        text.index(anchor, offsetBy: characterCount, limitedBy: text.endIndex) ?? text.endIndex
    }

    private func expandLowerBoundToParagraphBreak(
        in text: String,
        currentLowerBound: String.Index,
        targetUpperBound: String.Index,
        maximumCharacterCount: Int
    ) -> String.Index {
        guard currentLowerBound > text.startIndex,
              let breakRange = text.range(
                of: "\n\n",
                options: .backwards,
                range: text.startIndex..<currentLowerBound
              ) else {
            return currentLowerBound
        }

        let candidateLowerBound = breakRange.upperBound
        let candidateCount = text.distance(from: candidateLowerBound, to: targetUpperBound)
        return candidateCount <= maximumCharacterCount ? candidateLowerBound : currentLowerBound
    }

    private func expandUpperBoundToParagraphBreak(
        in text: String,
        currentUpperBound: String.Index,
        targetLowerBound: String.Index,
        maximumCharacterCount: Int
    ) -> String.Index {
        guard currentUpperBound < text.endIndex,
              let breakRange = text.range(
                of: "\n\n",
                options: [],
                range: currentUpperBound..<text.endIndex
              ) else {
            return currentUpperBound
        }

        let candidateUpperBound = breakRange.lowerBound
        let candidateCount = text.distance(from: targetLowerBound, to: candidateUpperBound)
        return candidateCount <= maximumCharacterCount ? candidateUpperBound : currentUpperBound
    }

    private func logWriteRequestMetrics(
        request: WritingAIRequest,
        envelope: WritingGatewayWriteEnvelope,
        requestId: String,
        requestBodyBytes: Int,
        contextBytes: Int,
        payloadFingerprint: String
    ) {
        let userMessageBytes = request.userMessage?.utf8.count ?? 0
        let tailBytes = envelope.continueWindow?.tailText.utf8.count ?? 0
        let selectionTextBytes = envelope.editWindow?.selectionText.utf8.count ?? 0
        let beforeContextBytes = envelope.editWindow?.beforeContextText.utf8.count ?? 0
        let afterContextBytes = envelope.editWindow?.afterContextText.utf8.count ?? 0
        let totalDocumentCharacters = request.project.documentText.count

        VibeWriteLog.ai.info(
            "backend write request metrics action=\(request.action.rawValue, privacy: .public) kind=\(request.kind.rawValue, privacy: .public) requestId=\(requestId, privacy: .public) payloadFingerprint=\(payloadFingerprint, privacy: .public) envelopeBytes=\(requestBodyBytes, privacy: .public) contextBytes=\(contextBytes, privacy: .public) totalDocumentCharacters=\(totalDocumentCharacters, privacy: .public) tailBytes=\(tailBytes, privacy: .public) beforeContextBytes=\(beforeContextBytes, privacy: .public) selectionTextBytes=\(selectionTextBytes, privacy: .public) afterContextBytes=\(afterContextBytes, privacy: .public) userMessageBytes=\(userMessageBytes, privacy: .public)"
        )
        VibeWriteRequestTrace.append(
            "backend write request metrics action=\(request.action.rawValue) kind=\(request.kind.rawValue) requestId=\(requestId) payloadFingerprint=\(payloadFingerprint) envelopeBytes=\(requestBodyBytes) contextBytes=\(contextBytes) totalDocumentCharacters=\(totalDocumentCharacters) tailBytes=\(tailBytes) beforeContextBytes=\(beforeContextBytes) selectionTextBytes=\(selectionTextBytes) afterContextBytes=\(afterContextBytes) userMessageBytes=\(userMessageBytes)"
        )
    }

    private func logWriteRequestOutcome(
        request: WritingAIRequest,
        requestId: String,
        statusCode: Int?,
        responseBytes: Int,
        responsePreview: String?,
        requestBytes: Int,
        contextBytes: Int,
        payloadFingerprint: String
    ) {
        let statusText = statusCode.map { String($0) } ?? "nil"
        let responsePreviewText = responsePreview ?? "nil"
        if let responsePreview, !responsePreview.isEmpty {
            VibeWriteLog.ai.warning(
                "backend write response action=\(request.action.rawValue, privacy: .public) kind=\(request.kind.rawValue, privacy: .public) requestId=\(requestId, privacy: .public) payloadFingerprint=\(payloadFingerprint, privacy: .public) statusCode=\(statusText, privacy: .public) responseBytes=\(responseBytes, privacy: .public) responsePreview=\(responsePreview, privacy: .public) requestBytes=\(requestBytes, privacy: .public) contextBytes=\(contextBytes, privacy: .public)"
            )
            VibeWriteRequestTrace.append(
                "backend write response action=\(request.action.rawValue) kind=\(request.kind.rawValue) requestId=\(requestId) payloadFingerprint=\(payloadFingerprint) statusCode=\(statusText) responseBytes=\(responseBytes) responsePreview=\(responsePreview) requestBytes=\(requestBytes) contextBytes=\(contextBytes)"
            )
            return
        }

        VibeWriteLog.ai.info(
            "backend write response action=\(request.action.rawValue, privacy: .public) kind=\(request.kind.rawValue, privacy: .public) requestId=\(requestId, privacy: .public) payloadFingerprint=\(payloadFingerprint, privacy: .public) statusCode=\(statusText, privacy: .public) responseBytes=\(responseBytes, privacy: .public) responsePreview=\(responsePreviewText, privacy: .public) requestBytes=\(requestBytes, privacy: .public) contextBytes=\(contextBytes, privacy: .public)"
        )
        VibeWriteRequestTrace.append(
            "backend write response action=\(request.action.rawValue) kind=\(request.kind.rawValue) requestId=\(requestId) payloadFingerprint=\(payloadFingerprint) statusCode=\(statusText) responseBytes=\(responseBytes) responsePreview=\(responsePreviewText) requestBytes=\(requestBytes) contextBytes=\(contextBytes)"
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

private struct BackendGatewayPreparedWriteRequest {
    let urlRequest: URLRequest
    let requestId: String
    let requestBodyBytes: Int
    let contextBytes: Int
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
