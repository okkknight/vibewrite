import Foundation
import VibeWriteShared

struct BackendPromptComposer {
    func proseMessages(
        for request: WritingAIRequest,
        systemPromptSnapshot: AdminSystemPromptStore.Snapshot,
        configuration: BackendAIConfiguration
    ) throws -> [WritingAIChatMessage] {
        let sanitizedRequest = sanitizedRequest(for: request)
        let promptRules = resolvedPromptRules(from: systemPromptSnapshot)
        let messages = [
            WritingAIChatMessage(
                role: .system,
                content: proseSystemPrompt(
                    promptRules: promptRules,
                    provider: configuration.provider,
                    model: configuration.model,
                    action: sanitizedRequest.action
                )
            ),
            WritingAIChatMessage(
                role: .user,
                content: proseUserPrompt(for: sanitizedRequest)
            )
        ]

        return messages
    }

    func metadataMessages(
        for request: WritingAIRequest,
        systemPromptSnapshot: AdminSystemPromptStore.Snapshot,
        configuration: BackendAIConfiguration
    ) throws -> [WritingAIChatMessage] {
        let promptRules = resolvedPromptRules(from: systemPromptSnapshot)
        return [
            WritingAIChatMessage(
                role: .system,
                content: metadataSystemPrompt(
                    promptRules: promptRules,
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
        promptRules: ResolvedPromptRules,
        provider: String,
        model: String,
        action: WritingAIAction
    ) -> String {
        switch action {
        case .startDraft:
            return composePrompt(
                leading: promptRules.templateBody,
                sections: promptRules.actionRules.prose.lines(for: action) + promptRules.modelContextRules.providerModelLines(provider: provider, model: model)
            )
        case .continueWriting:
            return composePrompt(
                leading: promptRules.templateBody,
                sections: promptRules.actionRules.prose.lines(for: action) + promptRules.modelContextRules.providerModelLines(provider: provider, model: model)
            )
        case .edit:
            return composePrompt(
                leading: promptRules.templateBody,
                sections: promptRules.actionRules.prose.lines(for: action) + promptRules.modelContextRules.providerModelLines(provider: provider, model: model)
            )
        }
    }

    private func metadataSystemPrompt(
        promptRules: ResolvedPromptRules,
        provider: String,
        model: String,
        action: WritingAIAction,
        metadataRoute: BackendAIConfiguration.MetadataRoute
    ) -> String {
        switch metadataRoute {
        case .current:
            let actionLines = promptRules.usesDefaultActionRules
                ? currentMetadataActionLines(for: action)
                : promptRules.actionRules.metadata.lines(for: action)
            return composePrompt(
                leading: promptRules.templateBody,
                sections: metadataIntroLines(for: metadataRoute)
                    + [""]
                    + actionLines
                    + [""]
                    + promptRules.modelContextRules.metadataRouteLines(for: metadataRoute)
            )

        case .text01JsonSchema:
            return composePrompt(
                leading: promptRules.templateBody,
                sections: metadataIntroLines(for: metadataRoute)
                    + [""]
                    + promptRules.actionRules.metadata.lines(for: action)
                    + [""]
                    + promptRules.modelContextRules.metadataRouteLines(for: metadataRoute)
                    + [""]
                    + promptRules.modelContextRules.providerModelLines(provider: provider, model: model)
            )
        }
    }

    private func composePrompt(leading: String, sections: [String]) -> String {
        var lines: [String] = []
        let trimmedLeading = leading.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLeading.isEmpty {
            lines.append(trimmedLeading)
        }
        lines.append(contentsOf: sections)
        return lines.joined(separator: "\n")
    }

    private func resolvedPromptRules(from snapshot: AdminSystemPromptStore.Snapshot) -> ResolvedPromptRules {
        let defaultSnapshot = AdminSystemPromptSeed.makeSnapshot()
        let resolvedActionRules: PromptActionRules = decodedPromptRules(
            from: snapshot.actionRulesJson,
            fallbackJSON: defaultSnapshot.actionRulesJson,
            field: "actionRulesJson"
        )
        let defaultActionRules: PromptActionRules = decodedPromptRules(
            from: defaultSnapshot.actionRulesJson,
            fallbackJSON: defaultSnapshot.actionRulesJson,
            field: "defaultActionRulesJson"
        )
        return ResolvedPromptRules(
            templateBody: normalizedPromptSection(snapshot.templateBody, fallback: defaultSnapshot.templateBody),
            actionRules: resolvedActionRules,
            modelContextRules: decodedPromptRules(
                from: snapshot.modelContextRulesJson,
                fallbackJSON: defaultSnapshot.modelContextRulesJson,
                field: "modelContextRulesJson"
            ),
            usesDefaultActionRules: resolvedActionRules == defaultActionRules
        )
    }

    private func decodedPromptRules<T: Decodable>(
        from rawValue: String,
        fallbackJSON: String,
        field: String
    ) -> T {
        let decoder = JSONDecoder()
        if let decoded = decodePromptRules(T.self, rawValue: rawValue, decoder: decoder, field: field) {
            return decoded
        }
        if let fallback = decodePromptRules(T.self, rawValue: fallbackJSON, decoder: decoder, field: field) {
            return fallback
        }

        fatalError("Failed to decode backend prompt rules for \(field).")
    }

    private func decodePromptRules<T: Decodable>(
        _ type: T.Type,
        rawValue: String,
        decoder: JSONDecoder,
        field: String
    ) -> T? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            return nil
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            return nil
        }
    }

    private func normalizedPromptSection(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
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

        if request.action == .continueWriting {
            lines.append("Use the global synopsis as stable context and the document tail as the continuation anchor.")
            lines.append("Do not restart from the beginning of the article.")
            lines.append("Write the continuation as 1 or 2 short natural paragraphs.")
            lines.append("Let a blank line appear when the focus shifts to a new beat, image, or thought.")
            lines.append("Keep the continuation brief, open-ended, and natural so the next move still has room to breathe.")
        } else if request.action == .edit {
            lines.append("Return only the replacement text for the selected segment.")
            lines.append("Rewrite only the selected passage or local region whenever practical.")
        } else {
            lines.append("Write the opening as 1 or 2 short natural paragraphs.")
            lines.append("Keep the opening brief and concrete, but let it feel like a real start instead of a placeholder sentence.")
            lines.append("Do not output metadata or commentary.")
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
            lines.append("Return exactly one JSON object with localSummary, globalSynopsis, nextFocus, and suggestionChips.")
            lines.append("Do not include prose, markdown fences, or commentary.")
        case .text01JsonSchema:
            lines.append("Return localSummary, globalSynopsis, nextFocus, and suggestionChips only.")
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

    private func metadataIntroLines(for route: BackendAIConfiguration.MetadataRoute) -> [String] {
        switch route {
        case .current:
            return [
                "You are VibeWrite metadata-only response builder.",
                "Return only a single JSON object.",
                "Do not output prose, markdown fences, or commentary.",
                "Do not answer in plain text."
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

    private func currentMetadataActionLines(for action: WritingAIAction) -> [String] {
        switch action {
        case .startDraft:
            return [
                "- Describe the current opening state.",
                "- Suggest the next concrete step after the opening exists.",
                "- Return exactly 3 concise suggestion chips."
            ]
        case .continueWriting:
            return [
                "- Summarize the completed正文 after the continuation.",
                "- Suggest the next concrete step after the continuation.",
                "- Return exactly 3 concise suggestion chips."
            ]
        case .edit:
            return [
                "- Summarize the completed change.",
                "- Suggest the next concrete step after the edit.",
                "- Return exactly 3 concise suggestion chips."
            ]
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

private struct ResolvedPromptRules {
    let templateBody: String
    let actionRules: PromptActionRules
    let modelContextRules: PromptModelContextRules
    let usesDefaultActionRules: Bool
}

private struct PromptActionRules: Decodable, Equatable {
    struct PromptStepRules: Decodable, Equatable {
        let startDraft: [String]
        let continueWriting: [String]
        let edit: [String]

        func lines(for action: WritingAIAction) -> [String] {
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

    let prose: PromptStepRules
    let metadata: PromptStepRules
}

private struct PromptModelContextRules: Decodable {
    struct MetadataRouteRules: Decodable {
        let current: [String]
        let text01JsonSchema: [String]

        func lines(for route: BackendAIConfiguration.MetadataRoute) -> [String] {
            switch route {
            case .current:
                return current
            case .text01JsonSchema:
                return text01JsonSchema
            }
        }
    }

    let providerModel: [String]
    let metadataRoute: MetadataRouteRules

    func providerModelLines(provider: String, model: String) -> [String] {
        providerModel.map { line in
            line
                .replacingOccurrences(of: "{provider}", with: provider)
                .replacingOccurrences(of: "{model}", with: model)
        }
    }

    func metadataRouteLines(for route: BackendAIConfiguration.MetadataRoute) -> [String] {
        metadataRoute.lines(for: route)
    }
}
