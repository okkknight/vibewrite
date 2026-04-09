import Foundation
import AppKit
import UniformTypeIdentifiers
import SwiftUI

@MainActor
final class VibeWriteAppFlow: ObservableObject {
    @Published private(set) var projects: [WritingProject]
    @Published private(set) var activeProjectID: UUID?
    @Published private(set) var isAIRequestInFlight = false
    @Published private(set) var isBodyThinkingInFlight = false
    @Published private(set) var isProseRequestInFlight = false
    @Published private(set) var isMetadataRequestInFlight = false
    @Published private(set) var activeEditLock: WritingEditLock?
    @Published private(set) var aiErrorMessage: String?
    @Published private(set) var currentDocumentURL: URL?
    @Published private(set) var recentDocumentEntries: [RecentDocumentEntry]
    @Published private(set) var activeDocumentText: String

    private let recentDocumentStore: RecentDocumentStore
    private let documentMetadataStore: VibeWriteDocumentMetadataStore
    private let documentIdentityStore: VibeWriteDocumentIdentityStore
    private let aiClient: any WritingAIClient
    private let streamingConfiguration: WritingStreamingConfiguration
    private let emptyProjectShell: WritingProject
    private var savedDocumentContents: String?
    private var documentHydrationProtectedProjectID: UUID?
    private var activeRequestToken: UUID?

    init(
        storageURL: URL? = nil,
        fileManager: FileManager = .default,
        aiClient: (any WritingAIClient)? = nil,
        aiConfiguration: WritingAIConfiguration = .current(),
        streamingConfiguration: WritingStreamingConfiguration = .current(),
        forceBlankStartup: Bool = false
    ) {
        let environmentStorageURL = forceBlankStartup ? nil : ProcessInfo.processInfo.environment["VIBEWRITE_STORAGE_URL"].flatMap {
            URL(fileURLWithPath: $0)
        }
        let shouldResetStorage = ProcessInfo.processInfo.environment["VIBEWRITE_UI_TEST_RESET_STORAGE"] == "1"
        let resolvedRecentStorageURL = storageURL ?? environmentStorageURL ?? RecentDocumentStore.defaultStorageURL(fileManager: fileManager)
        let resolvedMetadataStorageURL = resolvedRecentStorageURL
            .deletingLastPathComponent()
            .appendingPathComponent("document-collaboration-store.json")
        let resolvedStore = RecentDocumentStore(
            storageURL: resolvedRecentStorageURL,
            fileManager: fileManager
        )
        self.recentDocumentStore = resolvedStore
        self.documentMetadataStore = VibeWriteDocumentMetadataStore(
            storageURL: resolvedMetadataStorageURL,
            fileManager: fileManager
        )
        self.documentIdentityStore = VibeWriteDocumentIdentityStore()
        self.aiClient = aiClient ?? WritingAIClientFactory.makeDefaultClient(configuration: aiConfiguration)
        self.streamingConfiguration = streamingConfiguration
        self.emptyProjectShell = WritingProject.entryShell(mode: .collaboration)
        self.recentDocumentEntries = resolvedStore.load()
        self.savedDocumentContents = VibeWriteMarkdownDocument(project: self.emptyProjectShell).renderedText()
        self.activeDocumentText = self.emptyProjectShell.documentText

        if forceBlankStartup || shouldResetStorage {
            self.projects = []
            self.activeProjectID = nil
            resolvedStore.clear()
            documentMetadataStore.clear()
            self.recentDocumentEntries = []
            self.savedDocumentContents = VibeWriteMarkdownDocument(project: self.emptyProjectShell).renderedText()
            self.activeDocumentText = self.emptyProjectShell.documentText
            self.currentDocumentURL = nil
        } else {
            self.projects = []
            self.activeProjectID = nil
            self.currentDocumentURL = nil
        }

    }

