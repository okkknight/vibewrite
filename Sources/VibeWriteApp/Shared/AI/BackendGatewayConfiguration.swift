import Foundation

struct BackendGatewayConfiguration {
    enum Mode: String {
        case real
        case stub
    }

    let mode: Mode
    let baseURL: URL
    let appVersion: String
    let platform: String
    let deviceName: String

    static func current(
        bundle: Bundle = .main,
        ignoreEnvironmentOverrides: Bool = false
    ) -> BackendGatewayConfiguration {
        configuration(
            from: bundle.infoDictionary ?? [:],
            environment: ignoreEnvironmentOverrides ? [:] : ProcessInfo.processInfo.environment,
            launchArguments: ProcessInfo.processInfo.arguments
        )
    }

    static func configuration(
        from info: [String: Any],
        environment: [String: String] = [:],
        launchArguments: [String] = []
    ) -> BackendGatewayConfiguration {
        let modeValue = resolvedString(
            for: "VIBEWRITE_BACKEND_DEFAULT_MODE",
            in: info,
            environment: environment,
            fallbackKeys: [
                "VIBEWRITE_BACKEND_MODE",
                "VIBEWRITE_AI_DEFAULT_MODE",
                "VIBEWRITE_AI_MODE"
            ]
        ) ?? resolvedLaunchArgument(
            prefixes: ["--vibe-backend-mode", "--backend-mode", "--vibe-ai-mode", "--ai-mode"],
            arguments: launchArguments
        ) ?? "real"

        let baseURLValue = resolvedString(
            for: "VIBEWRITE_BACKEND_BASE_URL",
            in: info,
            environment: environment
        ) ?? "http://127.0.0.1:8080"

        let shortVersion = resolvedString(
            for: "CFBundleShortVersionString",
            in: info,
            environment: environment
        )
        let buildVersion = resolvedString(
            for: "CFBundleVersion",
            in: info,
            environment: environment
        )
        let appVersionParts = [shortVersion, buildVersion].compactMap { $0 }
        let appVersion = appVersionParts.isEmpty ? "unknown" : appVersionParts.joined(separator: " ")

        let deviceName = resolvedDeviceName()

        return BackendGatewayConfiguration(
            mode: Mode(rawValue: modeValue.lowercased()) ?? .real,
            baseURL: URL(string: baseURLValue) ?? URL(string: "http://127.0.0.1:8080")!,
            appVersion: appVersion,
            platform: "macOS",
            deviceName: deviceName
        )
    }

    var shouldUseRealClient: Bool {
        mode == .real
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

    private static func resolvedDeviceName() -> String {
        let localizedName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let localizedName, !localizedName.isEmpty {
            return localizedName
        }

        let hostName = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return hostName.isEmpty ? "unknown" : hostName
    }
}
