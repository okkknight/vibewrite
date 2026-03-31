import Foundation
import SwiftUI

@MainActor
final class VibeWriteAppFlow: ObservableObject {
    @Published var screen: AppScreen
    @Published private(set) var projects: [WritingProject]
    @Published private(set) var activeProjectID: UUID?
    @Published private(set) var isAIRequestInFlight = false
    @Published private(set) var aiErrorMessage: String?

    private let store: LocalProjectStore
    private let aiClient: any WritingAIClient

    init(
        storageURL: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        aiClient: (any WritingAIClient)? = nil,
        aiConfiguration: WritingAIConfiguration = .current()
    ) {
        let environmentStorageURL = ProcessInfo.processInfo.environment["VIBEWRITE_STORAGE_URL"].flatMap {
            URL(fileURLWithPath: $0)
        }
        let resolvedStore = LocalProjectStore(
            storageURL: storageURL ?? environmentStorageURL ?? LocalProjectStore.defaultStorageURL(fileManager: fileManager),
            fileManager: fileManager
        )
        self.store = resolvedStore
        self.aiClient = aiClient ?? WritingAIClientFactory.makeDefaultClient(configuration: aiConfiguration)

        if let snapshot = resolvedStore.load(), !snapshot.projects.isEmpty {
            self.projects = snapshot.projects
            let restoredProjectID = snapshot.lastOpenedProjectID.flatMap { candidate in
                snapshot.projects.contains(where: { $0.id == candidate }) ? candidate : nil
            }
            self.activeProjectID = restoredProjectID ?? snapshot.projects.first?.id
            self.screen = restoredProjectID == nil ? .home : .project
        } else {
            let seededProjects = WorkspaceFixtures.bootstrapProjects(now: now())
            self.projects = seededProjects
            self.activeProjectID = nil
            self.screen = .home
            resolvedStore.save(projects: seededProjects, lastOpenedProjectID: nil)
        }
    }

    var recentProjects: [WritingProject] {
        projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeProject: WritingProject {
        get {
            if let activeProjectID, let project = project(for: activeProjectID) {
                return project
            }

            if let firstProject = projects.first {
                return firstProject
            }

            let fallbackProject = WorkspaceFixtures.bootstrapProjects(now: .now).first!
            return fallbackProject
        }
        set {
            setActiveProject(newValue)
        }
    }

    var activeProjectBinding: Binding<WritingProject> {
        Binding(
            get: { [weak self] in
                guard let self else {
                    return WorkspaceFixtures.bootstrapProjects(now: .now).first!
                }
                return self.activeProject
            },
            set: { [weak self] updatedProject in
                self?.setActiveProject(updatedProject)
            }
        )
    }

    func openProject(_ project: WritingProject) {
        setActiveProject(project)
        screen = .project
        persist()
    }

    func createNewProject() {
        let project = WritingProject.quickStart(
            prompt: "写一篇关于成年人孤独感的公众号文章",
            mode: .collaboration,
            automationKey: "project.quickstart.default"
        )
        openProject(project)
        Task { [weak self] in
            guard let self else { return }
            try? await self.performWritingAction(
                .startDraft,
                userMessage: project.prompt,
                selectionText: nil
            )
        }
    }

    func startQuickDraft(prompt: String, mode: WritingProjectMode) {
        let project = WritingProject.quickStart(
            prompt: prompt,
            mode: mode,
            automationKey: "project.quickstart.\(mode.rawValue)"
        )
        openProject(project)
        Task { [weak self] in
            guard let self else { return }
            try? await self.performWritingAction(
                .startDraft,
                userMessage: prompt,
                selectionText: nil
            )
        }
    }

    func returnHome() {
        screen = .home
        persist()
    }

    func performWritingAction(
        _ action: WritingAIAction,
        userMessage: String? = nil,
        selectionText: String? = nil
    ) async throws {
        guard !isAIRequestInFlight else {
            throw WritingAIClientError.requestFailed("已有请求正在进行，请稍后再试。")
        }

        isAIRequestInFlight = true
        aiErrorMessage = nil
        defer {
            isAIRequestInFlight = false
        }

        let project = activeProject
        let requestUserMessage = requestUserMessage(
            for: action,
            userMessage: userMessage,
            project: project
        )

        let request = WritingAIRequest(
            action: action,
            project: project.aiSnapshot,
            userMessage: requestUserMessage,
            selectionText: selectionText
        )

        do {
            let response = try await aiClient.generateResponse(for: request)
            var updatedProject = project
            if let requestUserMessage {
                updatedProject.appendUserMessage(requestUserMessage)
                if action == .startDraft {
                    updatedProject.prompt = requestUserMessage
                }
            }
            updatedProject.apply(aiResponse: response)
            activeProject = updatedProject
            screen = .project
            persist()
        } catch {
            aiErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func requestUserMessage(
        for action: WritingAIAction,
        userMessage: String?,
        project: WritingProject
    ) -> String? {
        let trimmedUserMessage = userMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedUserMessage, !trimmedUserMessage.isEmpty else {
            return nil
        }

        if action == .startDraft {
            let trimmedProjectPrompt = project.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedUserMessage == trimmedProjectPrompt {
                return nil
            }
        }

        return trimmedUserMessage
    }

    private func setActiveProject(_ project: WritingProject) {
        upsert(project)
        activeProjectID = project.id
        persist()
    }

    private func upsert(_ project: WritingProject) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
    }

    private func project(for id: UUID) -> WritingProject? {
        projects.first(where: { $0.id == id })
    }

    private func persist() {
        store.save(projects: projects, lastOpenedProjectID: activeProjectID)
    }
}

enum AppScreen: Hashable {
    case home
    case project
}
