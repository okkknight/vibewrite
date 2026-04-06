import Foundation

struct WritingAIConfiguration {
    enum Mode: String {
        case real
        case stub
    }

    enum MetadataRoute: String, Codable, Hashable {
        case current
        case text01JsonSchema = "text01_json_schema"
    }

    let mode: Mode
    let provider: String
    let baseURL: URL
    let textBaseURL: URL
    let apiKey: String?
    let model: String
    let metadataRoute: MetadataRoute

    static func current(
        bundle: Bundle = .main,
        ignoreEnvironmentOverrides: Bool = false
    ) -> WritingAIConfiguration {
        let launchArguments = ProcessInfo.processInfo.arguments
        return configuration(
            from: bundle.infoDictionary ?? [:],
            environment: ignoreEnvironmentOverrides ? [:] : ProcessInfo.processInfo.environment,
            launchArguments: launchArguments
        )
    }

    static func configuration(
        from info: [String: Any],
        environment: [String: String] = [:],
        launchArguments: [String] = []
    ) -> WritingAIConfiguration {
        let modeValue = resolvedString(
            for: "VIBEWRITE_AI_DEFAULT_MODE",
            in: info,
            environment: environment,
            fallbackKeys: ["VIBEWRITE_AI_MODE"]
        ) ?? resolvedLaunchArgument(
            prefixes: ["--vibe-ai-mode", "--ai-mode"],
            arguments: launchArguments
        ) ?? "real"
        let provider = resolvedString(
            for: "VIBEWRITE_AI_PROVIDER",
            in: info,
            environment: environment
        ) ?? "minimax"

        let baseURLValue = resolvedString(
            for: "MINIMAX_BASE_URL",
            in: info,
            environment: environment
        )
            ?? "https://api.minimaxi.com/anthropic"
        let textBaseURLValue = resolvedString(
            for: "MINIMAX_TEXT_BASE_URL",
            in: info,
            environment: environment
        ) ?? "https://api.minimaxi.com"
        let model = resolvedString(
            for: "MINIMAX_MODEL",
            in: info,
            environment: environment
        )
            ?? "MiniMax-M2.5-highspeed"
        let metadataRoute = resolvedMetadataRoute(
            for: "MINIMAX_METADATA_ROUTE",
            in: info,
            environment: environment
        )
        let apiKey = resolvedString(
            for: "MINIMAX_API_KEY",
            in: info,
            environment: environment
        )

        return WritingAIConfiguration(
            mode: Mode(rawValue: modeValue.lowercased()) ?? .real,
            provider: provider,
            baseURL: URL(string: baseURLValue) ?? URL(string: "https://api.minimaxi.com/anthropic")!,
            textBaseURL: URL(string: textBaseURLValue) ?? URL(string: "https://api.minimaxi.com")!,
            apiKey: apiKey,
            model: model,
            metadataRoute: metadataRoute
        )
    }

    var shouldUseRealClient: Bool {
        mode == .real && !(apiKey?.isEmpty ?? true)
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
        in info: [String: Any],
        environment: [String: String],
        fallbackKeys: [String] = []
    ) -> String? {
        for lookupKey in [key] + fallbackKeys {
            if let rawValue = environment[lookupKey] {
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        for lookupKey in [key] + fallbackKeys {
            guard let rawValue = info[lookupKey] as? String else {
                continue
            }

            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            guard !trimmed.hasPrefix("$("), !trimmed.hasPrefix("<#") else {
                continue
            }

            return trimmed
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
        in info: [String: Any],
        environment: [String: String]
    ) -> MetadataRoute {
        let rawValue = resolvedString(for: key, in: info, environment: environment)?.lowercased()
        switch rawValue {
        case "text01_json_schema", "text01-json-schema", "text01", "json_schema":
            return .text01JsonSchema
        default:
            return .current
        }
    }
}

enum WritingAIClientFactory {
    static func makeDefaultClient(configuration: WritingAIConfiguration = .current()) -> any WritingAIClient {
        let hasAPIKey = !(configuration.apiKey?.isEmpty ?? true)
        VibeWriteLog.ai.info(
            "Resolved AI configuration mode=\(configuration.mode.rawValue, privacy: .public) provider=\(configuration.provider, privacy: .public) baseURL=\(configuration.baseURL.absoluteString, privacy: .public) textBaseURL=\(configuration.textBaseURL.absoluteString, privacy: .public) model=\(configuration.model, privacy: .public) metadataRoute=\(configuration.metadataRoute.rawValue, privacy: .public) metadataModel=\(configuration.metadataModel, privacy: .public) apiKeyPresent=\(hasAPIKey, privacy: .public)"
        )

        if configuration.shouldUseRealClient {
            VibeWriteLog.ai.notice("AI client selected: RemoteWritingAIClient")
            return RemoteWritingAIClient(configuration: configuration)
        }

        VibeWriteLog.ai.notice("AI client selected: StubWritingAIClient")
        return StubWritingAIClient()
    }
}
