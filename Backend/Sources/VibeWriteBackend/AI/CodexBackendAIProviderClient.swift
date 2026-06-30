import Foundation
import VibeWriteShared

protocol CodexCommandRunning: Sendable {
    func run(prompt: String, model: String) async throws -> CodexCommandResult
}

struct CodexCommandResult: Sendable {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
}

struct SystemCodexCommandRunner: CodexCommandRunning {
    private let commandPath: String

    init(commandPath: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.commandPath = commandPath ?? Self.resolveCommandPath(environment: environment)
    }

    func run(prompt: String, model: String) async throws -> CodexCommandResult {
        let process = Process()
        if commandPath.contains("/") {
            process.executableURL = URL(fileURLWithPath: commandPath)
            process.arguments = Self.makeArguments(model: model)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [commandPath] + Self.makeArguments(model: model)
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutTask = Task<Data, Error> {
            try await Self.readAllData(from: stdoutPipe.fileHandleForReading)
        }
        let stderrTask = Task<Data, Error> {
            try await Self.readAllData(from: stderrPipe.fileHandleForReading)
        }

        let terminationStatus = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { completedProcess in
                continuation.resume(returning: completedProcess.terminationStatus)
            }

            do {
                try process.run()
                try stdinPipe.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
                stdinPipe.fileHandleForWriting.closeFile()
            } catch {
                stdoutTask.cancel()
                stderrTask.cancel()
                continuation.resume(throwing: error)
            }
        }

        let stdoutData = try await stdoutTask.value
        let stderrData = try await stderrTask.value

        return CodexCommandResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            terminationStatus: terminationStatus
        )
    }

    private static func resolveCommandPath(environment: [String: String]) -> String {
        if let explicitPath = firstNonEmptyValue(
            for: ["VIBEWRITE_CODEX_CLI_PATH", "CODEX_CLI_PATH"],
            in: environment
        ) {
            return explicitPath
        }

        let bundledPath = "/Applications/Codex.app/Contents/Resources/codex"
        if FileManager.default.fileExists(atPath: bundledPath) {
            return bundledPath
        }

        return "codex"
    }

    private static func firstNonEmptyValue(for keys: [String], in environment: [String: String]) -> String? {
        for key in keys {
            guard let rawValue = environment[key] else {
                continue
            }

            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private static func makeArguments(model: String) -> [String] {
        [
            "exec",
            "--json",
            "--ignore-user-config",
            "--ignore-rules",
            "--sandbox",
            "read-only",
            "--skip-git-repo-check",
            "--ephemeral",
            "--model",
            model,
            "-"
        ]
    }

    private static func readAllData(from fileHandle: FileHandle) async throws -> Data {
        var data = Data()
        for try await byte in fileHandle.bytes {
            data.append(byte)
        }
        return data
    }
}

final class CodexBackendAIProviderClient: BackendAIProviderClient, @unchecked Sendable {
    private let commandRunner: any CodexCommandRunning
    private let responseBuilder = BackendWritingResponseBuilder()

    init(commandRunner: (any CodexCommandRunning)? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.commandRunner = commandRunner ?? SystemCodexCommandRunner(environment: environment)
    }

    func generateProseText(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> String {
        let result = try await commandRunner.run(
            prompt: makePrompt(for: messages),
            model: configuration.model
        )

        try validateExitCode(result, action: request.action)

        let text = try extractFinalAgentMessage(from: result.stdout)
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw BackendAIError.providerError("Codex CLI returned an empty prose response.")
        }

        return text
    }

    func streamProseText(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let proseText = try await generateProseText(
            for: request,
            messages: messages,
            configuration: configuration,
            apiKey: apiKey
        )

        return AsyncThrowingStream { continuation in
            Task {
                let chunks = proseText
                    .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                    .map(String.init)

                for (index, chunk) in chunks.enumerated() {
                    let emittedChunk = chunk.isEmpty ? "\n" : chunk + (index < chunks.count - 1 ? "\n" : "")
                    continuation.yield(emittedChunk)
                    if index < chunks.count - 1 {
                        try? await Task.sleep(nanoseconds: 85_000_000)
                    }
                }

                continuation.finish()
            }
        }
    }

    func generateMetadata(
        for request: WritingAIRequest,
        messages: [WritingAIChatMessage],
        configuration: BackendAIConfiguration,
        apiKey: String
    ) async throws -> WritingAICompletionMetadata {
        let result = try await commandRunner.run(
            prompt: makePrompt(for: messages),
            model: configuration.model
        )

        try validateExitCode(result, action: request.action)

        let text = try extractFinalAgentMessage(from: result.stdout)
        do {
            return try WritingAICompletionMetadataDecoder.decode(from: text)
        } catch {
            return responseBuilder.fallbackMetadata(for: request)
        }
    }

    private func makePrompt(for messages: [WritingAIChatMessage]) -> String {
        var lines: [String] = [
            "You are the local Codex runtime for VibeWrite.",
            "Do not use tools, browse files, or run commands.",
            "Return only the requested output."
        ]

        for message in messages {
            lines.append("")
            lines.append("\(message.role.rawValue.uppercased()):")
            lines.append(message.content)
        }

        return lines.joined(separator: "\n")
    }

    private func extractFinalAgentMessage(from output: String) throws -> String {
        let decoder = JSONDecoder()
        var finalMessage: String?

        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
                continue
            }

            guard let event = try? decoder.decode(CodexJSONEvent.self, from: data) else {
                continue
            }

            if event.type == "item.completed",
               let item = event.item,
               item.type == "agent_message",
               let text = item.text {
                finalMessage = text
            }
        }

        guard let finalMessage else {
            throw BackendAIError.providerError("Codex CLI did not return an agent message.")
        }

        return finalMessage
    }

    private func validateExitCode(_ result: CodexCommandResult, action: WritingAIAction) throws {
        guard result.terminationStatus == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = stderr.isEmpty
                ? "Codex CLI failed for \(action.rawValue) with exit code \(result.terminationStatus)."
                : "Codex CLI failed for \(action.rawValue) with exit code \(result.terminationStatus): \(stderr)"
            throw BackendAIError.providerError(message)
        }
    }
}

private struct CodexJSONEvent: Decodable {
    let type: String
    let item: CodexJSONItem?
}

private struct CodexJSONItem: Decodable {
    let type: String
    let text: String?
}
