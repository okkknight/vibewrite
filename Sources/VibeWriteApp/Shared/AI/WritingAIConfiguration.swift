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

    static func current(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> WritingAIConfiguration {
        let info = bundle.infoDictionary ?? [:]
        let env = processInfo.environment

        let modeValue = env["VIBEWRITE_AI_MODE"]
            ?? info["VIBEWRITE_AI_DEFAULT_MODE"] as? String
            ?? "real"
        let provider = env["VIBEWRITE_AI_PROVIDER"]
            ?? info["VIBEWRITE_AI_PROVIDER"] as? String
            ?? "minimax"

        let baseURLValue = env["MINIMAX_BASE_URL"]
            ?? info["MINIMAX_BASE_URL"] as? String
            ?? "https://api.minimax.io/v1"
        let model = env["MINIMAX_MODEL"]
            ?? info["MINIMAX_MODEL"] as? String
            ?? "MiniMax-M2.7"
        let apiKey = env["MINIMAX_API_KEY"]
            ?? info["MINIMAX_API_KEY"] as? String

        return WritingAIConfiguration(
            mode: Mode(rawValue: modeValue.lowercased()) ?? .real,
            provider: provider,
            baseURL: URL(string: baseURLValue) ?? URL(string: "https://api.minimax.io/v1")!,
            apiKey: apiKey,
            model: model
        )
    }

    var shouldUseRealClient: Bool {
        mode == .real && !(apiKey?.isEmpty ?? true)
    }
}

enum WritingAIClientFactory {
    static func makeDefaultClient(configuration: WritingAIConfiguration = .current()) -> any WritingAIClient {
        if configuration.shouldUseRealClient {
            return RemoteWritingAIClient(configuration: configuration)
        }

        return StubWritingAIClient()
    }
}
