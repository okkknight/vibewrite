import Foundation

struct VibeWriteMarkdownDocument: Hashable {
    var identityMarker: VibeWriteDocumentIdentityMarker?
    var body: String

    init(identityMarker: VibeWriteDocumentIdentityMarker? = nil, body: String) {
        self.identityMarker = identityMarker
        self.body = body
    }

    init(project: WritingProject) {
        identityMarker = VibeWriteDocumentIdentityMarker(
            schemaVersion: VibeWriteDocumentMetadataPolicy.schemaVersion,
            documentID: project.id
        )
        body = project.documentText
    }

    func renderedText() -> String {
        let marker = identityMarker ?? VibeWriteDocumentIdentityMarker(
            schemaVersion: VibeWriteDocumentMetadataPolicy.schemaVersion,
            documentID: UUID()
        )
        let markerLine = Self.renderMarkerLine(marker)

        if body.isEmpty {
            return markerLine + "\n"
        }

        return markerLine + "\n\n" + body
    }

    func makeProject(
        documentID: UUID? = nil,
        fallbackTitle: String? = nil,
        fallbackAutomationKey: String? = nil
    ) -> WritingProject {
        let resolvedDocumentID = documentID ?? identityMarker?.documentID ?? UUID()
        let resolvedTitle = fallbackTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .ifEmpty(nil) ?? "未命名写作"
        let resolvedAutomationKey = fallbackAutomationKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .ifEmpty(nil) ?? resolvedDocumentID.uuidString.lowercased()
        let cleanedBody = body.removingLeadingNewlines()
        let mode: WritingProjectMode = .collaboration
        let prompt = ""
        let summary = Self.defaultSummary(prompt: prompt, body: cleanedBody, mode: mode)

        return WritingProject(
            id: resolvedDocumentID,
            automationKey: resolvedAutomationKey,
            title: resolvedTitle,
            prompt: prompt,
            mode: mode,
            summary: summary,
            continuationSummary: summary,
            context: ProjectContext.recovered(
                prompt: prompt,
                body: cleanedBody,
                title: resolvedTitle,
                mode: mode
            ),
            conversation: [],
            documentText: cleanedBody,
            suggestionChips: Self.defaultSuggestionChips(prompt: prompt, body: cleanedBody, mode: mode),
            revisionHistory: [],
            updatedAt: .now
        )
    }

    static func parse(from rawText: String) -> VibeWriteMarkdownDocument {
        guard let markerLineRange = rawText.firstLineRange else {
            return VibeWriteMarkdownDocument(identityMarker: nil, body: rawText.removingLeadingNewlines())
        }

        let markerLine = String(rawText[markerLineRange])
        let looksLikeMarkerLine = markerLine.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(Self.markerStartToken)
            && markerLine.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(Self.markerEndToken)
        guard looksLikeMarkerLine else {
            return VibeWriteMarkdownDocument(identityMarker: nil, body: rawText.removingLeadingNewlines())
        }

        let marker = parseIdentityMarker(from: markerLine)
        let remainderStart: String.Index
        if markerLineRange.upperBound < rawText.endIndex {
            remainderStart = rawText.index(after: markerLineRange.upperBound)
        } else {
            remainderStart = rawText.endIndex
        }

        let rawBody = remainderStart < rawText.endIndex ? String(rawText[remainderStart...]) : ""
        return VibeWriteMarkdownDocument(identityMarker: marker, body: rawBody.removingLeadingNewlines())
    }

    static func defaultSummary(prompt: String, body: String, mode: WritingProjectMode) -> String {
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "打开已有正文，继续往下写"
        }

        if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mode == .discussion ? "先聊清楚方向，再生成第一稿" : "等待起稿输入"
        }

        return mode.stageDescription
    }

    static func defaultSuggestionChips(prompt: String, body: String, mode: WritingProjectMode) -> [String] {
        let hasBody = !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasBody {
            return ["继续写", "编辑这段", "补一段"]
        }

        return mode == .discussion ? ["开始起稿", "确认方向", "确认语气"] : ["开始起稿"]
    }

    static func renderMarkerLine(_ marker: VibeWriteDocumentIdentityMarker) -> String {
        let encodedMarker = (try? JSONEncoder.vibeWriteDocumentMarkerEncoder.encode(marker))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "{}"

        return "\(Self.markerStartToken) \(encodedMarker) \(Self.markerEndToken)"
    }

    static func parseIdentityMarker(from rawLine: String) -> VibeWriteDocumentIdentityMarker? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(Self.markerStartToken), trimmed.hasSuffix(Self.markerEndToken) else {
            return nil
        }

        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: Self.markerStartToken.count)
        let endIndex = trimmed.index(trimmed.endIndex, offsetBy: -Self.markerEndToken.count)
        let jsonSlice = trimmed[startIndex..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonSlice.data(using: .utf8),
              let marker = try? JSONDecoder.vibeWriteDocumentMarkerDecoder.decode(VibeWriteDocumentIdentityMarker.self, from: data),
              marker.schemaVersion == VibeWriteDocumentMetadataPolicy.schemaVersion else {
            return nil
        }

        return marker
    }

    static let markerStartToken = "<!-- vibe-write-document"
    static let markerEndToken = "-->"
}

struct VibeWriteDocumentIdentityMarker: Codable, Hashable {
    var schemaVersion: Int
    var documentID: UUID
}

extension ProjectContext {
    static func recovered(prompt: String, body: String, title: String, mode: WritingProjectMode) -> ProjectContext {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasBody = !cleanedBody.isEmpty
        let topic = cleanedPrompt.isEmpty ? (hasBody ? "当前正文" : title) : "“\(cleanedPrompt)”"

        return ProjectContext(
            intentSummary: hasBody
                ? "围绕\(topic)继续协作，先接上当前正文再往下写。"
                : "围绕\(topic)恢复上次的写作状态。",
            styleConstraints: cleanedPrompt.isEmpty ? ["克制", "平静", "非鸡汤"] : ["克制", "平静", "非鸡汤", "避免说教"],
            currentGoal: hasBody ? "继续当前正文" : (mode == .discussion ? "澄清起稿意图" : "等待起稿需求"),
            recentDecisions: hasBody ? ["已打开既有正文", "可以直接继续写"] : [],
            workingMemory: hasBody ? ["正文已经存在", "下一步可以继续推进"] : [],
            nextFocus: hasBody ? "继续推进下一段" : (mode == .discussion ? "完成起稿前共识" : "先开始起稿")
        )
    }
}

private extension JSONEncoder {
    static var vibeWriteDocumentMarkerEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var vibeWriteDocumentMarkerDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    var firstLineRange: Range<String.Index>? {
        guard !isEmpty else {
            return nil
        }

        for index in indices {
            if self[index] == "\n" || self[index] == "\r" {
                return startIndex..<index
            }
        }

        return startIndex..<endIndex
    }

    func ifEmpty(_ fallback: String?) -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func removingLeadingNewlines() -> String {
        var result = self
        while result.hasPrefix("\n") || result.hasPrefix("\r") {
            result.removeFirst()
        }
        return result
    }
}
