import Foundation
import Vapor

struct AdminSystemPromptUpdateRequest: Content {
    let templateBody: String?
    let actionRulesJson: String?
    let modelContextRulesJson: String?
}

struct AdminSystemPromptResponse: Content {
    let templateBody: String
    let actionRulesJson: String
    let modelContextRulesJson: String
    let updatedAt: String
}

actor AdminSystemPromptStore {
    struct Snapshot: Sendable, Equatable {
        let templateBody: String
        let actionRulesJson: String
        let modelContextRulesJson: String
        let updatedAt: Date
    }

    private let clock: any VibeWriteClock
    private var snapshot: Snapshot

    init(snapshot: Snapshot, clock: any VibeWriteClock = SystemVibeWriteClock()) {
        self.clock = clock
        self.snapshot = snapshot
    }

    func snapshotResponse() -> AdminSystemPromptResponse {
        AdminSystemPromptResponse(
            templateBody: snapshot.templateBody,
            actionRulesJson: snapshot.actionRulesJson,
            modelContextRulesJson: snapshot.modelContextRulesJson,
            updatedAt: AdminDateCodec.string(from: snapshot.updatedAt)
        )
    }

    func currentSnapshot() -> Snapshot {
        snapshot
    }

    func update(
        templateBody: String? = nil,
        actionRulesJson: String? = nil,
        modelContextRulesJson: String? = nil
    ) throws {
        if let actionRulesJson {
            try Self.validateJSON(actionRulesJson, field: "actionRulesJson")
        }

        if let modelContextRulesJson {
            try Self.validateJSON(modelContextRulesJson, field: "modelContextRulesJson")
        }

        guard templateBody != nil || actionRulesJson != nil || modelContextRulesJson != nil else {
            return
        }

        snapshot = Snapshot(
            templateBody: templateBody ?? snapshot.templateBody,
            actionRulesJson: actionRulesJson ?? snapshot.actionRulesJson,
            modelContextRulesJson: modelContextRulesJson ?? snapshot.modelContextRulesJson,
            updatedAt: clock.now()
        )
    }

    private static func validateJSON(_ value: String, field: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw Abort(.badRequest, reason: "\(field) must be valid JSON text.")
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw Abort(.badRequest, reason: "\(field) must be valid JSON text.")
        }
    }
}

enum AdminSystemPromptSeed {
    private struct ActionRules: Codable {
        struct ProseRules: Codable {
            let startDraft: [String]
            let continueWriting: [String]
            let edit: [String]
        }

        struct MetadataRules: Codable {
            let startDraft: [String]
            let continueWriting: [String]
            let edit: [String]
        }

        let prose: ProseRules
        let metadata: MetadataRules
    }

    private struct ModelContextRules: Codable {
        struct MetadataRouteRules: Codable {
            let current: [String]
            let text01JsonSchema: [String]
        }

        let providerModel: [String]
        let metadataRoute: MetadataRouteRules
    }

    static func makeSnapshot(clock: any VibeWriteClock = SystemVibeWriteClock()) -> AdminSystemPromptStore.Snapshot {
        AdminSystemPromptStore.Snapshot(
            templateBody: templateBody,
            actionRulesJson: jsonString(from: actionRules),
            modelContextRulesJson: jsonString(from: modelContextRules),
            updatedAt: clock.now()
        )
    }

    private static let templateBody = """
    You are VibeWrite, a calm macOS writing collaborator.
    Keep the writing voice calm, precise, and native to a macOS writing app.
    Preserve the current article's structure unless the action explicitly changes it.
    """

    private static let actionRules = ActionRules(
        prose: .init(
            startDraft: [
                "Output only prose text for the requested action.",
                "Do not output metadata, JSON, markdown fences, or commentary.",
                "Keep the output short enough to stream quickly.",
                "Write only the opening prose for the first draft.",
                "Keep the opening brief and concrete so it can stand on its own.",
                "When the action is startDraft, focus on the first usable opening rather than a full outline."
            ],
            continueWriting: [
                "Output only prose text for the requested action.",
                "Do not output metadata, JSON, markdown fences, or commentary.",
                "Keep the output short enough to stream quickly.",
                "Continue the current正文 with the next short paragraph or scene.",
                "Advance the passage only a little; do not turn this into a full ending or a fully closed paragraph.",
                "When the action is continueWriting, continue the existing正文 instead of restarting the article."
            ],
            edit: [
                "Output the writing text first, then append exactly one metadata block for the app.",
                "Do not output commentary outside the writing text and metadata block.",
                "A response is incomplete until the metadata block is present.",
                "When the action is edit, return only the replacement text for the selected segment.",
                "Do not stop after writing text alone.",
                "When the action is edit, rewrite only the selected passage or local region whenever practical."
            ]
        ),
        metadata: .init(
            startDraft: [
                "Return suggestionChips as the primary output and keep them concrete.",
                "Describe the current opening state as the local summary.",
                "Keep the global synopsis short and stable; it should preserve broader story state without repeating the local summary.",
                "Suggest the next concrete step after the opening exists.",
                "Return exactly 3 concise suggestion chips."
            ],
            continueWriting: [
                "Return suggestionChips as the primary output and keep them concrete.",
                "Describe the completed正文 as the local summary.",
                "Keep the global synopsis short and stable; it should preserve broader story state without repeating the local summary.",
                "Suggest the next concrete step after the continuation.",
                "Return exactly 3 concise suggestion chips."
            ],
            edit: [
                "Return suggestionChips as the primary output and keep them concrete.",
                "Describe the completed change as the local summary.",
                "Keep the global synopsis short and stable; it should preserve broader story state without repeating the local summary.",
                "Suggest the next concrete step after the edit.",
                "Return exactly 3 concise suggestion chips."
            ]
        )
    )

    private static let modelContextRules = ModelContextRules(
        providerModel: [
            "Provider: {provider}",
            "Model: {model}"
        ],
        metadataRoute: .init(
            current: [
                "The only valid response is a single emit_metadata tool call.",
                "Do not output plain text, prose, markdown fences, JSON, reasoning, or commentary.",
                "Do not answer in any other format.",
                "If you are about to produce ordinary assistant text, stop and emit the tool call instead.",
                "Treat suggestionChips as the most important field and do not let globalSynopsis crowd it out.",
                "Keep localSummary brief, keep globalSynopsis stable and short, and let suggestionChips stay concrete."
            ],
            text01JsonSchema: [
                "Return only the metadata for the completed prose.",
                "Do not output prose, markdown fences, tool calls, or commentary.",
                "Do not answer in plain text.",
                "The response format is schema-enforced, so do not wrap the metadata in extra text.",
                "Treat suggestionChips as the most important field and do not let globalSynopsis crowd it out.",
                "Keep localSummary brief, keep globalSynopsis stable and short, and let suggestionChips stay concrete."
            ]
        )
    )

    private static func jsonString<T: Encodable>(from value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try! encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
