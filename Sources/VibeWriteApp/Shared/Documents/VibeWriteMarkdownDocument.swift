import Foundation

struct VibeWriteDocumentMetadata: Codable, Hashable {
    var schemaVersion: Int
    var id: UUID
    var automationKey: String
    var title: String
    var prompt: String
    var summary: String
    var mode: WritingProjectMode
    var updatedAt: Date
    var context: ProjectContext
    var suggestionChips: [String]
}

struct VibeWriteMarkdownDocument: Hashable {
    static let metadataStartMarker = "<!-- vibe-write-metadata"
    static let metadataEndMarker = "-->"

    var metadata: VibeWriteDocumentMetadata
    var body: String

    init(metadata: VibeWriteDocumentMetadata, body: String) {
        self.metadata = metadata
        self.body = body
    }

    init(project: WritingProject) {
        metadata = VibeWriteDocumentMetadata(
            schemaVersion: 1,
            id: project.id,
            automationKey: project.automationKey,
            title: project.title,
            prompt: project.prompt,
            summary: project.summary,
            mode: project.mode,
            updatedAt: project.updatedAt,
            context: project.context,
            suggestionChips: project.suggestionChips
        )
        body = project.documentText
    }

    func renderedText() -> String {
        let encodedMetadata = (try? JSONEncoder.vibeWriteDocumentEncoder.encode(metadata))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "{}"

        if body.isEmpty {
            return "\(Self.metadataStartMarker)\n\(encodedMetadata)\n\(Self.metadataEndMarker)\n"
        }

        return "\(Self.metadataStartMarker)\n\(encodedMetadata)\n\(Self.metadataEndMarker)\n\n\(body)"
    }

    func makeProject(fallbackTitle: String? = nil, fallbackAutomationKey: String? = nil) -> WritingProject {
        let resolvedTitle = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty(fallbackTitle) ?? metadata.mode.defaultTitle
        let resolvedPrompt = metadata.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSummary = metadata.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAutomationKey = metadata.automationKey.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty(fallbackAutomationKey) ?? metadata.id.uuidString.lowercased()

        return WritingProject(
            id: metadata.id,
            automationKey: resolvedAutomationKey,
            title: resolvedTitle,
            prompt: resolvedPrompt,
            mode: metadata.mode,
            summary: resolvedSummary.isEmpty ? Self.defaultSummary(prompt: resolvedPrompt, body: body, mode: metadata.mode) : resolvedSummary,
            context: metadata.context,
            conversation: [],
            documentText: body,
            suggestionChips: Self.normalizedSuggestionChips(metadata.suggestionChips, prompt: resolvedPrompt, body: body, mode: metadata.mode),
            revisionHistory: [],
            updatedAt: metadata.updatedAt
        )
    }

    static func parse(from rawText: String, fallbackTitle: String? = nil, fallbackAutomationKey: String? = nil) -> VibeWriteMarkdownDocument {
        guard let markerStart = rawText.range(of: Self.metadataStartMarker),
              rawText[markerStart.lowerBound...].hasPrefix(Self.metadataStartMarker) else {
            return fallbackDocument(from: rawText, fallbackTitle: fallbackTitle, fallbackAutomationKey: fallbackAutomationKey)
        }

        guard let markerEnd = rawText.range(of: Self.metadataEndMarker, range: markerStart.upperBound..<rawText.endIndex) else {
            return fallbackDocument(from: rawText, fallbackTitle: fallbackTitle, fallbackAutomationKey: fallbackAutomationKey)
        }

        let metadataSlice = rawText[markerStart.upperBound..<markerEnd.lowerBound]
        let bodyStart = rawText.index(markerEnd.upperBound, offsetBy: rawText[markerEnd.upperBound...].hasPrefix("\n") ? 1 : 0, limitedBy: rawText.endIndex) ?? markerEnd.upperBound
        let rawBody = bodyStart < rawText.endIndex ? String(rawText[bodyStart...]) : ""
        let body = rawBody.removingLeadingNewlines()

        guard let metadataData = metadataSlice.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let metadata = try? JSONDecoder.vibeWriteDocumentDecoder.decode(VibeWriteDocumentMetadata.self, from: metadataData) else {
            return fallbackDocument(from: rawBody, fallbackTitle: fallbackTitle, fallbackAutomationKey: fallbackAutomationKey)
        }

        return VibeWriteMarkdownDocument(metadata: metadata, body: body)
    }

    private static func fallbackDocument(
        from rawText: String,
        fallbackTitle: String?,
        fallbackAutomationKey: String?
    ) -> VibeWriteMarkdownDocument {
        let body = rawText.removingLeadingNewlines()
        let trimmedFallbackTitle = fallbackTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmedFallbackTitle?.isEmpty == false ? trimmedFallbackTitle : nil) ?? "未命名写作"
        let mode: WritingProjectMode = .collaboration
        let prompt = ""
        let context = ProjectContext.recovered(
            prompt: prompt,
            body: body,
            title: title,
            mode: mode
        )

        return VibeWriteMarkdownDocument(
            metadata: VibeWriteDocumentMetadata(
                schemaVersion: 1,
                id: UUID(),
                automationKey: {
                    let trimmedFallbackAutomationKey = fallbackAutomationKey?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (trimmedFallbackAutomationKey?.isEmpty == false ? trimmedFallbackAutomationKey : nil) ?? UUID().uuidString.lowercased()
                }(),
                title: title,
                prompt: prompt,
                summary: defaultSummary(prompt: prompt, body: body, mode: mode),
                mode: mode,
                updatedAt: .now,
                context: context,
                suggestionChips: defaultSuggestionChips(prompt: prompt, body: body, mode: mode)
            ),
            body: body
        )
    }

    private static func defaultSummary(prompt: String, body: String, mode: WritingProjectMode) -> String {
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "打开已有正文，继续往下写"
        }

        if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mode == .discussion ? "先聊清楚方向，再生成第一稿" : "等待起稿输入"
        }

        return mode.stageDescription
    }

    private static func defaultSuggestionChips(prompt: String, body: String, mode: WritingProjectMode) -> [String] {
        let hasBody = !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasBody {
            return ["继续写", "编辑这段", "补一段"]
        }

        return mode == .discussion ? ["开始起稿", "确认方向", "确认语气"] : ["开始起稿"]
    }

    private static func normalizedSuggestionChips(_ chips: [String], prompt: String, body: String, mode: WritingProjectMode) -> [String] {
        let trimmed = chips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !trimmed.isEmpty {
            var seen = Set<String>()
            return trimmed.filter { seen.insert($0).inserted }
        }

        return defaultSuggestionChips(prompt: prompt, body: body, mode: mode)
    }
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
    static var vibeWriteDocumentEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var vibeWriteDocumentDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
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
