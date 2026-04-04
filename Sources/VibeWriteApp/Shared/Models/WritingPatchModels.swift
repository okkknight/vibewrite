import Foundation

enum WritingEditPatchError: LocalizedError, Hashable {
    case missingSelection
    case lockMismatch
    case nonLocalContinuation
    case patchContextMismatch
    case noPatchResult

    var errorDescription: String? {
        switch self {
        case .missingSelection:
            return "缺少可用于局部 patch 的选区。"
        case .lockMismatch:
            return "正文锁已失配，当前 patch 已取消。"
        case .nonLocalContinuation:
            return "续写结果没有保持对当前正文的局部追加。"
        case .patchContextMismatch:
            return "局部 patch 上下文失配，正文未被修改。"
        case .noPatchResult:
            return "AI 返回结果没有形成可应用的 patch。"
        }
    }
}

struct WritingEditLock: Codable, Hashable {
    let action: WritingAIAction
    let lockedSelectionText: String?
    let lockedDocumentText: String
    let createdAt: Date

    init(
        action: WritingAIAction,
        lockedSelectionText: String?,
        lockedDocumentText: String,
        createdAt: Date = .now
    ) {
        self.action = action
        self.lockedSelectionText = lockedSelectionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lockedDocumentText = lockedDocumentText
        self.createdAt = createdAt
    }

    var statusText: String {
        switch action {
        case .startDraft:
            return "起稿中，正文已锁定"
        case .continueWriting:
            return "续写中，正文已锁定"
        case .edit:
            return lockedSelectionText == nil ? "编辑中，正文已锁定" : "正在锁定选区"
        }
    }

    func matches(documentText: String) -> Bool {
        lockedDocumentText == documentText
    }
}

struct WritingEditPatch: Codable, Hashable {
    let action: WritingAIAction
    let lockedSelectionText: String?
    let sourceText: String?
    let sourceRange: WritingTextSelectionRange?
    let replacementText: String
    let userMessage: String?
    let summary: String
    let createdAt: Date

