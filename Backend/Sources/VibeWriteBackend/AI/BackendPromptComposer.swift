import Foundation
import VibeWriteShared

struct BackendPromptComposer {
    func proseMessages(
        for request: WritingAIRequest,
        systemPromptSnapshot: AdminSystemPromptStore.Snapshot,
        configuration: BackendAIConfiguration
    ) throws -> [WritingAIChatMessage] {
        let sanitized = sanitizedRequest(for: request)
        return [
            WritingAIChatMessage(
                role: .system,
                content: proseSystemPrompt(
                    snapshot: systemPromptSnapshot,
                    provider: configuration.provider,
                    model: configuration.model,
                    action: sanitized.action
                )
            ),
            WritingAIChatMessage(
                role: .user,
                content: proseUserPrompt(for: sanitized)
            )
        ]
    }

    func metadataMessages(
        for request: WritingAIRequest,
        systemPromptSnapshot: AdminSystemPromptStore.Snapshot,
        configuration: BackendAIConfiguration
    ) throws -> [WritingAIChatMessage] {
        [
            WritingAIChatMessage(
                role: .system,
                content: metadataSystemPrompt(
                    snapshot: systemPromptSnapshot,
                    provider: configuration.provider,
                    model: configuration.metadataModel,
                    action: request.action,
                    metadataRoute: configuration.metadataRoute
                )
            ),
            WritingAIChatMessage(
                role: .user,
                content: metadataUserPrompt(for: request, metadataRoute: configuration.metadataRoute)
            )
        ]
    }

    private func proseSystemPrompt(
        snapshot: AdminSystemPromptStore.Snapshot,
        provider: String,
        model: String,
        action: WritingAIAction
    ) -> String {
        let actionRules = parseActionRules(from: snapshot.actionRulesJson)?.prose.rules(for: action) ?? []
        let contextRules = parseModelContextRules(from: snapshot.modelContextRulesJson)?.providerModel ?? []

        return renderTemplateLines(
            promptLines(from: snapshot.templateBody)
            + actionRules
            + contextRules,
            provider: provider,
            model: model
        )
        .joined(separator: "\n")
    }

    private func metadataSystemPrompt(
        snapshot: AdminSystemPromptStore.Snapshot,
        provider: String,
        model: String,
        action: WritingAIAction,
        metadataRoute: BackendAIConfiguration.MetadataRoute
    ) -> String {
        let actionRules = parseActionRules(from: snapshot.actionRulesJson)?.metadata.rules(for: action) ?? []
        let routeRules = parseModelContextRules(from: snapshot.modelContextRulesJson)?.metadataRules(for: metadataRoute) ?? []

        var lines = promptLines(from: snapshot.templateBody)
        lines.append(contentsOf: metadataIntroLines(for: metadataRoute))
        lines.append("")
        lines.append(contentsOf: actionRules)
        lines.append("")
        lines.append(contentsOf: routeRules)

        if metadataRoute == .text01JsonSchema {
            lines.append("")
            lines.append("Provider: \(provider)")
            lines.append("Model: \(model)")
        }

        return renderTemplateLines(lines, provider: provider, model: model).joined(separator: "\n")
    }

