import Foundation
import VibeWriteShared

enum WritingProjectResponseBuilder {
    static func response(
        for request: WritingAIRequest,
        documentText: String? = nil,
        assistantMessage: String? = nil,
        metadata: WritingAICompletionMetadata? = nil
    ) -> WritingAIResponse {
        let action = request.action
        let currentDocument = request.project.documentText
        let prompt = request.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? request.project.prompt
        let resolvedDocumentText = documentText ?? fallbackDocumentText(
            for: request,
            prompt: prompt,
            currentDocument: currentDocument
        )
        let resolvedAssistantMessage = assistantMessage ?? MockWritingEngine.assistantLine(
            for: action.toMockAction,
            variant: .standard
        )
        let resolvedLocalSummary = normalizedMetadataValue(metadata?.localSummary)
        let resolvedGlobalSynopsis = normalizedMetadataValue(metadata?.globalSynopsis)
        let resolvedNextFocus = normalizedMetadataValue(metadata?.nextFocus)
        let resolvedSuggestionChips = normalizedSuggestionChips(metadata?.suggestionChips ?? [])

        return WritingAIResponse(
            assistantMessage: resolvedAssistantMessage,
            documentText: resolvedDocumentText,
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

    static func finalDocumentText(for request: WritingAIRequest, streamedText: String) -> String {
        switch request.action {
        case .startDraft:
            return streamedText

        case .continueWriting:
            return request.project.documentText + streamedText

        case .edit:
            guard let targetRange = request.selectionRange?.range(in: request.project.documentText) else {
                return request.project.documentText
            }

            var revised = request.project.documentText
            revised.replaceSubrange(targetRange, with: streamedText)
            return revised
        }
    }

    static func streamedTextChunks(for request: WritingAIRequest) -> [String] {
        MockWritingEngine.streamChunks(for: streamedTextDelta(for: request))
    }

    private static func streamedTextDelta(for request: WritingAIRequest) -> String {
        let finalDocumentText = fallbackDocumentText(
            for: request,
            prompt: request.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? request.project.prompt,
            currentDocument: request.project.documentText
        )

        switch request.action {
        case .startDraft:
            return finalDocumentText

        case .continueWriting:
            return String(finalDocumentText.dropFirst(request.project.documentText.count))

        case .edit:
            guard let targetRange = request.selectionRange?.range(in: request.project.documentText) else {
                return finalDocumentText
            }

            let prefix = String(request.project.documentText[..<targetRange.lowerBound])
            let suffix = String(request.project.documentText[targetRange.upperBound...])
            guard finalDocumentText.hasPrefix(prefix), finalDocumentText.hasSuffix(suffix) else {
                return finalDocumentText
            }

            let lowerBound = finalDocumentText.index(finalDocumentText.startIndex, offsetBy: prefix.count)
            let upperBound = finalDocumentText.index(finalDocumentText.endIndex, offsetBy: -suffix.count)
            return String(finalDocumentText[lowerBound..<upperBound])
        }
    }

    private static func fallbackDocumentText(
        for request: WritingAIRequest,
        prompt: String,
        currentDocument: String
    ) -> String {
        switch request.action {
        case .startDraft:
            return MockWritingEngine.firstDraft(for: prompt)

        case .continueWriting:
            return MockWritingEngine.revisedText(
                for: currentDocument,
                selectedRange: request.selectionRange,
                action: .continueWriting,
                variant: .standard
            )

        case .edit:
            return MockWritingEngine.revisedText(
                for: currentDocument,
                selectedRange: request.selectionRange,
                action: .edit,
                variant: .standard
            )
        }
    }

    private static func goalText(for action: WritingAIAction) -> String {
        switch action {
        case .startDraft:
            return "收紧开头"
        case .continueWriting:
            return "继续写"
        case .edit:
            return "修改选中文段"
        }
    }

    private static func decisionText(for action: WritingAIAction) -> [String] {
        switch action {
        case .startDraft:
            return ["先生成第一稿", "开头保持克制"]
        case .continueWriting:
            return ["继续沿当前主线", "保持节奏稳定"]
        case .edit:
            return ["选区带入对话", "局部修改优先"]
        }
    }

    private static func memoryText(for action: WritingAIAction) -> [String] {
        switch action {
        case .startDraft:
            return ["正文已经进入协作阶段", "后续修改优先围绕主线推进"]
        case .continueWriting:
            return ["继续沿当前正文推进", "优先保持节奏稳定"]
        case .edit:
            return ["当前在改选中文段", "先局部处理，再回到整体"]
        }
    }

    private static func intentSummary(for request: WritingAIRequest) -> String {
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

    private static func styleConstraints(for request: WritingAIRequest) -> [String] {
        switch request.action {
        case .startDraft:
            return ["克制", "平静", "非鸡汤", "避免说教"]
        case .continueWriting, .edit:
            return request.project.context.styleConstraints
        }
    }

    private static func normalizedMetadataValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed
    }

    private static func normalizedSuggestionChips(_ chips: [String]) -> [String] {
        var seen = Set<String>()
        return chips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

}

private extension WritingAIAction {
    var toMockAction: MockWritingAction {
        switch self {
        case .startDraft:
            return .startDraft
        case .continueWriting:
            return .continueWriting
        case .edit:
            return .edit
        }
    }
}
