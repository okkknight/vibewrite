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

actor AdminSystemPromptStore: VibeWriteAdminSystemPromptStore {
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

    static func validateJSON(_ value: String, field: String) throws {
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

extension AdminSystemPromptStore {
    func systemPromptSnapshotResponse() async throws -> AdminSystemPromptResponse {
        snapshotResponse()
    }

    func systemPromptCurrentSnapshot() async throws -> Snapshot {
        currentSnapshot()
    }

    func updateSystemPrompt(
        templateBody: String?,
        actionRulesJson: String?,
        modelContextRulesJson: String?
    ) async throws {
        try update(
            templateBody: templateBody,
            actionRulesJson: actionRulesJson,
            modelContextRulesJson: modelContextRulesJson
        )
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

    private static let templateBody = ""

    private static let actionRules = ActionRules(
        prose: .init(
            startDraft: [
                "You are VibeWrite, a calm macOS writing collaborator.",
                "Output only prose text for the requested action.",
                "Do not output metadata, JSON, markdown fences, or commentary.",
                "Write an opening that feels immediately alive, specific, and worth continuing.",
                "Let the prose carry its own rhythm, rather than following a template.",
                "Write only the opening prose for the first draft.",
                "- Keep the writing voice calm, precise, and native to a macOS writing app.",
                "- Preserve the current article's structure unless the action explicitly changes it.",
                "- When the action is \"startDraft\", focus on the first usable opening rather than a full outline."
            ],
            continueWriting: [
                "You are VibeWrite, a calm macOS writing collaborator.",
                "Output only prose text for the requested action.",
                "Do not output metadata, JSON, markdown fences, or commentary.",
                "Continue the current prose with fresh momentum.",
                "Push the scene, thought, or argument forward in a way that feels earned, not formulaic.",
                "Let the continuation find its own shape instead of forcing a fixed paragraph pattern.",
                "- Keep the writing voice calm, precise, and native to a macOS writing app.",
                "- Preserve the current article's structure unless the action explicitly changes it.",
                "- When the action is \"continueWriting\", continue the existing正文 instead of restarting the article."
            ],
            edit: [
                "You are VibeWrite, a calm macOS writing collaborator.",
                "Output only the replacement text for the requested edit.",
                "Do not output metadata, JSON, markdown fences, or commentary.",
                "Keep the output short enough to stream quickly.",
                "- When the action is \"edit\", return only the replacement text for the selected segment.",
                "- Rewrite only the selected passage or local region whenever practical.",
                "- When the user asks for 更画面, 更克制, or 更抓人, keep the original meaning and shift the sentence texture in that direction.",
                "- Keep the writing voice calm, precise, and native to a macOS writing app.",
                "- Preserve the current article's structure unless the action explicitly changes it.",
                "- Keep the prose concise enough for streaming."
            ]
        ),
        metadata: .init(
            startDraft: [
                "- Describe the current opening state as the local summary.",
                "- Keep the global synopsis short and stable.",
                "- Suggest the next concrete step after the opening exists.",
                "- Return exactly 3 concise suggestion chips."
            ],
            continueWriting: [
                "- Describe the completed正文 as the local summary.",
                "- Keep the global synopsis short and stable.",
                "- Suggest the next concrete step after the continuation.",
                "- Return exactly 3 concise suggestion chips."
            ],
            edit: [
                "- Describe the completed change as the local summary.",
                "- Keep the global synopsis short and stable.",
                "- Suggest the next concrete step after the edit.",
                "- Return exactly 3 concise suggestion chips."
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
                "- Keep the metadata specific to the current正文 and actionable for the next step.",
                "- Match the metadata language to the language of the current正文 and user request.",
                "- For Chinese writing tasks, localSummary, globalSynopsis, nextFocus, and suggestionChips must be concise Chinese.",
                "- suggestionChips must be concise, concrete, and non-generic."
            ],
            text01JsonSchema: [
                "- Keep the metadata specific to the current正文 and actionable for the next step.",
                "- Match the metadata language to the language of the current正文 and user request.",
                "- For Chinese writing tasks, localSummary, globalSynopsis, nextFocus, and suggestionChips must be concise Chinese.",
                "- suggestionChips must be concise, concrete, and non-generic.",
                "- The response format is schema-enforced, so do not wrap the metadata in extra text."
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
