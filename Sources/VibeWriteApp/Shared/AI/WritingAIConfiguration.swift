import Foundation

struct WritingAIConfiguration {
    enum Mode: String {
        case real
        case stub
    }

    let mode: Mode
    let provider: String
    let baseURL: URL
    let apiKey: String?
    let model: String

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
        let model = resolvedString(
            for: "MINIMAX_MODEL",
            in: info,
            environment: environment
        )
            ?? "MiniMax-M2.5-highspeed"
        let apiKey = resolvedString(
            for: "MINIMAX_API_KEY",
            in: info,
            environment: environment
        )

        return WritingAIConfiguration(
            mode: Mode(rawValue: modeValue.lowercased()) ?? .real,
            provider: provider,
            baseURL: URL(string: baseURLValue) ?? URL(string: "https://api.minimaxi.com/anthropic")!,
            apiKey: apiKey,
            model: model
        )
    }

    var shouldUseRealClient: Bool {
        mode == .real && !(apiKey?.isEmpty ?? true)
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
}

enum WritingAIClientFactory {
    static func makeDefaultClient(configuration: WritingAIConfiguration = .current()) -> any WritingAIClient {
        let hasAPIKey = !(configuration.apiKey?.isEmpty ?? true)
        VibeWriteLog.ai.info(
            "Resolved AI configuration mode=\(configuration.mode.rawValue, privacy: .public) provider=\(configuration.provider, privacy: .public) baseURL=\(configuration.baseURL.absoluteString, privacy: .public) model=\(configuration.model, privacy: .public) apiKeyPresent=\(hasAPIKey, privacy: .public)"
        )

        if configuration.shouldUseRealClient {
            VibeWriteLog.ai.notice("AI client selected: RemoteWritingAIClient")
            return RemoteWritingAIClient(configuration: configuration)
        }

        VibeWriteLog.ai.notice("AI client selected: StubWritingAIClient")
        return StubWritingAIClient()
    }
}
