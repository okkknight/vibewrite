import Foundation

struct WritingAIPromptBuilder {
    func messages(for request: WritingAIRequest, provider: String, model: String) -> [WritingAIChatMessage] {
        let sanitizedRequest = sanitizedRequest(for: request)
        let systemPrompt = systemPrompt(provider: provider, model: model)
        let userPrompt = userPrompt(for: sanitizedRequest)

        return [
            WritingAIChatMessage(
                role: .system,
                content: systemPrompt
            ),
            WritingAIChatMessage(
                role: .user,
                content: userPrompt
            )
        ]
    }

    private func systemPrompt(provider: String, model: String) -> String {
        """
        You are VibeWrite, a calm macOS writing collaborator.
        Output the writing text first, then append exactly one metadata block for the app.
        Do not output commentary outside the writing text and metadata block.
        A response is incomplete until the metadata block is present.

        - When the action is "startDraft", write a short opening paragraph or two.
        - When the action is "continueWriting", continue with the next short paragraph or scene.
        - When the action is "edit", return only the replacement text for the selected segment.
        - Keep the output short enough to stream quickly.
        - Do not stop after writing text alone.
        - After the prose is finished, output a blank line, then `[[VIBEWRITE_METADATA]]`, then a single JSON object.
        - The metadata JSON must contain: summary, nextFocus, suggestionChips.
        - Keep the metadata specific to the current正文 and actionable for the next step.
        - Match the metadata language to the language of the current正文 and user request.
        - For Chinese writing tasks, summary, nextFocus, and suggestionChips must be concise Chinese.
        - The metadata block is not part of the正文 and must not be mixed into the prose.
        - Every response must end with exactly one metadata block.
        - When the action is "startDraft", always return a complete metadata block even if the opening is short.
        - When the action is "startDraft", make sure suggestionChips describe concrete next steps after the first draft exists, so the app can show useful follow-up suggestions immediately after the opening is generated.
        - For "startDraft", prefer 3 concise chips that naturally continue the current opening rather than generic start-drafting prompts.
        - For "startDraft", keep summary concise and state the opening's current condition, keep nextFocus concrete, and keep suggestionChips directly actionable.
        - When the action is "continueWriting", suggestionChips must contain exactly 3 items.
        - When the action is "continueWriting", prefer 3 concise chips that follow the current正文 naturally, are concrete, and help the app suggest what to do next.
        - When the action is "continueWriting", suggestionChips must not be generic continuation prompts.
        - When the action is "continueWriting", treat the document summary as global context and the document tail as the local anchor for continuation; do not restart from the beginning of the article.

        Rules:
        - Keep the writing voice calm, precise, and native to a macOS writing app.
        - Preserve the current article's structure unless the action explicitly changes it.
        - When the action is "startDraft", focus on the first usable opening rather than a full outline.
        - When the action is "continueWriting", continue the existing正文 instead of restarting the article.
        - When the action is "edit", rewrite only the selected passage or local region whenever practical.
        - Keep the prose concise enough for streaming.
        - The metadata JSON should stay concise and concrete, not templated.

        Provider: \(provider)
        Model: \(model)
        """
    }

    private func userPrompt(for request: WritingAIRequest) -> String {
        let prompt = request.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selection = request.selectionText?.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("Action: \(request.action.rawValue)")
        lines.append("Project title: \(request.project.title)")

        switch request.action {
        case .continueWriting:
            lines.append("Document summary:")
            lines.append(nonEmptyText(request.project.continuationSummary, fallback: "(empty)"))
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

        if request.action == .startDraft {
            lines.append("For startDraft, the metadata block is required and must include summary, nextFocus, and exactly 3 concise suggestion chips.")
            lines.append("The summary should briefly describe the current opening state, nextFocus should name the next concrete step, and suggestionChips should be the most useful immediate follow-up actions.")
            lines.append("For startDraft, return 3 concise suggestion chips that would be useful immediately after this opening is written.")
            lines.append("Those chips should be concrete follow-up actions for the generated opening, not generic drafting prompts.")
        } else if request.action == .continueWriting {
            lines.append("Use the document summary as global context and the document tail as the continuation anchor.")
            lines.append("Do not restart from the beginning of the article.")
            lines.append("For continueWriting, suggestionChips must contain exactly 3 concise items.")
            lines.append("Those chips should be concrete next steps that naturally follow the current正文 and should not be generic continuation prompts.")
        }

        lines.append("Required output shape:")
        lines.append("<prose>")
        lines.append("")
        lines.append("[[VIBEWRITE_METADATA]]")
        lines.append("exactly one JSON object with summary, nextFocus, and suggestionChips")
        lines.append("{\"summary\":\"...\",\"nextFocus\":\"...\",\"suggestionChips\":[\"...\",\"...\",\"...\"]}")
        lines.append("Write the metadata in the same language as the current正文 and user request; for Chinese writing tasks, keep summary, nextFocus, and suggestionChips in concise Chinese.")
        lines.append("Do not wrap the metadata JSON in markdown fences.")

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

    private func joinedOrFallback(_ items: [String], fallback: String) -> String {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else {
            return fallback
        }

        return cleaned.joined(separator: " · ")
    }
}