    private func proseUserPrompt(for request: WritingAIRequest) -> String {
        let prompt = request.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selection = request.selectionText?.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("Action: \(request.action.rawValue)")
        lines.append("Project title: \(request.project.title)")

        switch request.action {
        case .continueWriting:
            lines.append("Global synopsis:")
            lines.append(nonEmptyText(request.project.globalSynopsis, fallback: "(empty)"))
            lines.append("Document tail:")
            lines.append(documentTail(for: request.project.documentText))

        case .startDraft, .edit:
            lines.append("Current document:")
            lines.append(request.project.documentText.isEmpty ? "(empty)" : request.project.documentText)
        }

        if let prompt, !prompt.isEmpty {
            lines.append("User message: \(prompt)")
        }

        if let selection, !selection.isEmpty {
            lines.append("Selection: \(selection)")
        }

        switch request.action {
        case .startDraft:
            lines.append("Write the opening prose for the first draft.")
            lines.append("Keep the opening brief and concrete so it can stand on its own.")
            lines.append("Do not output metadata or commentary.")
        case .continueWriting:
            lines.append("Use the global synopsis as stable context and the document tail as the continuation anchor.")
            lines.append("Do not restart from the beginning of the article.")
            lines.append("Advance the passage only a little; do not turn this into a full ending or a fully closed paragraph.")
            lines.append("Leave a small amount of forward momentum for the next step.")
            lines.append("Keep the continuation brief so the next move still feels natural.")
        case .edit:
            lines.append("Return only the replacement text for the selected segment.")
            lines.append("Rewrite only the selected passage or local region whenever practical.")
            lines.append("After the prose, append a blank line, then [[VIBEWRITE_METADATA]], then a single JSON object with localSummary, globalSynopsis, nextFocus, and suggestionChips.")
            lines.append("Do not mix the metadata into the prose.")
            lines.append("The metadata must be concise, concrete, and in the same language as the current正文.")
        }

        return lines.joined(separator: "\n")
    }

    private func metadataUserPrompt(
        for request: WritingAIRequest,
        metadataRoute: BackendAIConfiguration.MetadataRoute
    ) -> String {
        let prompt = request.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selection = request.selectionText?.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("Action: \(request.action.rawValue) metadata")
        lines.append("Project title: \(request.project.title)")

        switch request.action {
        case .startDraft:
            lines.append("Completed prose:")
            lines.append(documentExcerpt(for: request.project.documentText))
            lines.append("Current global synopsis:")
            lines.append(nonEmptyText(request.project.globalSynopsis, fallback: "(empty)"))

        case .continueWriting:
            lines.append("Completed prose:")
            lines.append(documentTail(for: request.project.documentText))
            lines.append("Current global synopsis:")
            lines.append(nonEmptyText(request.project.globalSynopsis, fallback: "(empty)"))

        case .edit:
            lines.append("Completed prose:")
            lines.append(documentExcerpt(for: request.project.documentText))
            lines.append("Current global synopsis:")
            lines.append(nonEmptyText(request.project.globalSynopsis, fallback: "(empty)"))
        }

        if let prompt, !prompt.isEmpty {
            lines.append("User message: \(prompt)")
        }

        if let selection, !selection.isEmpty {
            lines.append("Selection: \(selection)")
        }

        switch metadataRoute {
        case .current:
            lines.append("Use the `emit_metadata` tool to return localSummary, globalSynopsis, nextFocus, and suggestionChips.")
            lines.append("Make suggestionChips the most concrete part of the response; keep globalSynopsis short and stable.")
            lines.append("Return exactly one `emit_metadata` tool call and nothing else.")
            lines.append("Do not include prose, markdown fences, or commentary.")
            lines.append("Do not produce ordinary assistant text.")
        case .text01JsonSchema:
            lines.append("Return localSummary, globalSynopsis, nextFocus, and suggestionChips only.")
            lines.append("Make suggestionChips the most concrete part of the response; keep globalSynopsis short and stable.")
            lines.append("Do not include prose, markdown fences, or commentary.")
        }

        lines.append("For Chinese writing tasks, keep localSummary, globalSynopsis, nextFocus, and suggestionChips in concise Chinese.")
        lines.append("Return exactly 3 concise suggestion chips.")

        return lines.joined(separator: "\n")
    }

    private func sanitizedRequest(for request: WritingAIRequest) -> WritingAIRequest {
        guard request.action == .startDraft else {
            return request
        }

        var sanitized = request
        let trimmedProjectPrompt = sanitized.project.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserMessage = sanitized.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedUserMessage, !trimmedUserMessage.isEmpty, trimmedUserMessage != trimmedProjectPrompt {
            sanitized.project.prompt = trimmedUserMessage
        }

        if let matchingIndex = sanitized.project.conversation.firstIndex(where: { message in
            message.role == .user && message.text.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedProjectPrompt
        }) {
            sanitized.project.conversation.remove(at: matchingIndex)
        }

        sanitized.project.context.intentSummary = startDraftIntentSummary(for: sanitized.project.mode)
        return sanitized
    }

