import Foundation
@testable import VibeWriteBackend
import VibeWriteShared

func makeGatewayStartRequest(
    installationId: String,
    deviceToken: String,
    requestId: String,
    project: WritingProjectSnapshot,
    kind: WritingAIRequestKind = .prose,
    userMessage: String? = nil
) -> WriteRequestEnvelope {
    WriteRequestEnvelope(
        installationId: installationId,
        deviceToken: deviceToken,
        requestId: requestId,
        action: .startDraft,
        kind: kind,
        startProject: project,
        userMessage: userMessage
    )
}

func makeGatewayContinueRequest(
    installationId: String,
    deviceToken: String,
    requestId: String,
    project: WritingProjectSnapshot,
    kind: WritingAIRequestKind = .prose,
    userMessage: String? = nil,
    tailText: String? = nil
) -> WriteRequestEnvelope {
    let resolvedTailText = tailText ?? project.documentText
    return WriteRequestEnvelope(
        installationId: installationId,
        deviceToken: deviceToken,
        requestId: requestId,
        action: .continueWriting,
        kind: kind,
        sessionContext: makeGatewaySessionContext(from: project),
        continueWindow: WritingGatewayTailWindow(
            tailText: resolvedTailText,
            totalCharacterCount: project.documentText.count,
            tailCharacterCount: resolvedTailText.count,
            isTruncated: resolvedTailText != project.documentText
        ),
        userMessage: userMessage
    )
}

func makeGatewayEditRequest(
    installationId: String,
    deviceToken: String,
    requestId: String,
    project: WritingProjectSnapshot,
    selectionRange: WritingTextSelectionRange,
    kind: WritingAIRequestKind = .prose,
    userMessage: String? = nil,
    strategy: WritingGatewayEditWindowStrategy = .focused
) -> WriteRequestEnvelope {
    WriteRequestEnvelope(
        installationId: installationId,
        deviceToken: deviceToken,
        requestId: requestId,
        action: .edit,
        kind: kind,
        sessionContext: makeGatewaySessionContext(from: project),
        editWindow: makeGatewayEditWindow(
            documentText: project.documentText,
            selectionRange: selectionRange,
            strategy: strategy
        ),
        userMessage: userMessage
    )
}

func makeGatewaySessionContext(from project: WritingProjectSnapshot) -> WritingGatewaySessionContext {
    WritingGatewaySessionContext(
        title: project.title,
        prompt: project.prompt,
        mode: project.mode,
        localSummary: project.localSummary,
        globalSynopsis: project.globalSynopsis,
        context: project.context,
        suggestionChips: project.suggestionChips
    )
}

func makeGatewayEditWindow(
    documentText: String,
    selectionRange: WritingTextSelectionRange,
    strategy: WritingGatewayEditWindowStrategy = .focused
) -> WritingGatewayEditWindow {
    guard let range = selectionRange.range(in: documentText) else {
        return WritingGatewayEditWindow(
            beforeContextText: documentText,
            selectionText: "",
            afterContextText: "",
            totalCharacterCount: documentText.count,
            windowCharacterCount: documentText.count,
            strategy: strategy
        )
    }

    let beforeContextText = String(documentText[..<range.lowerBound])
    let selectionText = String(documentText[range])
    let afterContextText = String(documentText[range.upperBound...])

    return WritingGatewayEditWindow(
        beforeContextText: beforeContextText,
        selectionText: selectionText,
        afterContextText: afterContextText,
        totalCharacterCount: documentText.count,
        windowCharacterCount: documentText.count,
        strategy: strategy
    )
}
