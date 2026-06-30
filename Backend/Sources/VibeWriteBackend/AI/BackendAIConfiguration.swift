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
        let resolvedProvider = resolvedString(
            for: "VIBEWRITE_AI_PROVIDER",
            in: environment
        ) ?? (isTesting ? "minimax" : "codex")

        let modeValue = resolvedString(
            for: "VIBEWRITE_BACKEND_AI_MODE",
            in: environment,
            fallbackKeys: ["VIBEWRITE_AI_DEFAULT_MODE", "VIBEWRITE_AI_MODE"]
        ) ?? resolvedLaunchArgument(
            prefixes: ["--backend-ai-mode", "--vibe-ai-mode", "--ai-mode"],
            arguments: launchArguments
        ) ?? (isTesting ? "stub" : "real")

        let provider = resolvedProvider

        let baseURLValue = resolvedString(
            for: "MINIMAX_BASE_URL",
            in: environment
        ) ?? "https://api.minimaxi.com/anthropic"

        let textBaseURLValue = resolvedString(
            for: "MINIMAX_TEXT_BASE_URL",
            in: environment
        ) ?? "https://api.minimaxi.com"

        let model = resolvedModel(
            for: provider,
            in: environment,
            isTesting: isTesting
        )

        let metadataRoute = resolvedMetadataRoute(
            for: "MINIMAX_METADATA_ROUTE",
            in: environment,
            provider: provider
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
        if isCodexProvider {
            return model
        }

        switch metadataRoute {
        case .current:
            return model
        case .text01JsonSchema:
            return "MiniMax-Text-01"
        }
    }

    var metadataRequestBaseURL: URL {
        if isCodexProvider {
            return baseURL
        }

        switch metadataRoute {
        case .current:
            return baseURL
        case .text01JsonSchema:
            return textBaseURL
        }
    }

    private var isCodexProvider: Bool {
        provider.lowercased() == "codex"
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
        in environment: [String: String],
        provider: String
    ) -> MetadataRoute {
        if provider.lowercased() == "codex" {
            return .current
        }

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

    private static func resolvedModel(
        for provider: String,
        in environment: [String: String],
        isTesting: Bool
    ) -> String {
        switch provider.lowercased() {
        case "codex":
            return resolvedCodexModel(in: environment) ?? "gpt-5.4-mini"
        default:
            return resolvedString(
                for: "MINIMAX_MODEL",
                in: environment
            ) ?? (isTesting ? "MiniMax-M2.5-highspeed" : "MiniMax-M2.5-highspeed")
        }
    }

    private static func resolvedCodexModel(in environment: [String: String]) -> String? {
        if let explicitModel = resolvedString(
            for: "VIBEWRITE_CODEX_MODEL",
            in: environment,
            fallbackKeys: ["CODEX_MODEL"]
        ) {
            return explicitModel
        }

        let configURL = resolvedCodexConfigURL(in: environment)
        guard let configContents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }

        for line in configContents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("model") else {
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let rawValue = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if rawValue.hasPrefix("\""), rawValue.hasSuffix("\""), rawValue.count >= 2 {
                return String(rawValue.dropFirst().dropLast())
            }

            if rawValue.hasPrefix("'"), rawValue.hasSuffix("'"), rawValue.count >= 2 {
                return String(rawValue.dropFirst().dropLast())
            }

            if !rawValue.isEmpty {
                return rawValue
            }
        }

        return nil
    }

    private static func resolvedCodexConfigURL(in environment: [String: String]) -> URL {
        if let codexHome = resolvedString(
            for: "CODEX_HOME",
            in: environment
        ) {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("config.toml")
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("config.toml")
    }
}