    private func startDraftIntentSummary(for mode: WritingProjectMode) -> String {
        switch mode {
        case .discussion:
            return "用户想先把方向聊清楚，再开始起稿。"
        case .collaboration:
            return "围绕当前主题持续协作，正文会直接写入文档而不是停留在聊天里。"
        }
    }

    private func nonEmptyText(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func promptLines(from text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }

        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func metadataIntroLines(for route: BackendAIConfiguration.MetadataRoute) -> [String] {
        switch route {
        case .current:
            return [
                "You are VibeWrite metadata-only response builder.",
                "The only valid response is a single `emit_metadata` tool call.",
                "Do not output plain text, prose, markdown fences, JSON, reasoning, or commentary.",
                "Do not answer in any other format.",
                "If you are about to produce ordinary assistant text, stop and emit the tool call instead."
            ]

        case .text01JsonSchema:
            return [
                "You are VibeWrite metadata-only response builder.",
                "Return only the metadata for the completed prose.",
                "Do not output prose, markdown fences, tool calls, or commentary.",
                "Do not answer in plain text."
            ]
        }
    }

    private func renderTemplateLines(_ lines: [String], provider: String, model: String) -> [String] {
        lines.map { line in
            line
                .replacingOccurrences(of: "{provider}", with: provider)
                .replacingOccurrences(of: "{model}", with: model)
        }
    }

    private func documentExcerpt(for text: String, maximumCharacterCount: Int = 900) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "(empty)"
        }

        if trimmed.count <= maximumCharacterCount {
            return trimmed
        }

        return String(trimmed.prefix(maximumCharacterCount))
    }

    private func documentTail(for text: String, maximumCharacterCount: Int = 900) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "(empty)"
        }

        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else {
            return String(trimmed.suffix(maximumCharacterCount))
        }

        var selected: [String] = []
        var characterCount = 0

        for paragraph in paragraphs.reversed() {
            selected.insert(paragraph, at: 0)
            characterCount += paragraph.count
            if characterCount >= maximumCharacterCount && selected.count >= 2 {
                break
            }
        }

        let joined = selected.joined(separator: "\n\n")
        if joined.count <= maximumCharacterCount {
            return joined
        }

        return String(joined.suffix(maximumCharacterCount))
    }
}

private struct BackendActionRulesSnapshot: Decodable {
    let prose: BackendActionPhaseRules
    let metadata: BackendActionPhaseRules
}

private struct BackendActionPhaseRules: Decodable {
    let startDraft: [String]
    let continueWriting: [String]
    let edit: [String]

    func rules(for action: WritingAIAction) -> [String] {
        switch action {
        case .startDraft:
            return startDraft
        case .continueWriting:
            return continueWriting
        case .edit:
            return edit
        }
    }
}

private struct BackendModelContextRulesSnapshot: Decodable {
    let providerModel: [String]
    let metadataRoute: BackendMetadataRouteRules

    func metadataRules(for route: BackendAIConfiguration.MetadataRoute) -> [String] {
        switch route {
        case .current:
            return metadataRoute.current
        case .text01JsonSchema:
            return metadataRoute.text01JsonSchema
        }
    }
}

private struct BackendMetadataRouteRules: Decodable {
    let current: [String]
    let text01JsonSchema: [String]
}

private extension BackendPromptComposer {
    func parseActionRules(from json: String) -> BackendActionRulesSnapshot? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(BackendActionRulesSnapshot.self, from: data)
    }

    func parseModelContextRules(from json: String) -> BackendModelContextRulesSnapshot? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(BackendModelContextRulesSnapshot.self, from: data)
    }
}
