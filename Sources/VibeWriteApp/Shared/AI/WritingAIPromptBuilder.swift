import Foundation
import VibeWriteShared

struct WritingAIPromptBuilder {
    func messages(
        for request: WritingAIRequest,
        provider: String,
        model: String,
        metadataRoute: WritingAIConfiguration.MetadataRoute = .current
    ) -> [WritingAIChatMessage] {
        switch request.kind {
        case .prose:
            let sanitizedRequest = sanitizedRequest(for: request)
            return [
                WritingAIChatMessage(
                    role: .system,
                    content: proseSystemPrompt(provider: provider, model: model, action: sanitizedRequest.action)
                ),
                WritingAIChatMessage(
                    role: .user,
                    content: proseUserPrompt(for: sanitizedRequest)
                )
            ]

        case .metadata:
            return [
                WritingAIChatMessage(
                    role: .system,
                    content: metadataSystemPrompt(
                        provider: provider,
                        model: model,
                        action: request.action,
                        metadataRoute: metadataRoute
                    )
                ),
                WritingAIChatMessage(
                    role: .user,
                    content: metadataUserPrompt(for: request, metadataRoute: metadataRoute)
                )
            ]
        }
    }

    private func proseSystemPrompt(provider: String, model: String, action: WritingAIAction) -> String {
        switch action {
        case .startDraft:
            return """
            You are VibeWrite, a calm macOS writing collaborator.
            Output only prose text for the requested action.
            Do not output metadata, JSON, markdown fences, or commentary.
            Keep the output short enough to stream quickly.
            - Write only the opening prose for the first draft.
            - Keep the opening brief and concrete so it can stand on its own.
            - Keep the writing voice calm, precise, and native to a macOS writing app.
            - Preserve the current article's structure unless the action explicitly changes it.
            - When the action is "startDraft", focus on the first usable opening rather than a full outline.
            Provider: \(provider)
            Model: \(model)
            """

        case .continueWriting:
            return """
            You are VibeWrite, a calm macOS writing collaborator.
            Output only prose text for the requested action.
            Do not output metadata, JSON, markdown fences, or commentary.
            Keep the output short enough to stream quickly.
            - Continue the current正文 with the next short paragraph or scene.
            - Advance the passage only a little; do not turn this into a full ending or a fully closed paragraph.
            - Leave a small amount of forward momentum for the next step.
            - Keep the writing voice calm, precise, and native to a macOS writing app.
            - Preserve the current article's structure unless the action explicitly changes it.
            - When the action is "continueWriting", continue the existing正文 instead of restarting the article.
            Provider: \(provider)
            Model: \(model)
            """

        case .edit:
            return """
            You are VibeWrite, a calm macOS writing collaborator.
            Output the writing text first, then append exactly one metadata block for the app.
            Do not output commentary outside the writing text and metadata block.
            A response is incomplete until the metadata block is present.
            - When the action is "edit", return only the replacement text for the selected segment.
            - Keep the output short enough to stream quickly.
            - Do not stop after writing text alone.
            - After the prose is finished, output a blank line, then `[[VIBEWRITE_METADATA]]`, then a single JSON object.
            - The metadata JSON must contain: localSummary, globalSynopsis, nextFocus, suggestionChips.
            - Keep the metadata specific to the current正文 and actionable for the next step.
            - Match the metadata language to the language of the current正文 and user request.
            - For Chinese writing tasks, localSummary, globalSynopsis, nextFocus, and suggestionChips must be concise Chinese.
            - The metadata block is not part of the正文 and must not be mixed into the prose.
            - Every response must end with exactly one metadata block.
            - When the action is "edit", rewrite only the selected passage or local region whenever practical.
            - Keep the prose concise enough for streaming.
            - The metadata JSON should stay concise and concrete, not templated.

            Rules:
            - Keep the writing voice calm, precise, and native to a macOS writing app.
            - Preserve the current article's structure unless the action explicitly changes it.
            - When the action is "edit", rewrite only the selected passage or local region whenever practical.

            Provider: \(provider)
            Model: \(model)
            """
        }
    }

    private func metadataSystemPrompt(
        provider: String,
        model: String,
        action: WritingAIAction,
        metadataRoute: WritingAIConfiguration.MetadataRoute
    ) -> String {
        let actionInstructions: String
        switch action {
        case .startDraft:
            actionInstructions = """
            - Return suggestionChips as the primary output and keep them concrete.
            - Describe the current opening state as the local summary.
            - Keep the global synopsis short and stable; it should preserve broader story state without repeating the local summary.
            - Suggest the next concrete step after the opening exists.
            - Return exactly 3 concise suggestion chips.
            """
        case .continueWriting:
            actionInstructions = """
            - Return suggestionChips as the primary output and keep them concrete.
            - Describe the completed正文 as the local summary.
            - Keep the global synopsis short and stable; it should preserve broader story state without repeating the local summary.
            - Suggest the next concrete step after the continuation.
            - Return exactly 3 concise suggestion chips.
            """
        case .edit:
            actionInstructions = """
            - Return suggestionChips as the primary output and keep them concrete.
            - Describe the completed change as the local summary.
            - Keep the global synopsis short and stable; it should preserve broader story state without repeating the local summary.
            - Suggest the next concrete step after the edit.
            - Return exactly 3 concise suggestion chips.
            """
        }

        switch metadataRoute {
        case .current:
            return """
            You are VibeWrite metadata-only response builder.
            The only valid response is a single `emit_metadata` tool call.
            Do not output plain text, prose, markdown fences, JSON, reasoning, or commentary.
            Do not answer in any other format.
            If you are about to produce ordinary assistant text, stop and emit the tool call instead.

            \(actionInstructions)

            - Keep the metadata specific to the current正文 and actionable for the next step.
            - Treat suggestionChips as the most important field and do not let globalSynopsis crowd it out.
            - Keep localSummary brief, keep globalSynopsis stable and short, and let suggestionChips stay concrete.
            - Match the metadata language to the language of the current正文 and user request.
            - For Chinese writing tasks, localSummary, globalSynopsis, nextFocus, and suggestionChips must be concise Chinese.
            - suggestionChips must be concise, concrete, and non-generic.
            """

        case .text01JsonSchema:
            return """
            You are VibeWrite metadata-only response builder.
            Return only the metadata for the completed prose.
            Do not output prose, markdown fences, tool calls, or commentary.
            Do not answer in plain text.

            \(actionInstructions)

            - Keep the metadata specific to the current正文 and actionable for the next step.
            - Treat suggestionChips as the most important field and do not let globalSynopsis crowd it out.
            - Keep localSummary brief, keep globalSynopsis stable and short, and let suggestionChips stay concrete.
            - Match the metadata language to the language of the current正文 and user request.
            - For Chinese writing tasks, localSummary, globalSynopsis, nextFocus, and suggestionChips must be concise Chinese.
            - suggestionChips must be concise, concrete, and non-generic.
            - The response format is schema-enforced, so do not wrap the metadata in extra text.

            Provider: \(provider)
            Model: \(model)
            """
        }
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
            lines.append("Advance the passage only a little; do not turn this into a full ending or a fully closed paragraph.")
            lines.append("Leave a small amount of forward momentum for the next step.")
            lines.append("Keep the continuation brief so the next move still feels natural.")
        } else if request.action == .edit {
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
        metadataRoute: WritingAIConfiguration.MetadataRoute
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

        if let trimmedUserMessage, !trimmedUserMessage.isEmpty {
            if trimmedUserMessage != trimmedProjectPrompt {
                sanitized.project.prompt = trimmedUserMessage
            }
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
