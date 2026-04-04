import Foundation

struct WritingStreamingConfiguration {
    let frameInterval: TimeInterval
    let charactersPerSecond: Double
    let initialBurstCharacters: Int
    let minimumCharactersPerTick: Int
    let maximumCharactersPerTick: Int

    static func current(
        bundle: Bundle = .main,
        ignoreEnvironmentOverrides: Bool = false
    ) -> WritingStreamingConfiguration {
        configuration(
            from: bundle.infoDictionary ?? [:],
            environment: ignoreEnvironmentOverrides ? [:] : ProcessInfo.processInfo.environment
        )
    }

    static func configuration(
        from info: [String: Any],
        environment: [String: String] = [:]
    ) -> WritingStreamingConfiguration {
        let frameIntervalMs = resolvedDouble(
            for: "VIBEWRITE_STREAMING_FRAME_INTERVAL_MS",
            in: info,
            environment: environment
        ) ?? 40
        let charactersPerSecond = resolvedDouble(
            for: "VIBEWRITE_STREAMING_CHARACTERS_PER_SECOND",
            in: info,
            environment: environment
        ) ?? 25
        let initialBurstCharacters = resolvedInt(
            for: "VIBEWRITE_STREAMING_INITIAL_BURST_CHARACTERS",
            in: info,
            environment: environment
        ) ?? 1
        let minimumCharactersPerTick = resolvedInt(
            for: "VIBEWRITE_STREAMING_MINIMUM_CHARACTERS_PER_TICK",
            in: info,
            environment: environment
        ) ?? 1
        let maximumCharactersPerTick = resolvedInt(
            for: "VIBEWRITE_STREAMING_MAXIMUM_CHARACTERS_PER_TICK",
            in: info,
            environment: environment
        ) ?? 1

        let sanitizedMinimumCharactersPerTick = max(1, minimumCharactersPerTick)
        let sanitizedMaximumCharactersPerTick = max(sanitizedMinimumCharactersPerTick, maximumCharactersPerTick)

        return WritingStreamingConfiguration(
            frameInterval: max(0.008, frameIntervalMs / 1000),
            charactersPerSecond: max(1, charactersPerSecond),
            initialBurstCharacters: max(1, initialBurstCharacters),
            minimumCharactersPerTick: sanitizedMinimumCharactersPerTick,
            maximumCharactersPerTick: sanitizedMaximumCharactersPerTick
        )
    }

    var frameIntervalNanoseconds: UInt64 {
        UInt64((frameInterval * 1_000_000_000).rounded())
    }

    var charactersPerTickBudget: Int {
        let computed = Int((charactersPerSecond * frameInterval).rounded(.down))
        return min(
            maximumCharactersPerTick,
            max(minimumCharactersPerTick, max(1, computed))
        )
    }

    private static func resolvedDouble(
        for key: String,
        in info: [String: Any],
        environment: [String: String]
    ) -> Double? {
        guard let rawValue = resolvedString(for: key, in: info, environment: environment) else {
            return nil
        }

        return Double(rawValue)
    }

    private static func resolvedInt(
        for key: String,
        in info: [String: Any],
        environment: [String: String]
    ) -> Int? {
        guard let rawValue = resolvedString(for: key, in: info, environment: environment) else {
            return nil
        }

        return Int(rawValue)
    }

    private static func resolvedString(
        for key: String,
        in info: [String: Any],
        environment: [String: String]
    ) -> String? {
        if let rawValue = environment[key] {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        guard let rawValue = info[key] as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard !trimmed.hasPrefix("$("), !trimmed.hasPrefix("<#") else {
            return nil
        }

        return trimmed
    }
}
