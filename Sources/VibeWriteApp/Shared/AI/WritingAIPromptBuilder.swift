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
        Output exactly one JSON object and nothing else.
        Do not wrap the JSON in markdown fences.
        Do not add commentary before or after the JSON.

        The JSON object must contain these keys:
        - assistantMessage: string
        - documentText: string
        - summary: string
        - intentSummary: string
        - styleConstraints: array of strings
        - currentGoal: string
        - recentDecisions: array of strings
        - workingMemory: array of strings
        - nextFocus: string
        - suggestionChips: array of strings
        - mode: one of "discussion" or "collaboration"

        Rules:
        - Keep the writing voice calm, precise, and native to a macOS writing app.
        - Preserve the current article's structure unless the action explicitly changes it.
        - When the action is "startDraft", produce a full first draft in documentText.
        - When the action is "selectionModify", rewrite the selected passage rather than the entire article whenever practical.
        - When the action is "expand", "shorten", or "polish", adjust the current document accordingly.
        - Keep suggestionChips short and action-oriented.
        - Update the context fields so they reflect the current writing state.

        Provider: \(provider)
        Model: \(model)
        """
    }

    private func userPrompt(for request: WritingAIRequest) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(request),
              let json = String(data: data, encoding: .utf8) else {
            return "Return a valid JSON response for the supplied request."
        }

        return """
        Respond to this request as a JSON object:
        \(json)
        """
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

            sanitized.userMessage = nil
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
