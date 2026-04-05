import Foundation
import AppKit
import UniformTypeIdentifiers
import SwiftUI

@MainActor
final class VibeWriteAppFlow: ObservableObject {
    @Published private(set) var projects: [WritingProject]
    @Published private(set) var activeProjectID: UUID?
    @Published private(set) var isAIRequestInFlight = false
    @Published private(set) var isProseRequestInFlight = false
    @Published private(set) var isMetadataRequestInFlight = false
    @Published private(set) var activeEditLock: WritingEditLock?
    @Published private(set) var aiErrorMessage: String?
    @Published private(set) var currentDocumentURL: URL?
    @Published private(set) var recentDocumentEntries: [RecentDocumentEntry]

    private let recentDocumentStore: RecentDocumentStore
    private let documentMetadataStore: VibeWriteDocumentMetadataStore
    private let documentIdentityStore: VibeWriteDocumentIdentityStore
    private let aiClient: any WritingAIClient
    private let streamingConfiguration: WritingStreamingConfiguration
    private let emptyProjectShell: WritingProject
    private var savedDocumentContents: String?
    private var documentHydrationProtectedProjectID: UUID?

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

        if forceBlankStartup || shouldResetStorage {
            self.projects = []
            self.activeProjectID = nil
            resolvedStore.clear()
            documentMetadataStore.clear()
            self.recentDocumentEntries = []
            self.savedDocumentContents = VibeWriteMarkdownDocument(project: self.emptyProjectShell).renderedText()
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
        VibeWriteMarkdownDocument(project: activeProject).renderedText()
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

    var activeProjectBinding: Binding<WritingProject> {
        Binding(
            get: { [weak self] in
                guard let self else {
                    return WritingProject.entryShell(mode: .collaboration)
                }
                return self.activeProject
            },
            set: { [weak self] updatedProject in
                self?.replaceActiveProject(updatedProject, persist: false)
            }
        )
    }

    func openProject(_ project: WritingProject) {
        replaceActiveProject(project, persist: false)
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

        var updatedProject = activeProject
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
        activeEditLock = nil
        aiErrorMessage = nil
        isAIRequestInFlight = false
        isProseRequestInFlight = false
        isMetadataRequestInFlight = false
    }

    @discardableResult
    func undoLastRevision() -> WritingProjectRevision? {
        var project = activeProject
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

        let project = activeProject
        isAIRequestInFlight = true
        isProseRequestInFlight = true
        isMetadataRequestInFlight = false
        activeEditLock = WritingEditLock(
            action: action,
            lockedSelectionText: selectionRange.flatMap { $0.substring(in: project.documentText)?.trimmingCharacters(in: .whitespacesAndNewlines) } ?? selectionText,
            lockedDocumentText: activeProject.documentText
        )
        aiErrorMessage = nil
        defer {
            isAIRequestInFlight = false
            isProseRequestInFlight = false
            isMetadataRequestInFlight = false
            activeEditLock = nil
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
                liveProject.summary = streamingSummary(for: action)
                replaceActiveProject(liveProject, persist: false)

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
                let updatedDocumentText = try patch.apply(
                    to: beforeSnapshot.documentText,
                    lock: activeEditLock
                )
                liveProject.applyEditingResponse(response, documentText: updatedDocumentText)
                liveProject.recordRevision(
                    patch: patch,
                    before: beforeSnapshot,
                    after: liveProject.aiSnapshot
                )
                replaceActiveProject(liveProject, persist: false)
                if let currentDocumentURL {
                    _ = saveCurrentDocument(to: currentDocumentURL)
                }
            } catch {
                VibeWriteLog.ai.error(
                    "Flow AI request failed action=\(action.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                replaceActiveProject(project, persist: false)
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
            liveProject.summary = streamingSummary(for: action)
            liveProject.nextFocus = ""
            liveProject.suggestionChips = []
            replaceActiveProject(liveProject, persist: false)

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
                liveProject.documentText = renderedText
                self.replaceActiveProject(liveProject, persist: false)
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

            previewRenderer.markStreamCompleted()
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
            let updatedDocumentText = try patch.apply(
                to: beforeSnapshot.documentText,
                lock: activeEditLock
            )
            liveProject.applyWritingProseResponse(response, documentText: updatedDocumentText)
            liveProject.recordRevision(
                patch: patch,
                before: beforeSnapshot,
                after: liveProject.aiSnapshot
            )
            replaceActiveProject(liveProject, persist: false)
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
                let metadata = metadataResponse.completionMetadata
                liveProject.applyWritingMetadata(metadata)
                replaceActiveProject(liveProject, persist: false)
                if let currentDocumentURL {
                    _ = saveCurrentDocument(to: currentDocumentURL)
                }
                let metadataElapsed = Self.elapsedSeconds(since: metadataRequestStartedAt)
                VibeWriteLog.ai.info(
                    "Flow metadata response complete action=\(action.rawValue, privacy: .public) trace=\(traceID, privacy: .public) metadataSeconds=\(metadataElapsed, privacy: .public) summaryCount=\(metadata.summary.count, privacy: .public) nextFocusCount=\(metadata.nextFocus.count, privacy: .public) suggestionCount=\(metadata.suggestionChips.count, privacy: .public)"
                )
            } catch {
                let metadataElapsed = Self.elapsedSeconds(since: metadataRequestStartedAt)
                VibeWriteLog.ai.error(
                    "Flow metadata request failed action=\(action.rawValue, privacy: .public) trace=\(traceID, privacy: .public) metadataSeconds=\(metadataElapsed, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
            isMetadataRequestInFlight = false
        } catch {
            VibeWriteLog.ai.error(
                "Flow AI request failed action=\(action.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            replaceActiveProject(project, persist: false)
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
        replaceActiveProject(project, persist: false)
    }

    private func replaceActiveProject(_ project: WritingProject, persist: Bool) {
        if let currentProject = self.project(for: project.id), currentProject == project, activeProjectID == project.id {
            return
        }

        projects = [project]
        activeProjectID = project.id
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
                replaceActiveProject(project, persist: false)
            }
            currentDocumentURL = url
            savedDocumentContents = renderedText
            VibeWriteDebugTrace.append(
                "flow saveCurrentDocument applied projectID=\(project.id.uuidString) savedCount=\(savedDocumentContents?.count ?? -1) currentURL=\(url.lastPathComponent)"
            )
            recordRecentDocument(url: url, title: project.title)
            return true
        } catch {
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
        if let currentDocumentURL {
            return saveCurrentDocument(to: currentDocumentURL)
        }

        return saveCurrentDocumentAs()
    }

    func saveCurrentDocumentAs() -> Bool {
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

        let projectToSave = currentDocumentURL == nil ? activeProject : activeProject.forkedSaveAsCopy()
        return saveCurrentDocument(
            to: url,
            project: projectToSave,
            updateActiveProject: currentDocumentURL != nil
        )
    }

    func saveCurrentDocument(to url: URL) -> Bool {
        saveCurrentDocument(to: url, project: activeProject, updateActiveProject: false)
    }

    func openDocumentFromPanel() -> Bool {
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
            currentDocumentURL = url
            savedDocumentContents = rawText
            beginDocumentHydration(for: project.id)
            openProject(project)
            DispatchQueue.main.async { [weak self, projectID = project.id] in
                self?.endDocumentHydration(for: projectID)
            }
            let currentURLName = currentDocumentURL?.lastPathComponent ?? "nil"
            VibeWriteDebugTrace.append(
                "flow openDocument applied url=\(url.lastPathComponent) projectID=\(project.id.uuidString) currentURL=\(currentURLName) savedCount=\(savedDocumentContents?.count ?? -1) activeCount=\(activeProject.documentText.count)"
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
        confirmDiscardCurrentChangesIfNeeded()
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
        let cleanedTitle = activeProject.title
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

    private func ensureDocumentParentDirectoryExists(for url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parentDirectory.path) {
            return
        }

        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
    }

    private func confirmDiscardCurrentChangesIfNeeded() -> Bool {
        guard isCurrentDocumentDirty else {
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
            return saveCurrentDocument()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}
