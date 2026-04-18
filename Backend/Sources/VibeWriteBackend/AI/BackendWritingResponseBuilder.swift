import Foundation
import VibeWriteShared

struct BackendWritingResponseBuilder {
    func response(
        for request: WritingAIRequest,
        documentText: String,
        metadata: WritingAICompletionMetadata? = nil,
        assistantMessage: String? = nil
    ) -> WritingAIResponse {
        let action = request.action
        let resolvedAssistantMessage = assistantMessage ?? assistantLine(for: action)
        let resolvedLocalSummary = normalizedMetadataValue(metadata?.localSummary)
        let resolvedGlobalSynopsis = normalizedMetadataValue(metadata?.globalSynopsis)
        let resolvedNextFocus = normalizedMetadataValue(metadata?.nextFocus)
        let resolvedSuggestionChips = normalizedSuggestionChips(metadata?.suggestionChips ?? [])

        return WritingAIResponse(
            assistantMessage: resolvedAssistantMessage,
            documentText: documentText,
            localSummary: resolvedLocalSummary,
            globalSynopsis: resolvedGlobalSynopsis,
            intentSummary: intentSummary(for: request),
            styleConstraints: styleConstraints(for: request),
            currentGoal: goalText(for: action),
            recentDecisions: decisionText(for: action),
            workingMemory: memoryText(for: action),
            nextFocus: resolvedNextFocus,
            suggestionChips: resolvedSuggestionChips,
            mode: action == .startDraft ? .collaboration : request.project.mode
        )
    }

    func assistantLine(for action: WritingAIAction) -> String {
        switch action {
        case .startDraft:
            return "我已经根据你的方向起了一版第一稿。"
        case .continueWriting:
            return "我接着往下写了一段，让主线继续往前走。"
        case .edit:
            return "我按你选中的那段改了一版。"
        }
    }

    func updatedProjectSnapshot(
        for request: WritingAIRequest,
        documentText: String,
        assistantMessage: String? = nil
    ) -> WritingProjectSnapshot {
        var snapshot = request.project
        snapshot.documentText = documentText
        if let assistantMessage {
            snapshot.conversation.append(
                ConversationMessage(
                    role: .assistant,
                    text: assistantMessage,
                    timestamp: "AI · 刚刚"
                )
            )
        }
        return snapshot
    }

    func appliedDocumentText(
        for request: WritingAIRequest,
        proseText: String
    ) throws -> String {
        switch request.action {
        case .startDraft:
            return proseText

        case .continueWriting:
            return request.project.documentText + proseText

        case .edit:
            guard let range = request.selectionRange?.range(in: request.project.documentText) else {
                throw BackendAIError.invalidRequest("A valid selectionRange is required for edit requests.")
            }

            var revised = request.project.documentText
            revised.replaceSubrange(range, with: proseText)
            return revised
        }
    }

    private func intentSummary(for request: WritingAIRequest) -> String {
        switch request.action {
        case .startDraft:
            let sourcePrompt = request.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? request.project.prompt
            return "围绕“\(sourcePrompt)”持续协作，正文会直接写入文档而不是停留在聊天里。"
        case .continueWriting:
            return "围绕当前正文继续往下写一段，让主线自然往前推进。"
        case .edit:
            return "围绕当前选中文段局部协作，优先保持整体语气和节奏一致。"
        }
    }

    private func styleConstraints(for request: WritingAIRequest) -> [String] {
        switch request.action {
        case .startDraft:
            return ["克制", "平静", "非鸡汤", "避免说教"]
        case .continueWriting, .edit:
            return request.project.context.styleConstraints
        }
    }

    private func goalText(for action: WritingAIAction) -> String {
        switch action {
        case .startDraft:
            return "收紧开头"
        case .continueWriting:
            return "继续写"
        case .edit:
            return "修改选中文段"
        }
    }

    private func decisionText(for action: WritingAIAction) -> [String] {
        switch action {
        case .startDraft:
            return ["先生成第一稿", "开头保持克制"]
        case .continueWriting:
            return ["继续沿当前主线", "保持节奏稳定"]
        case .edit:
            return ["选区带入对话", "局部修改优先"]
        }
    }

    private func memoryText(for action: WritingAIAction) -> [String] {
        switch action {
        case .startDraft:
            return ["正文已经进入协作阶段", "后续修改优先围绕主线推进"]
        case .continueWriting:
            return ["继续沿当前正文推进", "优先保持节奏稳定"]
        case .edit:
            return ["当前在改选中文段", "先局部处理，再回到整体"]
        }
    }

    private func normalizedMetadataValue(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func normalizedSuggestionChips(_ chips: [String]) -> [String] {
        var seen = Set<String>()
        return chips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}