    init(
        action: WritingAIAction,
        lockedSelectionText: String?,
        sourceText: String?,
        sourceRange: WritingTextSelectionRange? = nil,
        replacementText: String,
        userMessage: String?,
        summary: String,
        createdAt: Date = .now
    ) {
        VibeWriteLog.ai.notice(
            "WritingEditPatch.init begin action=\(action.rawValue, privacy: .public) lockedSelectionText=\(lockedSelectionText?.vibewriteLogPreview(maxLength: 60) ?? "nil", privacy: .public) sourceText=\(sourceText?.vibewriteLogPreview(maxLength: 60) ?? "nil", privacy: .public) sourceRange=\(sourceRange?.nsRange.debugDescription ?? "nil", privacy: .public) replacementCount=\(replacementText.count, privacy: .public) userMessage=\(userMessage?.vibewriteLogPreview(maxLength: 60) ?? "nil", privacy: .public) summary=\(summary.vibewriteLogPreview(maxLength: 60), privacy: .public)"
        )
        self.action = action
        VibeWriteLog.ai.notice("WritingEditPatch.init assigned action")
        self.lockedSelectionText = lockedSelectionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        VibeWriteLog.ai.notice("WritingEditPatch.init assigned lockedSelectionText")
        self.sourceText = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines)
        VibeWriteLog.ai.notice("WritingEditPatch.init assigned sourceText")
        self.sourceRange = sourceRange
        VibeWriteLog.ai.notice("WritingEditPatch.init assigned sourceRange")
        self.replacementText = replacementText
        VibeWriteLog.ai.notice("WritingEditPatch.init assigned replacementText")
        self.userMessage = userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        VibeWriteLog.ai.notice("WritingEditPatch.init assigned userMessage")
        self.summary = summary
        VibeWriteLog.ai.notice("WritingEditPatch.init assigned summary")
        self.createdAt = createdAt
        VibeWriteLog.ai.notice("WritingEditPatch.init finished")
    }

    static func build(
        action: WritingAIAction,
        before: WritingProjectSnapshot,
        after: WritingProjectSnapshot,
        selectionRange: WritingTextSelectionRange? = nil,
        userMessage: String?
    ) throws -> WritingEditPatch {
        switch action {
        case .startDraft:
            let replacementText = after.documentText
            guard !replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WritingEditPatchError.noPatchResult
            }

            VibeWriteLog.ai.notice(
                "WritingEditPatch.build startDraft beforeCount=\(before.documentText.count, privacy: .public) afterCount=\(after.documentText.count, privacy: .public) replacementCount=\(replacementText.count, privacy: .public)"
            )

            return WritingEditPatch(
                action: action,
                lockedSelectionText: nil,
                sourceText: nil,
                replacementText: replacementText,
                userMessage: userMessage,
                summary: summaryText(for: action, sourceText: nil)
            )

        case .continueWriting:
            guard after.documentText.hasPrefix(before.documentText) else {
                throw WritingEditPatchError.nonLocalContinuation
            }

            let appendedText = String(after.documentText.dropFirst(before.documentText.count))
            guard !appendedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WritingEditPatchError.noPatchResult
            }

            VibeWriteLog.ai.notice(
                "WritingEditPatch.build continueWriting beforeCount=\(before.documentText.count, privacy: .public) afterCount=\(after.documentText.count, privacy: .public) appendedCount=\(appendedText.count, privacy: .public)"
            )

            return WritingEditPatch(
                action: action,
                lockedSelectionText: nil,
                sourceText: nil,
                replacementText: appendedText,
                userMessage: userMessage,
                summary: summaryText(for: action, sourceText: nil)
            )

        case .edit:
            guard let sourceTextRange = selectionRange?.range(in: before.documentText) else {
                throw WritingEditPatchError.missingSelection
            }

            let sourceRange = WritingTextSelectionRange(NSRange(sourceTextRange, in: before.documentText))

            guard let sourceText = sourceRange.substring(in: before.documentText)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !sourceText.isEmpty else {
                throw WritingEditPatchError.missingSelection
            }

            guard let targetRange = sourceRange.range(in: before.documentText) else {
                throw WritingEditPatchError.patchContextMismatch
            }

            let prefix = String(before.documentText[..<targetRange.lowerBound])
            let suffix = String(before.documentText[targetRange.upperBound...])
            guard after.documentText.hasPrefix(prefix), after.documentText.hasSuffix(suffix) else {
                throw WritingEditPatchError.patchContextMismatch
            }

            let lowerBound = after.documentText.index(after.documentText.startIndex, offsetBy: prefix.count)
            let upperBound = after.documentText.index(after.documentText.endIndex, offsetBy: -suffix.count)
            let replacementText = String(after.documentText[lowerBound..<upperBound])

            VibeWriteLog.ai.notice(
                "WritingEditPatch.build edit beforeCount=\(before.documentText.count, privacy: .public) afterCount=\(after.documentText.count, privacy: .public) sourceRange=\(sourceRange.nsRange.debugDescription, privacy: .public) sourceTextPreview=\(sourceText.vibewriteLogPreview(maxLength: 60), privacy: .public) replacementCount=\(replacementText.count, privacy: .public)"
            )

            return WritingEditPatch(
                action: action,
                lockedSelectionText: sourceText,
                sourceText: sourceText,
                sourceRange: sourceRange,
                replacementText: replacementText,
                userMessage: userMessage,
                summary: summaryText(for: action, sourceText: sourceText)
            )
        }
    }

    var isLocalEdit: Bool {
        action == .edit
    }

    var scopeLabel: String {
        switch action {
        case .startDraft:
            return "起稿"
        case .continueWriting:
            return "续写"
        case .edit:
            return sourceText == nil ? "正文编辑" : "局部 patch"
        }
    }

    private static func summaryText(for action: WritingAIAction, sourceText: String?) -> String {
        switch action {
        case .startDraft:
            return "起草第一版正文"
        case .continueWriting:
            return "顺着当前正文继续往下写"
        case .edit:
            if let sourceText {
                return "围绕选中文段进行局部 patch：\(sourceText)"
            }

            return "围绕正文局部 patch 修改"
        }
    }

    func apply(to documentText: String, lock: WritingEditLock?) throws -> String {
        if let lock, !lock.matches(documentText: documentText) {
            throw WritingEditPatchError.lockMismatch
        }

        switch action {
        case .startDraft:
            guard documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WritingEditPatchError.lockMismatch
            }

            return replacementText

        case .continueWriting:
            return documentText + replacementText

        case .edit:
            guard let sourceText, !sourceText.isEmpty else {
                throw WritingEditPatchError.missingSelection
            }

            guard let sourceRange, let targetRange = sourceRange.range(in: documentText) else {
                throw WritingEditPatchError.patchContextMismatch
            }

            var updated = documentText
            updated.replaceSubrange(targetRange, with: replacementText)
            return updated
        }
    }
}

struct WritingProjectRevision: Identifiable, Hashable, Codable {
    let id: UUID
    let patch: WritingEditPatch
    let before: WritingProjectSnapshot
    let after: WritingProjectSnapshot
    let createdAt: Date

    init(
        id: UUID = UUID(),
        patch: WritingEditPatch,
        before: WritingProjectSnapshot,
        after: WritingProjectSnapshot,
        createdAt: Date = .now
    ) {
        self.id = id
        self.patch = patch
        self.before = before
        self.after = after
        self.createdAt = createdAt
    }

    var action: WritingAIAction {
        patch.action
    }

    var lockedSelectionText: String? {
        patch.lockedSelectionText
    }

    var lockedSelectionRange: WritingTextSelectionRange? {
        patch.sourceRange
    }

    var title: String {
        switch patch.action {
        case .startDraft:
            return "起稿"
        case .continueWriting:
            return "继续写作"
        case .edit:
            return "局部 patch"
        }
    }

    var subtitle: String {
        if let lockedSelectionText, !lockedSelectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "围绕选中文段：\(lockedSelectionText)"
        }

        return patch.summary
    }
}
