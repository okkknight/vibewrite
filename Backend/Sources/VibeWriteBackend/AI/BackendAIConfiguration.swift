import Foundation

struct BackendAIConfiguration: Sendable, Equatable {
    enum Mode: String, Sendable, Equatable {
        case real
        case stub
    }

    enum MetadataRoute: String, Codable, Hashable, Sendable {
        case current
        case text01JsonSchema = "text01_json_schema"
    }

    let mode: Mode
    let provider: String
    let baseURL: URL
    let textBaseURL: URL
    let model: String
    let metadataRoute: MetadataRoute

    init(
        mode: Mode,
        provider: String,
        baseURL: URL,
        textBaseURL: URL,
        model: String,
        metadataRoute: MetadataRoute
    ) {
        self.mode = mode
        self.provider = provider
        self.baseURL = baseURL
        self.textBaseURL = textBaseURL
        self.model = model
        self.metadataRoute = metadataRoute
    }

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        isTesting: Bool = false
    ) -> BackendAIConfiguration {
        let modeValue = resolvedString(
            for: "VIBEWRITE_BACKEND_AI_MODE",
            in: environment,
            fallbackKeys: ["VIBEWRITE_AI_DEFAULT_MODE", "VIBEWRITE_AI_MODE"]
        ) ?? resolvedLaunchArgument(
            prefixes: ["--backend-ai-mode", "--vibe-ai-mode", "--ai-mode"],
            arguments: launchArguments
        ) ?? (isTesting ? "stub" : "real")

        let provider = resolvedString(
            for: "VIBEWRITE_AI_PROVIDER",
            in: environment
        ) ?? "minimax"

        let baseURLValue = resolvedString(
            for: "MINIMAX_BASE_URL",
            in: environment
        ) ?? "https://api.minimaxi.com/anthropic"

        let textBaseURLValue = resolvedString(
            for: "MINIMAX_TEXT_BASE_URL",
            in: environment
        ) ?? "https://api.minimaxi.com"

        let model = resolvedString(
            for: "MINIMAX_MODEL",
            in: environment
        ) ?? "MiniMax-M2.5-highspeed"

        let metadataRoute = resolvedMetadataRoute(
            for: "MINIMAX_METADATA_ROUTE",
            in: environment
        )

        return BackendAIConfiguration(
            mode: Mode(rawValue: modeValue.lowercased()) ?? .real,
            provider: provider,
            baseURL: URL(string: baseURLValue) ?? URL(string: "https://api.minimaxi.com/anthropic")!,
            textBaseURL: URL(string: textBaseURLValue) ?? URL(string: "https://api.minimaxi.com")!,
            model: model,
            metadataRoute: metadataRoute
        )
    }

    var metadataModel: String {
        switch metadataRoute {
        case .current:
            return model
        case .text01JsonSchema:
            return "MiniMax-Text-01"
        }
    }

    var metadataRequestBaseURL: URL {
        switch metadataRoute {
        case .current:
            return baseURL
        case .text01JsonSchema:
            return textBaseURL
        }
    }

    private static func resolvedString(
        for key: String,
        in environment: [String: String],
        fallbackKeys: [String] = []
    ) -> String? {
        for lookupKey in [key] + fallbackKeys {
            guard let rawValue = environment[lookupKey] else {
                continue
            }

            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private static func resolvedLaunchArgument(prefixes: [String], arguments: [String]) -> String? {
        for argument in arguments {
            for prefix in prefixes {
                if argument == prefix {
                    return "stub"
                }

                let equalsPrefix = "\(prefix)="
                if argument.hasPrefix(equalsPrefix) {
                    let value = String(argument.dropFirst(equalsPrefix.count))
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }

        return nil
    }

    private static func resolvedMetadataRoute(
        for key: String,
        in environment: [String: String]
    ) -> MetadataRoute {
        let rawValue = resolvedString(for: key, in: environment)?.lowercased()
        switch rawValue {
        case "text01_json_schema", "text01-json-schema", "text01", "json_schema":
            return .text01JsonSchema
        case "current":
            return .current
        default:
            return .current
        }
    }
}

