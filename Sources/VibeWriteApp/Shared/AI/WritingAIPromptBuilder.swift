import Foundation

struct WritingAIPromptBuilder {
    func messages(for request: WritingAIRequest, provider: String, model: String) -> [WritingAIChatMessage] {
        let sanitizedRequest = sanitizedRequest(for: request)

        return [
            WritingAIChatMessage(
                role: .system,
                content: systemPrompt(provider: provider, model: model)
            ),
            WritingAIChatMessage(
                role: .user,
                content: userPrompt(for: sanitizedRequest)
            )
        ]
    }

    private func systemPrompt(provider: String, model: String) -> String {
        """
        You are VibeWrite, a calm macOS writing collaborator.
        Output the writing text first, then append a single metadata block for the app.
        Do not output commentary outside the writing text and metadata block.

        - When the action is "startDraft", write a short opening paragraph or two.
        - When the action is "continueWriting", continue with the next short paragraph or scene.
        - When the action is "edit", return only the replacement text for the selected segment.
        - Keep the output short enough to stream quickly.
        - Stop as soon as the local change is complete.
        - After the prose is finished, output a blank line, then `[[VIBEWRITE_METADATA]]`, then a single JSON object.
        - The metadata JSON must contain: summary, nextFocus, suggestionChips.
        - Keep the metadata specific to the current正文 and actionable for the next step.
        - The metadata block is not part of the正文 and must not be mixed into the prose.
        - When the action is "startDraft", make sure suggestionChips describe concrete next steps after the first draft exists, so the app can show useful follow-up suggestions immediately after the opening is generated.
        - For "startDraft", prefer 3 concise chips that naturally continue the current opening rather than generic start-drafting prompts.

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
        lines.append("Current document:")
        lines.append(request.project.documentText.isEmpty ? "(empty)" : request.project.documentText)

        if let prompt, !prompt.isEmpty {
            lines.append("User message: \(prompt)")
        }

        if let selection, !selection.isEmpty {
            lines.append("Selection: \(selection)")
        }

        if request.action == .startDraft {
            lines.append("For startDraft, return 3 concise suggestion chips that would be useful immediately after this opening is written.")
            lines.append("Those chips should be concrete follow-up actions for the generated opening, not generic drafting prompts.")
        }

        lines.append("Respond with only the writing text for the action above.")
        lines.append("After the prose, output a blank line, then `[[VIBEWRITE_METADATA]]`, then a JSON object with summary, nextFocus, and suggestionChips.")
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
}