    var recentProjects: [WritingProject] {
        projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    var currentDocumentFileText: String {
        VibeWriteMarkdownDocument(project: activeEditingProject).renderedText()
    }

    var isCurrentDocumentDirty: Bool {
        if currentDocumentURL != nil {
            return currentDocumentFileText != savedDocumentContents
        }

        guard !projects.isEmpty else {
            return false
        }

        guard let savedDocumentContents else {
            return true
        }

        return currentDocumentFileText != savedDocumentContents
    }

    var activeEditingProject: WritingProject {
        var project = activeProject
        project.documentText = activeDocumentText
        return project
    }

    var activeProject: WritingProject {
        get {
            if let activeProjectID, let project = project(for: activeProjectID) {
                return project
            }

            if let firstProject = projects.first {
                return firstProject
            }

            return emptyProjectShell
        }
        set {
            setActiveProject(newValue)
        }
    }

    var activeDocumentTextBinding: Binding<String> {
        Binding(
            get: { [weak self] in
                self?.activeDocumentText ?? ""
            },
            set: { [weak self] newText in
                guard let self else { return }
                let oldCount = activeDocumentText.utf16.count
                let newCount = newText.utf16.count
                let activeProjectIDName = activeProjectID?.uuidString ?? "nil"
                let currentURLName = currentDocumentURL?.lastPathComponent ?? "nil"
                VibeWriteLog.ai.info(
                    "flow activeDocumentText binding writeback oldCount=\(oldCount, privacy: .public) newCount=\(newCount, privacy: .public) activeProjectID=\(activeProjectIDName, privacy: .public) currentURL=\(currentURLName, privacy: .public)"
                )
                VibeWriteLog.launch.info(
                    "flow activeDocumentText binding writeback oldCount=\(oldCount, privacy: .public) newCount=\(newCount, privacy: .public) activeProjectID=\(activeProjectIDName, privacy: .public) currentURL=\(currentURLName, privacy: .public)"
                )
                VibeWriteDebugTrace.append(
                    "flow activeDocumentText binding writeback oldCount=\(oldCount) newCount=\(newCount) activeProjectID=\(activeProjectIDName) currentURL=\(currentURLName)"
                )
                self.activeDocumentText = newText
            }
        )
    }

    func openProject(_ project: WritingProject) {
        replaceActiveProject(project)
    }

    func beginDocumentHydration(for projectID: UUID) {
        documentHydrationProtectedProjectID = projectID
        VibeWriteDebugTrace.append("flow document hydration started projectID=\(projectID.uuidString)")
    }

    func endDocumentHydration(for projectID: UUID) {
        guard documentHydrationProtectedProjectID == projectID else { return }
        documentHydrationProtectedProjectID = nil
        VibeWriteDebugTrace.append("flow document hydration ended projectID=\(projectID.uuidString)")
    }

    func isDocumentHydrationProtected(for projectID: UUID) -> Bool {
        documentHydrationProtectedProjectID == projectID
    }

    func createNewProject() {
        guard confirmDiscardCurrentChangesIfNeeded() else {
            return
        }

        let project = WritingProject.entryShell(
            prompt: "",
            mode: .collaboration,
            automationKey: "project.new.blank"
        )
        currentDocumentURL = nil
        savedDocumentContents = VibeWriteMarkdownDocument(project: project).renderedText()
        activeDocumentText = project.documentText
        openProject(project)
    }

    func startQuickDraft(prompt: String, mode: WritingProjectMode) async {
        guard confirmDiscardCurrentChangesIfNeeded() else {
            return
        }

        let project = WritingProject.entryShell(
            prompt: prompt,
            mode: mode,
            automationKey: "project.quickstart.\(mode.rawValue)"
        )
        currentDocumentURL = nil
        savedDocumentContents = VibeWriteMarkdownDocument(project: project).renderedText()
        activeDocumentText = project.documentText
        openProject(project)
        guard mode == .collaboration else { return }

        do {
            try await performWritingAction(
                .startDraft,
                userMessage: prompt,
                selectionText: nil
            )
        } catch {
            return
        }
    }

    func renameActiveProject(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updatedProject = activeEditingProject
        updatedProject.title = trimmed
        activeProject = updatedProject
        if let currentDocumentURL {
            documentMetadataStore.save(project: updatedProject)
            recordRecentDocument(url: currentDocumentURL, title: updatedProject.title)
        }
    }

    func deleteActiveProject() {
        guard let currentProjectID = activeProjectID,
              let index = projects.firstIndex(where: { $0.id == currentProjectID }) else {
            return
        }

        var updatedProjects = projects
        updatedProjects.remove(at: index)
        projects = updatedProjects
        activeProjectID = nil
    }

    func resetLocalData() {
        recentDocumentStore.clear()
        documentMetadataStore.clear()
        recentDocumentEntries = []
        projects = []
        activeProjectID = nil
        currentDocumentURL = nil
        savedDocumentContents = nil
        activeDocumentText = emptyProjectShell.documentText
        activeEditLock = nil
        aiErrorMessage = nil
        isAIRequestInFlight = false
        isBodyThinkingInFlight = false
        isProseRequestInFlight = false
        isMetadataRequestInFlight = false
        activeRequestToken = nil
    }

    @discardableResult
    func undoLastRevision() -> WritingProjectRevision? {
        var project = activeEditingProject
        guard let revision = project.undoLastRevision() else {
            return nil
        }

        activeProject = project
        return revision
    }

    func performWritingAction(
        _ action: WritingAIAction,
        userMessage: String? = nil,
        selectionText: String? = nil,
        selectionRange: WritingTextSelectionRange? = nil
    ) async throws {
        guard !isAIRequestInFlight else {
            throw WritingAIClientError.requestFailed("已有请求正在进行，请稍后再试。")
        }

        let project = activeEditingProject
        let requestToken = UUID()
        let requestLock = WritingEditLock(
            action: action,
            lockedSelectionText: selectionRange.flatMap { $0.substring(in: project.documentText)?.trimmingCharacters(in: .whitespacesAndNewlines) } ?? selectionText,
            lockedDocumentText: project.documentText
        )
        activeRequestToken = requestToken
        isAIRequestInFlight = true
        isBodyThinkingInFlight = true
        isProseRequestInFlight = true
        isMetadataRequestInFlight = false
        activeEditLock = requestLock
        aiErrorMessage = nil
        defer {
            if self.activeRequestToken == requestToken {
                self.isAIRequestInFlight = false
                self.isBodyThinkingInFlight = false
                self.isProseRequestInFlight = false
                self.isMetadataRequestInFlight = false
                self.activeEditLock = nil
                self.activeRequestToken = nil
            }
        }

        let requestUserMessage = requestUserMessage(
            for: action,
            userMessage: userMessage
        )

        let normalizedSelectionText: String? = {
            guard let selectionRange,
                  let exactSelection = selectionRange.substring(in: project.documentText)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !exactSelection.isEmpty else {
                return nil
            }

            return exactSelection
        }()
        let traceID = Self.shortTraceID()

        if action == .edit {
            guard normalizedSelectionText != nil else {
                throw WritingEditPatchError.missingSelection
            }
        }

        if action == .edit {
            let request = WritingAIRequest(
                action: action,
                project: project.aiSnapshot,
                userMessage: requestUserMessage,
                selectionText: normalizedSelectionText ?? selectionText,
                selectionRange: selectionRange
            )

            do {
                let beforeSnapshot = project.aiSnapshot
                var liveProject = project
                if let requestUserMessage {
                    let alreadyHasMatchingUserMessage = action == .startDraft && project.conversation.contains { message in
                        message.role == .user && message.text.trimmingCharacters(in: .whitespacesAndNewlines) == requestUserMessage
                    }

                    if !alreadyHasMatchingUserMessage {
                        liveProject.appendUserMessage(requestUserMessage)
                    }

                    if action == .startDraft {
                        liveProject.prompt = requestUserMessage
                    }
                }
                liveProject.localSummary = streamingSummary(for: action)
                replaceActiveProject(liveProject)

                var streamedText = ""
                let previewRenderer: WritingStreamingPreviewRenderer? = nil
                var finalResponse: WritingAIResponse?
                for try await event in aiClient.streamResponse(for: request) {
                    switch event {
                    case .textDelta(let delta):
                        streamedText += delta
                        if let previewRenderer {
                            previewRenderer.updateTargetText(
                                previewDocumentText(
                                    for: action,
                                    baseDocumentText: beforeSnapshot.documentText,
                                    selectionRange: selectionRange,
                                    streamedText: streamedText
                                ),
                                revealFromCharacterCount: action == .continueWriting ? beforeSnapshot.documentText.count : 0
                            )
                        }

                    case .completed(let response):
                        finalResponse = response
                    }
                }

                if let previewRenderer {
                    previewRenderer.markStreamCompleted()
                    await previewRenderer.waitForCompletion()
                }

                guard let response = finalResponse else {
                    throw WritingAIClientError.invalidResponse("AI stream did not produce a final response.")
                }
                let patch = try WritingEditPatch.build(
                    action: action,
                    before: beforeSnapshot,
                    after: response.snapshotByApplyingDocumentText(response.documentText, to: beforeSnapshot),
                    selectionRange: selectionRange,
                    userMessage: requestUserMessage
                )
                guard isCurrentRequest(requestToken) else {
                    return
                }
                let updatedDocumentText = try patch.apply(
                    to: beforeSnapshot.documentText,
                    lock: requestLock
                )
                guard isCurrentRequest(requestToken) else {
                    return
                }
                liveProject.applyEditingResponse(response, documentText: updatedDocumentText)
                liveProject.recordRevision(
                    patch: patch,
                    before: beforeSnapshot,
                    after: liveProject.aiSnapshot
                )
                replaceActiveProject(liveProject)
                if let currentDocumentURL {
                    _ = saveCurrentDocument(to: currentDocumentURL)
                }
            } catch {
                VibeWriteLog.ai.error(
                    "Flow AI request failed action=\(action.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                replaceActiveProject(project)
                aiErrorMessage = error.localizedDescription
                throw error
            }
            return
        }

        do {
            let beforeSnapshot = project.aiSnapshot
            var liveProject = project
            if let requestUserMessage {
                let alreadyHasMatchingUserMessage = action == .startDraft && project.conversation.contains { message in
                    message.role == .user && message.text.trimmingCharacters(in: .whitespacesAndNewlines) == requestUserMessage
                }

                if !alreadyHasMatchingUserMessage {
                    liveProject.appendUserMessage(requestUserMessage)
                }

                if action == .startDraft {
                    liveProject.prompt = requestUserMessage
                }
            }
            liveProject.localSummary = streamingSummary(for: action)
            liveProject.nextFocus = ""
            liveProject.suggestionChips = []
            replaceActiveProject(liveProject)

            let proseRequest = WritingAIRequest(
                action: action,
                project: liveProject.aiSnapshot,
                userMessage: requestUserMessage,
                selectionText: normalizedSelectionText ?? selectionText,
                selectionRange: selectionRange,
                kind: .prose
            )

            var streamedText = ""
            let proseNetworkStartedAt = Date()
            let previewRenderer = WritingStreamingPreviewRenderer(configuration: streamingConfiguration) { renderedText in
                guard self.isCurrentRequest(requestToken) else { return }
                liveProject.documentText = renderedText
                self.replaceActiveProject(liveProject)
            }
            var finalResponse: WritingAIResponse?
            VibeWriteLog.ai.info(
                "Flow prose request start action=\(action.rawValue, privacy: .public) trace=\(traceID, privacy: .public) docCount=\(proseRequest.project.documentText.count, privacy: .public) selectionCount=\(normalizedSelectionText?.count ?? selectionText?.count ?? 0, privacy: .public)"
            )
            for try await event in aiClient.streamResponse(for: proseRequest) {
                switch event {
                case .textDelta(let delta):
                    streamedText += delta
                    previewRenderer.updateTargetText(
                        previewDocumentText(
                            for: action,
                            baseDocumentText: beforeSnapshot.documentText,
                            selectionRange: selectionRange,
                            streamedText: streamedText
                        ),
                        revealFromCharacterCount: action == .continueWriting ? beforeSnapshot.documentText.count : 0
                    )

                case .completed(let response):
                    finalResponse = response
                }
            }
            let proseNetworkElapsed = Self.elapsedSeconds(since: proseNetworkStartedAt)
            VibeWriteLog.ai.info(
                "Flow prose network stream finished action=\(action.rawValue, privacy: .public) trace=\(traceID, privacy: .public) streamSeconds=\(proseNetworkElapsed, privacy: .public) streamedCount=\(streamedText.count, privacy: .public) previewTailWillContinue=true"
            )
            isBodyThinkingInFlight = false
            isAIRequestInFlight = false

            previewRenderer.markStreamCompleted()
            guard isCurrentRequest(requestToken) else {
                return
            }
            guard let response = finalResponse else {
                throw WritingAIClientError.invalidResponse("AI stream did not produce a final response.")
            }
            let patch = try WritingEditPatch.build(
                action: action,
                before: beforeSnapshot,
                after: response.snapshotByApplyingDocumentText(response.documentText, to: beforeSnapshot),
                selectionRange: selectionRange,
                userMessage: requestUserMessage
            )
            guard isCurrentRequest(requestToken) else {
                return
            }
            let updatedDocumentText = try patch.apply(
                to: beforeSnapshot.documentText,
                lock: requestLock
            )
            guard isCurrentRequest(requestToken) else {
                return
            }
            liveProject.applyWritingProseResponse(response, documentText: updatedDocumentText)
            liveProject.recordRevision(
                patch: patch,
                before: beforeSnapshot,
                after: liveProject.aiSnapshot
            )
            replaceActiveProject(liveProject)
            if let currentDocumentURL {
                _ = saveCurrentDocument(to: currentDocumentURL)
            }
            VibeWriteLog.ai.info(
                "Flow prose response complete action=\(action.rawValue, privacy: .public) trace=\(traceID, privacy: .public) documentCount=\(updatedDocumentText.count, privacy: .public)"
            )

            let metadataRequest = WritingAIRequest(
                action: action,
                project: liveProject.aiSnapshot,
                userMessage: requestUserMessage,
                selectionText: normalizedSelectionText ?? selectionText,
                selectionRange: selectionRange,
                kind: .metadata
            )
            let metadataRequestStartedAt = Date()
            VibeWriteLog.ai.info(
                "Flow metadata request start action=\(action.rawValue, privacy: .public) trace=\(traceID, privacy: .public) docCount=\(metadataRequest.project.documentText.count, privacy: .public) suggestionCount=\(metadataRequest.project.suggestionChips.count, privacy: .public)"
            )
            isMetadataRequestInFlight = true
            let metadataTask = Task {
                try await aiClient.generateResponse(for: metadataRequest)
            }

            let prosePlaybackWaitStartedAt = Date()
            VibeWriteLog.ai.info(
                "Flow prose playback wait start action=\(action.rawValue, privacy: .public) trace=\(traceID, privacy: .public)"
            )
            await previewRenderer.waitForCompletion()
            isProseRequestInFlight = false
            let prosePlaybackElapsed = Self.elapsedSeconds(since: prosePlaybackWaitStartedAt)
            VibeWriteLog.ai.info(
                "Flow prose playback wait finished action=\(action.rawValue, privacy: .public) trace=\(traceID, privacy: .public) waitSeconds=\(prosePlaybackElapsed, privacy: .public)"
            )

            do {
                let metadataResponse = try await metadataTask.value
                guard isCurrentRequest(requestToken) else {
                    return
                }
                let metadata = metadataResponse.completionMetadata
                liveProject.applyWritingMetadata(metadata)
                replaceActiveProject(liveProject)
                if let currentDocumentURL {
                    _ = saveCurrentDocument(to: currentDocumentURL)
                }
                let metadataElapsed = Self.elapsedSeconds(since: metadataRequestStartedAt)
                VibeWriteLog.ai.info(
                    "Flow metadata response complete action=\(action.rawValue, privacy: .public) trace=\(traceID, privacy: .public) metadataSeconds=\(metadataElapsed, privacy: .public) localSummaryCount=\(metadata.localSummary.count, privacy: .public) globalSynopsisCount=\(metadata.globalSynopsis.count, privacy: .public) nextFocusCount=\(metadata.nextFocus.count, privacy: .public) suggestionCount=\(metadata.suggestionChips.count, privacy: .public)"
                )
            } catch {
                let metadataElapsed = Self.elapsedSeconds(since: metadataRequestStartedAt)
                VibeWriteLog.ai.error(
                    "Flow metadata request failed action=\(action.rawValue, privacy: .public) trace=\(traceID, privacy: .public) metadataSeconds=\(metadataElapsed, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
            if isCurrentRequest(requestToken) {
                isMetadataRequestInFlight = false
            }
        } catch {
            guard isCurrentRequest(requestToken) else {
                return
            }
            VibeWriteLog.ai.error(
                "Flow AI request failed action=\(action.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            replaceActiveProject(project)
            aiErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func requestUserMessage(
        for action: WritingAIAction,
        userMessage: String?
    ) -> String? {
        let trimmedUserMessage = userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedUserMessage, !trimmedUserMessage.isEmpty else {
            return nil
        }

        return trimmedUserMessage
    }

    private static func shortTraceID() -> String {
        String(UUID().uuidString.prefix(8))
    }

    private static func elapsedSeconds(since start: Date) -> String {
        String(format: "%.2f", Date().timeIntervalSince(start))
    }

    private func setActiveProject(_ project: WritingProject) {
        replaceActiveProject(project)
    }

    private func resetCurrentSessionForDockReopen() {
        projects = []
        activeProjectID = nil
        currentDocumentURL = nil
        savedDocumentContents = VibeWriteMarkdownDocument(project: emptyProjectShell).renderedText()
        documentHydrationProtectedProjectID = nil
        activeEditLock = nil
        aiErrorMessage = nil
        isAIRequestInFlight = false
        isBodyThinkingInFlight = false
        isProseRequestInFlight = false
        isMetadataRequestInFlight = false
        activeRequestToken = nil
    }

    private func isCurrentRequest(_ requestToken: UUID) -> Bool {
        activeRequestToken == requestToken
    }

    private func replaceActiveProject(_ project: WritingProject) {
        let previousProjectID = activeProjectID?.uuidString ?? "nil"
        let currentDocumentURLName = currentDocumentURL?.lastPathComponent ?? "nil"
        let previousActiveCount = self.activeDocumentText.count
        let incomingCount = project.documentText.count
        let projectCount = projects.count
        let hydrationProtected = documentHydrationProtectedProjectID?.uuidString ?? "nil"
        VibeWriteLog.ai.info(
            "flow replaceActiveProject entry incomingProjectID=\(project.id.uuidString, privacy: .public) incomingCount=\(incomingCount, privacy: .public) previousProjectID=\(previousProjectID, privacy: .public) previousActiveCount=\(previousActiveCount, privacy: .public) projectCount=\(projectCount, privacy: .public) currentURL=\(currentDocumentURLName, privacy: .public) hydrationProtected=\(hydrationProtected, privacy: .public)"
        )
        VibeWriteLog.launch.info(
            "flow replaceActiveProject entry incomingProjectID=\(project.id.uuidString, privacy: .public) incomingCount=\(incomingCount, privacy: .public) previousProjectID=\(previousProjectID, privacy: .public) previousActiveCount=\(previousActiveCount, privacy: .public) projectCount=\(projectCount, privacy: .public) currentURL=\(currentDocumentURLName, privacy: .public) hydrationProtected=\(hydrationProtected, privacy: .public)"
        )
        VibeWriteDebugTrace.append(
            "flow replaceActiveProject entry incomingProjectID=\(project.id.uuidString) incomingCount=\(incomingCount) previousProjectID=\(previousProjectID) previousActiveCount=\(previousActiveCount) projectCount=\(projectCount) currentURL=\(currentDocumentURLName) hydrationProtected=\(hydrationProtected)"
        )
        if activeDocumentText != project.documentText {
            VibeWriteLog.ai.info(
                "flow replaceActiveProject sync live text incomingCount=\(incomingCount, privacy: .public) previousActiveCount=\(previousActiveCount, privacy: .public)"
            )
            VibeWriteLog.launch.info(
                "flow replaceActiveProject sync live text incomingCount=\(incomingCount, privacy: .public) previousActiveCount=\(previousActiveCount, privacy: .public)"
            )
            activeDocumentText = project.documentText
        } else {
            VibeWriteLog.ai.info(
                "flow replaceActiveProject live text already aligned count=\(incomingCount, privacy: .public)"
            )
            VibeWriteLog.launch.info(
                "flow replaceActiveProject live text already aligned count=\(incomingCount, privacy: .public)"
            )
        }

        if let currentProject = self.project(for: project.id), currentProject == project, activeProjectID == project.id {
            VibeWriteLog.ai.info(
                "flow replaceActiveProject skipped project unchanged projectID=\(project.id.uuidString, privacy: .public) count=\(incomingCount, privacy: .public)"
            )
            VibeWriteLog.launch.info(
                "flow replaceActiveProject skipped project unchanged projectID=\(project.id.uuidString, privacy: .public) count=\(incomingCount, privacy: .public)"
            )
            return
        }

        projects = [project]
        activeProjectID = project.id
        VibeWriteLog.ai.info(
            "flow replaceActiveProject applied projectID=\(project.id.uuidString, privacy: .public) projectCount=1 activeCount=\(self.activeDocumentText.count, privacy: .public)"
        )
        VibeWriteLog.launch.info(
            "flow replaceActiveProject applied projectID=\(project.id.uuidString, privacy: .public) projectCount=1 activeCount=\(self.activeDocumentText.count, privacy: .public)"
        )
        VibeWriteDebugTrace.append(
            "flow replaceActiveProject applied projectID=\(project.id.uuidString) projectCount=1 activeCount=\(self.activeDocumentText.count)"
        )
    }

    @discardableResult
    private func saveCurrentDocument(
        to url: URL,
        project: WritingProject,
        updateActiveProject: Bool
    ) -> Bool {
        let document = VibeWriteMarkdownDocument(project: project)
        let renderedText = document.renderedText()
        let currentDocumentURLName = currentDocumentURL?.lastPathComponent ?? "nil"
        let projectCount = project.documentText.count
        let renderedCount = renderedText.count
        let titlePreview = project.title.vibewriteLogPreview(maxLength: 60)
        VibeWriteLog.ai.info(
            "flow saveCurrentDocument start projectID=\(project.id.uuidString, privacy: .public) title=\(titlePreview, privacy: .public) documentCount=\(projectCount, privacy: .public) renderedCount=\(renderedCount, privacy: .public) updateActiveProject=\(updateActiveProject, privacy: .public) currentURL=\(currentDocumentURLName, privacy: .public)"
        )
        VibeWriteLog.launch.info(
            "flow saveCurrentDocument start projectID=\(project.id.uuidString, privacy: .public) title=\(titlePreview, privacy: .public) documentCount=\(projectCount, privacy: .public) renderedCount=\(renderedCount, privacy: .public) updateActiveProject=\(updateActiveProject, privacy: .public) currentURL=\(currentDocumentURLName, privacy: .public)"
        )
        VibeWriteDebugTrace.append(
            "flow saveCurrentDocument start projectID=\(project.id.uuidString) title=\(project.title) documentCount=\(project.documentText.count) renderedCount=\(renderedText.count) updateActiveProject=\(updateActiveProject) currentURL=\(currentDocumentURLName)"
        )

        do {
            try ensureDocumentParentDirectoryExists(for: url)
            try renderedText.write(to: url, atomically: true, encoding: .utf8)
            if let identityMarker = document.identityMarker {
                _ = documentIdentityStore.writeDocumentID(identityMarker, to: url)
            }
            documentMetadataStore.save(project: project)
            if updateActiveProject {
                replaceActiveProject(project)
            }
            currentDocumentURL = url
            savedDocumentContents = renderedText
            let savedCount = renderedText.count
            VibeWriteLog.ai.info(
                "flow saveCurrentDocument applied projectID=\(project.id.uuidString, privacy: .public) savedCount=\(savedCount, privacy: .public) currentURL=\(url.lastPathComponent, privacy: .public)"
            )
            VibeWriteLog.launch.info(
                "flow saveCurrentDocument applied projectID=\(project.id.uuidString, privacy: .public) savedCount=\(savedCount, privacy: .public) currentURL=\(url.lastPathComponent, privacy: .public)"
            )
            VibeWriteDebugTrace.append(
                "flow saveCurrentDocument applied projectID=\(project.id.uuidString) savedCount=\(savedDocumentContents?.count ?? -1) currentURL=\(url.lastPathComponent)"
            )
            recordRecentDocument(url: url, title: project.title)
            return true
        } catch {
            VibeWriteLog.ai.error(
                "flow saveCurrentDocument failed projectID=\(project.id.uuidString, privacy: .public) title=\(project.title.vibewriteLogPreview(maxLength: 60), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            VibeWriteLog.launch.error(
                "flow saveCurrentDocument failed projectID=\(project.id.uuidString, privacy: .public) title=\(project.title.vibewriteLogPreview(maxLength: 60), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            aiErrorMessage = error.localizedDescription
            return false
        }
    }

    private func project(for id: UUID) -> WritingProject? {
        projects.first(where: { $0.id == id })
    }

    private func previewDocumentText(
        for action: WritingAIAction,
        baseDocumentText: String,
        selectionRange: WritingTextSelectionRange?,
        streamedText: String
    ) -> String {
        switch action {
        case .startDraft:
            return streamedText

        case .continueWriting:
            return baseDocumentText + streamedText

        case .edit:
            guard let selectionRange,
                  let targetRange = selectionRange.range(in: baseDocumentText) else {
                return baseDocumentText
            }

            var preview = baseDocumentText
            preview.replaceSubrange(targetRange, with: streamedText)
            return preview
        }
    }

    private func streamingSummary(for action: WritingAIAction) -> String {
        switch action {
        case .startDraft:
            return "正在生成第一稿"
        case .continueWriting:
            return "正在续写下一段"
        case .edit:
            return "局部润色中"
        }
    }

    func saveCurrentDocument() -> Bool {
        let currentDocumentURLName = currentDocumentURL?.lastPathComponent ?? "nil"
        let dirty = isCurrentDocumentDirty
        let activeCount = activeDocumentText.count
        VibeWriteLog.ai.info(
            "flow saveCurrentDocument entry currentURL=\(currentDocumentURLName, privacy: .public) dirty=\(dirty, privacy: .public) activeCount=\(activeCount, privacy: .public)"
        )
        VibeWriteLog.launch.info(
            "flow saveCurrentDocument entry currentURL=\(currentDocumentURLName, privacy: .public) dirty=\(dirty, privacy: .public) activeCount=\(activeCount, privacy: .public)"
        )
        if let currentDocumentURL {
            return saveCurrentDocument(to: currentDocumentURL)
        }

        return saveCurrentDocumentAs()
    }

    func saveCurrentDocumentAs() -> Bool {
        let currentDocumentURLName = currentDocumentURL?.lastPathComponent ?? "nil"
        let dirty = isCurrentDocumentDirty
        let activeCount = activeDocumentText.count
        VibeWriteLog.ai.info(
            "flow saveCurrentDocumentAs entry currentURL=\(currentDocumentURLName, privacy: .public) dirty=\(dirty, privacy: .public) activeCount=\(activeCount, privacy: .public)"
        )
        VibeWriteLog.launch.info(
            "flow saveCurrentDocumentAs entry currentURL=\(currentDocumentURLName, privacy: .public) dirty=\(dirty, privacy: .public) activeCount=\(activeCount, privacy: .public)"
        )
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = saveFileNameSuggestion()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText
        ]
        panel.title = "保存写作文件"

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        let projectToSave = currentDocumentURL == nil
            ? projectForInitialSave(at: url)
            : activeEditingProject.forkedSaveAsCopy()
        return saveCurrentDocument(
            to: url,
            project: projectToSave,
            updateActiveProject: true
        )
    }

    func saveCurrentDocument(to url: URL) -> Bool {
        let currentDocumentURLName = currentDocumentURL?.lastPathComponent ?? "nil"
        let dirty = isCurrentDocumentDirty
        let activeCount = activeDocumentText.count
        VibeWriteLog.ai.info(
            "flow saveCurrentDocument to-url entry targetURL=\(url.lastPathComponent, privacy: .public) currentURL=\(currentDocumentURLName, privacy: .public) dirty=\(dirty, privacy: .public) activeCount=\(activeCount, privacy: .public)"
        )
        VibeWriteLog.launch.info(
            "flow saveCurrentDocument to-url entry targetURL=\(url.lastPathComponent, privacy: .public) currentURL=\(currentDocumentURLName, privacy: .public) dirty=\(dirty, privacy: .public) activeCount=\(activeCount, privacy: .public)"
        )
        return saveCurrentDocument(to: url, project: activeEditingProject, updateActiveProject: true)
    }

    func openDocumentFromPanel() -> Bool {
        let currentURLName = currentDocumentURL?.lastPathComponent ?? "nil"
        let dirty = isCurrentDocumentDirty
        let activeCount = activeDocumentText.count
        VibeWriteLog.ai.info(
            "flow openDocumentFromPanel entry currentURL=\(currentURLName, privacy: .public) dirty=\(dirty, privacy: .public) activeCount=\(activeCount, privacy: .public)"
        )
        guard confirmDiscardCurrentChangesIfNeeded() else {
            return false
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText
        ]
        panel.title = "打开写作文件"

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        return openDocument(at: url)
    }

    func openDocument(at url: URL) -> Bool {
        do {
            let rawText = try String(contentsOf: url, encoding: .utf8)
            let parsedDocument = VibeWriteMarkdownDocument.parse(from: rawText)
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            let fallbackAutomationKey = url.deletingPathExtension().lastPathComponent
            let resolvedMarker = documentIdentityStore.readDocumentID(from: url) ?? parsedDocument.identityMarker
            let metadataRecord = resolvedMarker.flatMap { documentMetadataStore.loadRecord(documentID: $0.documentID) }
            let resolvedMarkerID = resolvedMarker?.documentID.uuidString ?? "nil"
            VibeWriteLog.ai.info(
                "flow openDocument parse url=\(url.lastPathComponent, privacy: .public) rawCount=\(rawText.count, privacy: .public) bodyCount=\(parsedDocument.body.count, privacy: .public) hasIdentityMarker=\(parsedDocument.identityMarker != nil, privacy: .public) resolvedMarker=\(resolvedMarkerID, privacy: .public) metadataFound=\(metadataRecord != nil, privacy: .public)"
            )
            VibeWriteLog.launch.info(
                "flow openDocument parse url=\(url.lastPathComponent, privacy: .public) rawCount=\(rawText.count, privacy: .public) bodyCount=\(parsedDocument.body.count, privacy: .public) hasIdentityMarker=\(parsedDocument.identityMarker != nil, privacy: .public) resolvedMarker=\(resolvedMarkerID, privacy: .public) metadataFound=\(metadataRecord != nil, privacy: .public)"
            )
            let project = metadataRecord?
                .makeProject(
                    documentText: parsedDocument.body,
                    fallbackTitle: fallbackTitle,
                    fallbackAutomationKey: fallbackAutomationKey
                )
                ?? parsedDocument.makeProject(
                    documentID: resolvedMarker?.documentID,
                    fallbackTitle: fallbackTitle,
                    fallbackAutomationKey: fallbackAutomationKey
                )
            VibeWriteLog.ai.info(
                "flow openDocument project resolved url=\(url.lastPathComponent, privacy: .public) projectID=\(project.id.uuidString, privacy: .public) projectCount=\(project.documentText.count, privacy: .public) activeCountBefore=\(self.activeDocumentText.count, privacy: .public)"
            )
            VibeWriteLog.launch.info(
                "flow openDocument project resolved url=\(url.lastPathComponent, privacy: .public) projectID=\(project.id.uuidString, privacy: .public) projectCount=\(project.documentText.count, privacy: .public) activeCountBefore=\(self.activeDocumentText.count, privacy: .public)"
            )
            currentDocumentURL = url
            savedDocumentContents = rawText
            activeDocumentText = project.documentText
            VibeWriteLog.ai.info(
                "flow openDocument staged projectID=\(project.id.uuidString, privacy: .public) title=\(project.title.vibewriteLogPreview(maxLength: 60), privacy: .public) documentCount=\(project.documentText.count, privacy: .public) currentURL=\(url.lastPathComponent, privacy: .public)"
            )
            VibeWriteLog.launch.info(
                "flow openDocument staged projectID=\(project.id.uuidString, privacy: .public) title=\(project.title.vibewriteLogPreview(maxLength: 60), privacy: .public) documentCount=\(project.documentText.count, privacy: .public) currentURL=\(url.lastPathComponent, privacy: .public)"
            )
            beginDocumentHydration(for: project.id)
            openProject(project)
            DispatchQueue.main.async { [weak self, projectID = project.id] in
                self?.endDocumentHydration(for: projectID)
            }
            let savedCount = self.savedDocumentContents?.count ?? -1
            let activeCount = self.activeDocumentText.count
            VibeWriteLog.ai.info(
                "flow openDocument applied url=\(url.lastPathComponent, privacy: .public) projectID=\(project.id.uuidString, privacy: .public) savedCount=\(savedCount, privacy: .public) activeCount=\(activeCount, privacy: .public)"
            )
            let currentURLName = currentDocumentURL?.lastPathComponent ?? "nil"
            VibeWriteDebugTrace.append(
                "flow openDocument applied url=\(url.lastPathComponent) projectID=\(project.id.uuidString) currentURL=\(currentURLName) savedCount=\(savedDocumentContents?.count ?? -1) activeCount=\(activeDocumentText.count)"
            )
            recordRecentDocument(url: url, title: project.title)
            return true
        } catch {
            aiErrorMessage = error.localizedDescription
            return false
        }
    }

    func openRecentDocument(_ entry: RecentDocumentEntry) -> Bool {
        guard confirmDiscardCurrentChangesIfNeeded() else {
            return false
        }

        return openDocument(at: entry.url)
    }

    func handleWindowCloseRequest() -> Bool {
        guard confirmDiscardCurrentChangesIfNeeded() else {
            return false
        }

        resetCurrentSessionForDockReopen()
        return true
    }

    private func recordRecentDocument(url: URL, title: String) {
        let entry = RecentDocumentEntry(
            url: url,
            title: title,
            lastOpenedAt: .now
        )

        var updatedEntries = recentDocumentEntries.filter { $0.url != url }
        updatedEntries.insert(entry, at: 0)
        recentDocumentEntries = updatedEntries
        recentDocumentStore.save(entries: updatedEntries)
    }

    private func saveFileNameSuggestion() -> String {
        let cleanedTitle = activeEditingProject.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")

        if cleanedTitle.isEmpty {
            return "未命名写作.md"
        }

        if cleanedTitle.hasSuffix(".md") || cleanedTitle.hasSuffix(".markdown") {
            return cleanedTitle
        }

        return cleanedTitle + ".md"
    }

    func projectForInitialSave(at url: URL) -> WritingProject {
        var project = activeEditingProject
        let initialSaveTitle = initialSaveTitle(for: url)
        if project.title != initialSaveTitle {
            project.title = initialSaveTitle
        }
        return project
    }

    private func initialSaveTitle(for url: URL) -> String {
        let candidateTitle = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return candidateTitle.isEmpty ? activeEditingProject.title : candidateTitle
    }

    private func ensureDocumentParentDirectoryExists(for url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parentDirectory.path) {
            return
        }

        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
    }

    private func confirmDiscardCurrentChangesIfNeeded() -> Bool {
        let currentDocumentURLName = currentDocumentURL?.lastPathComponent ?? "nil"
        let dirty = isCurrentDocumentDirty
        let pristineBlank = isPristineBlankSession
        let activeCount = activeDocumentText.count
        let savedCount = savedDocumentContents?.count ?? -1
        let fileCount = currentDocumentFileText.count
        VibeWriteLog.ai.info(
            "flow discard prompt check currentURL=\(currentDocumentURLName, privacy: .public) dirty=\(dirty, privacy: .public) pristineBlank=\(pristineBlank, privacy: .public) activeCount=\(activeCount, privacy: .public) fileCount=\(fileCount, privacy: .public) savedCount=\(savedCount, privacy: .public)"
        )
        VibeWriteLog.launch.info(
            "flow discard prompt check currentURL=\(currentDocumentURLName, privacy: .public) dirty=\(dirty, privacy: .public) pristineBlank=\(pristineBlank, privacy: .public) activeCount=\(activeCount, privacy: .public) fileCount=\(fileCount, privacy: .public) savedCount=\(savedCount, privacy: .public)"
        )
        if pristineBlank {
            VibeWriteDebugTrace.append("flow discard prompt skipped pristine blank session")
            VibeWriteLog.ai.info("flow discard prompt skipped pristine blank session")
            VibeWriteLog.launch.info("flow discard prompt skipped pristine blank session")
            return true
        }

        guard dirty else {
            VibeWriteLog.ai.info("flow discard prompt bypassed clean session")
            VibeWriteLog.launch.info("flow discard prompt bypassed clean session")
            return true
        }

        let alert = NSAlert()
        alert.messageText = "要保存更改吗？"
        alert.informativeText = "当前写作内容还没有保存。要先保存再继续吗？"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            VibeWriteLog.ai.info("flow discard prompt chose save")
            VibeWriteLog.launch.info("flow discard prompt chose save")
            return saveCurrentDocument()
        case .alertSecondButtonReturn:
            VibeWriteLog.ai.info("flow discard prompt chose dont-save")
            VibeWriteLog.launch.info("flow discard prompt chose dont-save")
            return true
        default:
            VibeWriteLog.ai.info("flow discard prompt cancelled")
            VibeWriteLog.launch.info("flow discard prompt cancelled")
            return false
        }
    }

    private var isPristineBlankSession: Bool {
        guard currentDocumentURL == nil else { return false }

        let project = activeEditingProject
        return project.documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && project.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && project.title == emptyProjectShell.title
            && project.mode == emptyProjectShell.mode
            && project.localSummary == emptyProjectShell.localSummary
            && project.globalSynopsis == emptyProjectShell.globalSynopsis
            && project.context == emptyProjectShell.context
            && project.conversation.isEmpty
            && project.revisionHistory.isEmpty
            && project.suggestionChips == emptyProjectShell.suggestionChips
    }
}
