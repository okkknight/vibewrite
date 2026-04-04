import Foundation

@MainActor
final class WritingStreamingPreviewRenderer {
    private let configuration: WritingStreamingConfiguration
    private let applyRenderedText: (String) -> Void
    private var targetText: String = ""
    private var renderedText: String = ""
    private var playbackTask: Task<Void, Never>?
    private var didShowInitialBurst = false
    private var revealStartCharacterCount = 0
    private var isStreamCompleted = false
    private var didSignalCompletion = false
    private var completionContinuation: CheckedContinuation<Void, Never>?

    init(
        configuration: WritingStreamingConfiguration,
        applyRenderedText: @escaping (String) -> Void
    ) {
        self.configuration = configuration
        self.applyRenderedText = applyRenderedText
    }

    deinit {
        playbackTask?.cancel()
    }

    func updateTargetText(_ newTargetText: String, revealFromCharacterCount: Int = 0) {
        guard newTargetText != targetText else {
            return
        }

        targetText = newTargetText
        revealStartCharacterCount = max(0, min(revealFromCharacterCount, targetText.count))

        if didShowInitialBurst == false {
            revealInitialBurst()
            didShowInitialBurst = true
        }

        startPlaybackIfNeeded()
    }

    func markStreamCompleted() {
        isStreamCompleted = true
        startPlaybackIfNeeded()
        resolveCompletionIfNeeded()
    }

    func waitForCompletion() async {
        guard didSignalCompletion == false else {
            return
        }

        await withCheckedContinuation { continuation in
            completionContinuation = continuation
            resolveCompletionIfNeeded()
        }
    }

    func cancelPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
    }

    private func startPlaybackIfNeeded() {
        guard playbackTask == nil else {
            return
        }

        playbackTask = Task { [weak self] in
            await self?.playbackLoop()
        }
    }

    private func playbackLoop() async {
        defer {
            playbackTask = nil
        }

        while !Task.isCancelled {
            guard renderedText.count < targetText.count else {
                resolveCompletionIfNeeded()
                break
            }

            let remainingCharacters = targetText.count - renderedText.count
            let step = min(remainingCharacters, configuration.charactersPerTickBudget)
            guard step > 0 else {
                break
            }

            let nextRenderedText = prefix(of: targetText, characterCount: renderedText.count + step)
            render(nextRenderedText)

            if renderedText.count >= targetText.count {
                resolveCompletionIfNeeded()
                break
            }

            try? await Task.sleep(nanoseconds: configuration.frameIntervalNanoseconds)
        }

        resolveCompletionIfNeeded()
    }

    private func revealInitialBurst() {
        let initialCount = min(
            revealStartCharacterCount + configuration.initialBurstCharacters,
            targetText.count
        )
        guard initialCount > 0 else {
            return
        }

        render(prefix(of: targetText, characterCount: initialCount))
    }

    private func render(_ newText: String) {
        guard newText != renderedText else {
            return
        }

        renderedText = newText
        applyRenderedText(newText)
        resolveCompletionIfNeeded()
    }

    private func resolveCompletionIfNeeded() {
        guard isStreamCompleted, renderedText.count >= targetText.count else {
            return
        }

        guard didSignalCompletion == false else {
            return
        }

        didSignalCompletion = true
        let continuation = completionContinuation
        completionContinuation = nil
        continuation?.resume()
    }

    private func prefix(of text: String, characterCount: Int) -> String {
        guard characterCount > 0 else {
            return ""
        }

        if characterCount >= text.count {
            return text
        }

        let endIndex = text.index(text.startIndex, offsetBy: characterCount)
        return String(text[..<endIndex])
    }
}
