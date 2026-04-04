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
    let leadingContext: String?
    let trailingContext: String?
    let replacementText: String
    let userMessage: String?
    let summary: String
    let createdAt: Date

    init(
        action: WritingAIAction,
        lockedSelectionText: String?,
        sourceText: String?,
        leadingContext: String? = nil,
        trailingContext: String? = nil,
        replacementText: String,
        userMessage: String?,
        summary: String,
        createdAt: Date = .now
    ) {
        self.action = action
        self.lockedSelectionText = lockedSelectionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceText = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.leadingContext = leadingContext
        self.trailingContext = trailingContext
        self.replacementText = replacementText
        self.userMessage = userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary
        self.createdAt = createdAt
    }

    static func build(
        action: WritingAIAction,
        before: WritingProjectSnapshot,
        after: WritingProjectSnapshot,
        selectionText: String?,
        userMessage: String?
    ) throws -> WritingEditPatch {
        let trimmedSelection = selectionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelection = trimmedSelection.flatMap { $0.isEmpty ? nil : $0 }

        switch action {
        case .startDraft:
            let replacementText = after.documentText
            guard !replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WritingEditPatchError.noPatchResult
            }

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

            return WritingEditPatch(
                action: action,
                lockedSelectionText: nil,
                sourceText: nil,
                replacementText: appendedText,
                userMessage: userMessage,
                summary: summaryText(for: action, sourceText: nil)
            )

        case .edit:
            guard let sourceText = normalizedSelection else {
                throw WritingEditPatchError.missingSelection
            }

            guard let targetRange = before.documentText.range(of: sourceText) else {
                throw WritingEditPatchError.patchContextMismatch
            }

            let leadingContext = localContext(
                in: before.documentText,
                around: targetRange.lowerBound,
                limit: 72,
                direction: .leading
            )
            let trailingContext = localContext(
                in: before.documentText,
                around: targetRange.upperBound,
                limit: 72,
                direction: .trailing
            )

            let prefix = String(before.documentText[..<targetRange.lowerBound])
            let suffix = String(before.documentText[targetRange.upperBound...])
            guard after.documentText.hasPrefix(prefix), after.documentText.hasSuffix(suffix) else {
                throw WritingEditPatchError.patchContextMismatch
            }

            let lowerBound = after.documentText.index(after.documentText.startIndex, offsetBy: prefix.count)
            let upperBound = after.documentText.index(after.documentText.endIndex, offsetBy: -suffix.count)
            let replacementText = String(after.documentText[lowerBound..<upperBound])

            return WritingEditPatch(
                action: action,
                lockedSelectionText: sourceText,
                sourceText: sourceText,
                leadingContext: leadingContext,
                trailingContext: trailingContext,
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

            let targetContext = (leadingContext ?? "") + sourceText + (trailingContext ?? "")
            guard let targetRange = documentText.range(of: targetContext) else {
                throw WritingEditPatchError.patchContextMismatch
            }

            let sourceStart = documentText.index(targetRange.lowerBound, offsetBy: leadingContext?.count ?? 0)
            let sourceEnd = documentText.index(sourceStart, offsetBy: sourceText.count)
            var updated = documentText
            updated.replaceSubrange(sourceStart..<sourceEnd, with: replacementText)
            return updated
        }
    }
}

private enum WritingEditContextDirection {
    case leading
    case trailing
}

private func localContext(
    in text: String,
    around index: String.Index,
    limit: Int,
    direction: WritingEditContextDirection
) -> String {
    switch direction {
    case .leading:
        let startIndex = text.index(
            index,
            offsetBy: -min(limit, text.distance(from: text.startIndex, to: index)),
            limitedBy: text.startIndex
        ) ?? text.startIndex
        return String(text[startIndex..<index])

    case .trailing:
        let remaining = text.distance(from: index, to: text.endIndex)
        let endIndex = text.index(
            index,
            offsetBy: min(limit, remaining),
            limitedBy: text.endIndex
        ) ?? text.endIndex
        return String(text[index..<endIndex])
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
