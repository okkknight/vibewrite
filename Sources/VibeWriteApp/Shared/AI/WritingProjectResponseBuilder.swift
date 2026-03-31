import Foundation

enum WritingProjectResponseBuilder {
    static func response(for request: WritingAIRequest) -> WritingAIResponse {
        let action = request.action
        let currentDocument = request.project.documentText
        let selection = request.selectionText
        let prompt = request.userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? request.project.prompt

        let documentText: String
        switch action {
        case .startDraft:
            documentText = MockWritingEngine.firstDraft(for: prompt)

        case .submitMessage:
            documentText = MockWritingEngine.revisedText(
                for: currentDocument,
                selectedSegment: selection,
                action: selection == nil ? .polish : .selectionModify,
                variant: .standard
            )

        case .selectionModify:
            documentText = MockWritingEngine.revisedText(
                for: currentDocument,
                selectedSegment: selection,
                action: .selectionModify,
                variant: .standard
            )

        case .expand:
            documentText = MockWritingEngine.revisedText(
                for: currentDocument,
                selectedSegment: selection,
                action: .expand,
                variant: .standard
            )

        case .shorten:
            documentText = MockWritingEngine.revisedText(
                for: currentDocument,
                selectedSegment: selection,
                action: .shorten,
                variant: .standard
            )

        case .polish, .continueWriting, .proactiveSuggestion:
            documentText = MockWritingEngine.revisedText(
                for: currentDocument,
                selectedSegment: selection,
                action: .polish,
                variant: .standard
            )
        }

        let assistantMessage = MockWritingEngine.assistantLine(
            for: action.toMockAction,
            variant: .standard
        )

        return WritingAIResponse(
            assistantMessage: assistantMessage,
            documentText: documentText,
            summary: summaryText(for: action),
            intentSummary: intentSummary(for: request),
            styleConstraints: styleConstraints(for: request),
            currentGoal: goalText(for: action),
            recentDecisions: decisionText(for: action),
            workingMemory: memoryText(for: action),
            nextFocus: nextFocusText(for: action),
            suggestionChips: suggestionChips(for: request.project.mode),
            mode: action == .startDraft ? .collaboration : request.project.mode
        )
    }

    private static func summaryText(for action: WritingAIAction) -> String {
        switch action {
        case .startDraft:
            return "已生成第一稿，正在收紧开头"
        case .expand:
            return "语气保持克制，但内容往外展开了一点"
        case .shorten:
            return "正文被收紧了一些，节奏更干净"
        case .polish:
            return "正文语气更平了，整体更贴近当前风格"
        case .selectionModify:
            return "局部段落通过选区带入对话完成了修改"
        case .submitMessage:
            return "收到新的协作指令，正文继续更新"
        case .continueWriting:
            return "继续沿着当前主线推进正文"
        case .proactiveSuggestion:
            return "给出下一步建议，帮助继续写下去"
        }
    }

    private static func goalText(for action: WritingAIAction) -> String {
        switch action {
        case .startDraft:
            return "收紧开头"
        case .expand:
            return "继续推进正文"
        case .shorten:
            return "压缩冗余表达"
        case .polish:
            return "调整语气"
        case .selectionModify:
            return "修改选中文段"
        case .submitMessage:
            return "继续响应用户指令"
        case .continueWriting:
            return "推进当前段落"
        case .proactiveSuggestion:
            return "给出下一步建议"
        }
    }

    private static func nextFocusText(for action: WritingAIAction) -> String {
        switch action {
        case .startDraft:
            return "继续推进第一段"
        case .expand:
            return "看下一段要不要继续展开"
        case .shorten:
            return "检查结尾是否还需要再收一点"
        case .polish:
            return "决定要不要进一步降低解释感"
        case .selectionModify:
            return "回到正文，继续局部微调"
        case .submitMessage:
            return "观察用户新的方向，再继续推进"
        case .continueWriting:
            return "沿当前主线补下一段"
        case .proactiveSuggestion:
            return "挑一个建议继续往下写"
        }
    }

    private static func decisionText(for action: WritingAIAction) -> [String] {
        switch action {
        case .startDraft:
            return ["先生成第一稿", "开头保持克制"]
        case .expand:
            return ["保留主线", "让段落再往外延伸一点"]
        case .shorten:
            return ["压掉多余解释", "让节奏更轻"]
        case .polish:
            return ["语气继续收一收", "避免过度抒情"]
        case .selectionModify:
            return ["选区带入对话", "局部修改优先"]
        case .submitMessage:
            return ["跟随用户新的协作指令", "优先保持文脉一致"]
        case .continueWriting:
            return ["保持当前结构", "继续推动文本向前"]
        case .proactiveSuggestion:
            return ["先给下一步建议", "让协作继续推进"]
        }
    }

    private static func memoryText(for action: WritingAIAction) -> [String] {
        switch action {
        case .startDraft:
            return ["正文已经进入协作阶段", "后续修改优先围绕主线推进"]
        case .expand:
            return ["当前在做展开", "不要偏离现在的写作主线"]
        case .shorten:
            return ["当前在做收紧", "避免信息密度太高"]
        case .polish:
            return ["当前在做润色", "保留原意，不做风格大改"]
        case .selectionModify:
            return ["当前在改选中文段", "先局部处理，再回到整体"]
        case .submitMessage:
            return ["正在响应新的用户指令", "保持和上下文一致"]
        case .continueWriting:
            return ["继续沿当前正文推进", "优先保持节奏稳定"]
        case .proactiveSuggestion:
            return ["正在生成下一步建议", "建议要围绕当前主线"]
        }
    }

    private static func intentSummary(for request: WritingAIRequest) -> String {
        switch request.action {
        case .startDraft:
            return "围绕“\(request.project.prompt)”持续协作，正文会直接写入文档而不是停留在聊天里。"
        case .selectionModify:
            return "围绕当前选中文段局部协作，优先保持整体语气和节奏一致。"
        case .expand:
            return "围绕当前正文继续扩写，但不偏离原有主线。"
        case .shorten:
            return "围绕当前正文收紧表达，减少重复和解释感。"
        case .polish:
            return "围绕当前正文润色语气，让表达更克制、更自然。"
        case .submitMessage, .continueWriting, .proactiveSuggestion:
            return request.project.context.intentSummary
        }
    }

    private static func styleConstraints(for request: WritingAIRequest) -> [String] {
        switch request.action {
        case .startDraft:
            return ["克制", "平静", "非鸡汤", "避免说教"]
        case .selectionModify, .expand, .shorten, .polish:
            return request.project.context.styleConstraints
        case .submitMessage, .continueWriting, .proactiveSuggestion:
            return request.project.context.styleConstraints
        }
    }

    private static func suggestionChips(for mode: WritingProjectMode) -> [String] {
        switch mode {
        case .discussion:
            return ["明确主题", "确认语气", "开始起稿"]
        case .collaboration:
            return ["调整语气", "继续展开", "收紧结尾", "降低解释感"]
        }
    }
}

private extension WritingAIAction {
    var toMockAction: MockWritingAction {
        switch self {
        case .startDraft:
            return .startDraft
        case .submitMessage, .continueWriting, .proactiveSuggestion:
            return .polish
        case .selectionModify:
            return .selectionModify
        case .expand:
            return .expand
        case .shorten:
            return .shorten
        case .polish:
            return .polish
        }
    }
}
