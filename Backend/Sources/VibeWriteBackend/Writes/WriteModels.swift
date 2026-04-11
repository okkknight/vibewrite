import Foundation
import Vapor
import VibeWriteShared

struct WriteRequestEnvelope: Content {
    let installationId: String
    let deviceToken: String
    let requestId: String
    let action: WritingAIAction
    let kind: WritingAIRequestKind
    let project: WritingProjectSnapshot
    let userMessage: String?
    let selectionText: String?
    let selectionRange: WritingTextSelectionRange?
}
