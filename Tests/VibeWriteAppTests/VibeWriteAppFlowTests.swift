import XCTest
@testable import VibeWriteApp

@MainActor
final class VibeWriteAppFlowTests: XCTestCase {
    func testCreateNewProjectOpensBlankCollaborationShell() {
        let flow = VibeWriteAppFlow()

        flow.createNewProject()

        XCTAssertEqual(flow.activeProject.mode, .collaboration)
        XCTAssertTrue(flow.activeProject.documentText.isEmpty)
        XCTAssertTrue(flow.activeProject.prompt.isEmpty)
        XCTAssertTrue(flow.activeProject.conversation.isEmpty)
        XCTAssertEqual(flow.activeProject.localSummary, "等待起稿输入")
        XCTAssertEqual(flow.activeProject.mode.stageTitle, "正文协作中")
        XCTAssertEqual(flow.activeProject.automationKey, "project.new.blank")
    }

    func testBlankStartupDoesNotBootstrapSampleProjects() throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL)

        XCTAssertTrue(flow.projects.isEmpty)
        XCTAssertNil(flow.activeProjectID)
        XCTAssertTrue(flow.recentProjects.isEmpty)
    }

    func testActiveDocumentTextIsTrackedSeparatelyFromProjectSnapshot() {
        let flow = VibeWriteAppFlow()
        flow.createNewProject()

        XCTAssertTrue(flow.activeProject.documentText.isEmpty)
        XCTAssertTrue(flow.activeDocumentText.isEmpty)

        flow.activeDocumentTextBinding.wrappedValue = "typed draft"

        XCTAssertTrue(flow.activeProject.documentText.isEmpty)
        XCTAssertEqual(flow.activeDocumentText, "typed draft")
        XCTAssertEqual(flow.activeEditingProject.documentText, "typed draft")
    }

    func testBlankStartupStartsCleanBeforeEditing() throws {
        let flow = VibeWriteAppFlow()

        XCTAssertFalse(flow.isCurrentDocumentDirty)

        flow.createNewProject()

        XCTAssertFalse(flow.isCurrentDocumentDirty)
        XCTAssertEqual(flow.activeProject.documentText, "")
    }

    func testSaveCurrentDocumentUsesLiveDocumentTextSnapshot() throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL)
        flow.createNewProject()
        flow.activeDocumentTextBinding.wrappedValue = "typed draft"

        let documentURL = storageURL.deletingLastPathComponent().appendingPathComponent("draft.md")
        XCTAssertTrue(flow.saveCurrentDocument(to: documentURL))

        let rawText = try String(contentsOf: documentURL, encoding: .utf8)
        XCTAssertTrue(rawText.contains("typed draft"))
        XCTAssertEqual(flow.activeProject.documentText, "typed draft")
        XCTAssertEqual(flow.activeDocumentText, "typed draft")
    }

    func testInitialSaveProjectUsesChosenFilenameAsTitle() throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL)
        flow.createNewProject()
        flow.activeDocumentTextBinding.wrappedValue = "typed draft"

        let saveURL = storageURL.deletingLastPathComponent().appendingPathComponent("我写的第一篇文章.md")
        let project = flow.projectForInitialSave(at: saveURL)

        XCTAssertEqual(project.title, "我写的第一篇文章")
        XCTAssertEqual(project.documentText, "typed draft")
        XCTAssertEqual(flow.activeProject.title, "未命名写作")
    }

    func testRenameActiveProjectPreservesLiveDocumentText() {
        let flow = VibeWriteAppFlow()
        flow.createNewProject()
        flow.activeDocumentTextBinding.wrappedValue = "typed draft"

        flow.renameActiveProject(to: "新的标题")

        XCTAssertEqual(flow.activeProject.title, "新的标题")
        XCTAssertEqual(flow.activeDocumentText, "typed draft")
        XCTAssertEqual(flow.activeEditingProject.documentText, "typed draft")
    }

    func testBlankStartupWindowCloseBypassesDiscardPrompt() {
        let flow = VibeWriteAppFlow()

        XCTAssertTrue(flow.handleWindowCloseRequest())

        flow.createNewProject()

        XCTAssertTrue(flow.handleWindowCloseRequest())
    }

    func testWindowCloseResetsCurrentSessionButPreservesRecentHistory() throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL)
        let project = WritingProject.entryShell(
            prompt: "写一个雨夜重逢的小说场景",
            mode: .collaboration,
            automationKey: "project.close.reset"
        )
        flow.openProject(project)

        let documentURL = storageURL.deletingPathExtension().appendingPathExtension("md")
        XCTAssertTrue(flow.saveCurrentDocument(to: documentURL))
        XCTAssertFalse(flow.recentDocumentEntries.isEmpty)

        XCTAssertTrue(flow.handleWindowCloseRequest())

        XCTAssertNil(flow.currentDocumentURL)
        XCTAssertNil(flow.activeProjectID)
        XCTAssertTrue(flow.projects.isEmpty)
        XCTAssertTrue(flow.activeProject.documentText.isEmpty)
        XCTAssertTrue(flow.activeProject.prompt.isEmpty)
        XCTAssertFalse(flow.recentDocumentEntries.isEmpty)
        XCTAssertTrue(flow.recentDocumentEntries.contains(where: { $0.url == documentURL }))
        XCTAssertFalse(flow.isCurrentDocumentDirty)
    }

    func testDocumentHydrationProtectionIsScopedToTheOpenedProject() {
        let flow = VibeWriteAppFlow()
        let project = WritingProject.entryShell(
            prompt: "写一个雨夜重逢的小说场景",
            mode: .collaboration,
            automationKey: "project.hydration.demo"
        )

        XCTAssertFalse(flow.isDocumentHydrationProtected(for: project.id))

        flow.beginDocumentHydration(for: project.id)

        XCTAssertTrue(flow.isDocumentHydrationProtected(for: project.id))
        XCTAssertFalse(flow.isDocumentHydrationProtected(for: UUID()))

        flow.endDocumentHydration(for: project.id)

        XCTAssertFalse(flow.isDocumentHydrationProtected(for: project.id))
    }

    func testEmptyActiveProjectFallsBackToCollaborationShell() {
        let flow = VibeWriteAppFlow(forceBlankStartup: true)

        XCTAssertEqual(flow.activeProject.mode, .collaboration)
        XCTAssertEqual(flow.activeProject.mode.stageTitle, "正文协作中")
    }

    func testProjectShellLayoutModeUsesCompactThreshold() {
        XCTAssertTrue(ProjectShellLayoutMode(windowWidth: 1079).isCompact)
        XCTAssertTrue(ProjectShellLayoutMode(windowWidth: 1080).isWide)
    }

    func testSingleLineOverflowHidingLayoutDropsTrailingItemsThatDoNotFit() {
        let line = SingleLineOverflowHidingLayoutMetrics.line(
            maxWidth: 278,
            itemSpacing: 8,
            sizes: [
                CGSize(width: 120, height: 32),
                CGSize(width: 104, height: 32),
                CGSize(width: 96, height: 32)
            ]
        )

        XCTAssertEqual(line.elements.map(\.index), [0, 1])
        XCTAssertEqual(line.width, 232)
        XCTAssertEqual(line.height, 32)
    }

    func testForceBlankStartupIgnoresPersistedProjectsAndResetsStore() throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let persistedFlow = VibeWriteAppFlow(storageURL: storageURL)
        persistedFlow.openProject(
            WritingProject.entryShell(
                prompt: "写一个雨夜重逢的小说场景",
                mode: .collaboration,
                automationKey: "project.forceblank.demo"
            )
        )

        let blankFlow = VibeWriteAppFlow(storageURL: storageURL, forceBlankStartup: true)

        XCTAssertTrue(blankFlow.projects.isEmpty)
        XCTAssertNil(blankFlow.activeProjectID)
        XCTAssertTrue(blankFlow.recentDocumentEntries.isEmpty)

        let restoredFlow = VibeWriteAppFlow(storageURL: storageURL)
        XCTAssertTrue(restoredFlow.projects.isEmpty)
        XCTAssertTrue(restoredFlow.recentDocumentEntries.isEmpty)
    }

    func testDiscussionQuickStartStartsDiscussionProjectWithoutGeneratingDraft() async {
        let flow = VibeWriteAppFlow()

        await flow.startQuickDraft(prompt: "我想先聊清楚方向", mode: .discussion)

        XCTAssertEqual(flow.activeProject.mode, .discussion)
        XCTAssertTrue(flow.activeProject.documentText.isEmpty)
        XCTAssertEqual(flow.activeProject.prompt, "我想先聊清楚方向")
        XCTAssertEqual(flow.activeProject.mode.stageTitle, "起稿中")
        XCTAssertEqual(flow.activeProject.automationKey, "project.quickstart.discussion")
        XCTAssertEqual(flow.activeProject.conversation.filter { $0.role == .user }.count, 1)
    }

    func testDirectQuickStartCreatesRevisionHistoryAndCanUndoConsistently() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: StubWritingAIClient())

        await flow.startQuickDraft(
            prompt: "写一篇关于成年人孤独感的公众号文章",
            mode: .collaboration
        )

        XCTAssertEqual(flow.activeProject.mode, .collaboration)
        XCTAssertFalse(flow.activeProject.documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(flow.activeProject.revisionHistory.count, 1)

        let revision = flow.activeProject.revisionHistory.last
        XCTAssertEqual(revision?.action, .startDraft)
        XCTAssertEqual(revision?.patch.action, .startDraft)
        XCTAssertTrue(revision?.before.documentText.isEmpty ?? false)
        XCTAssertFalse(revision?.after.documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        let undone = flow.undoLastRevision()
        XCTAssertEqual(undone?.action, .startDraft)
        XCTAssertTrue(flow.activeProject.documentText.isEmpty)
        XCTAssertEqual(flow.activeProject.localSummary, revision?.before.localSummary)
        XCTAssertEqual(flow.activeProject.currentGoal, revision?.before.context.currentGoal)
        XCTAssertEqual(flow.activeProject.suggestionChips, revision?.before.suggestionChips)
    }

    func testStartDraftStreamsIncrementallyBeforeCompletion() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: StubWritingAIClient())
        flow.openProject(
            WritingProject.entryShell(
                prompt: "写一篇关于成年人孤独感的公众号文章",
                mode: .collaboration,
                automationKey: "project.stream.start"
            )
        )

        let initialText = flow.activeProject.documentText
        let task = Task { @MainActor in
            try await flow.performWritingAction(
                .startDraft,
                userMessage: "写一篇关于成年人孤独感的公众号文章",
                selectionText: nil
            )
        }

        let firstGrowthObserved = await waitUntil(timeout: 4) {
            flow.activeProject.documentText.count > initialText.count
        }
        XCTAssertTrue(firstGrowthObserved)

        let firstChunk = flow.activeProject.documentText
        XCTAssertFalse(firstChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(flow.isAIRequestInFlight)

        let secondGrowthObserved = await waitUntil(timeout: 4) {
            flow.activeProject.documentText.count > firstChunk.count
        }
        XCTAssertTrue(secondGrowthObserved)

        let finalText = flow.activeProject.documentText
        XCTAssertGreaterThan(finalText.count, firstChunk.count)

        try await task.value
        XCTAssertFalse(flow.isAIRequestInFlight)
        XCTAssertEqual(flow.activeProject.revisionHistory.last?.action, .startDraft)
    }

    func testContinueWritingStreamsIncrementallyBeforeCompletion() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: StubWritingAIClient())
        let project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!
        flow.openProject(project)

        let initialText = flow.activeProject.documentText
        let task = Task { @MainActor in
            try await flow.performWritingAction(
                .continueWriting,
                userMessage: nil,
                selectionText: nil
            )
        }

        let continueGrowthObserved = await waitUntil(timeout: 4) {
            flow.activeProject.documentText.count > initialText.count
        }
        XCTAssertTrue(continueGrowthObserved)

        let firstChunk = flow.activeProject.documentText
        XCTAssertTrue(firstChunk.hasPrefix(initialText))

        let continueGrowthObservedAgain = await waitUntil(timeout: 4) {
            flow.activeProject.documentText.count > firstChunk.count
        }
        XCTAssertTrue(continueGrowthObservedAgain)

        let finalText = flow.activeProject.documentText
        XCTAssertGreaterThan(finalText.count, firstChunk.count)
        XCTAssertTrue(finalText.hasPrefix(initialText))

        try await task.value
        XCTAssertEqual(flow.activeProject.revisionHistory.last?.action, .continueWriting)
    }

    func testMetadataPhaseCanRunWhileProsePreviewFinishes() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(
            storageURL: storageURL,
            aiClient: DelayedMetadataWritingAIClient()
        )
        flow.openProject(
            WritingProject.entryShell(
                prompt: "写一篇关于成年人孤独感的公众号文章",
                mode: .collaboration,
                automationKey: "project.metadata.concurrent"
            )
        )

        let task = Task { @MainActor in
            try await flow.performWritingAction(
                .startDraft,
                userMessage: "写一篇关于成年人孤独感的公众号文章",
                selectionText: nil
            )
        }

        let metadataPhaseObserved = await waitUntil(timeout: 4) {
            flow.isProseRequestInFlight && flow.isMetadataRequestInFlight
        }
        XCTAssertTrue(metadataPhaseObserved)
        XCTAssertFalse(flow.isAIRequestInFlight)
        XCTAssertFalse(flow.isBodyThinkingInFlight)
        XCTAssertTrue(flow.isProseRequestInFlight)
        XCTAssertTrue(flow.isMetadataRequestInFlight)
        XCTAssertFalse(flow.activeProject.documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(flow.activeProject.suggestionChips.isEmpty)

        try await task.value

        XCTAssertFalse(flow.isAIRequestInFlight)
        XCTAssertFalse(flow.isBodyThinkingInFlight)
        XCTAssertFalse(flow.isProseRequestInFlight)
        XCTAssertFalse(flow.isMetadataRequestInFlight)
        XCTAssertFalse(flow.activeProject.suggestionChips.isEmpty)
    }

    func testNewDraftCanStartAfterBodyFinishesEvenIfMetadataStillLoads() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(
            storageURL: storageURL,
            aiClient: OverlappingMetadataWritingAIClient()
        )
        flow.openProject(
            WritingProject.entryShell(
                prompt: "第一轮",
                mode: .collaboration,
                automationKey: "project.metadata.overlap"
            )
        )

        let firstTask = Task { @MainActor in
            try await flow.performWritingAction(
                .startDraft,
                userMessage: "第一轮",
                selectionText: nil
            )
        }

        let firstBodyFinished = await waitUntil(timeout: 4) {
            !flow.isAIRequestInFlight && flow.isMetadataRequestInFlight
        }
        XCTAssertTrue(firstBodyFinished)

        let secondTask = Task { @MainActor in
            try await flow.performWritingAction(
                .continueWriting,
                userMessage: nil,
                selectionText: nil
            )
        }

        try await secondTask.value
        try await firstTask.value

        XCTAssertEqual(flow.activeProject.revisionHistory.last?.action, .continueWriting)
        XCTAssertEqual(flow.activeProject.suggestionChips, ["继续写建议"])
    }

    func testEditAppliesPatchAtCompletionWhilePreservingPatchBoundaries() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: StubWritingAIClient())
        let project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!
        flow.openProject(project)
        let selection = project.documentText.components(separatedBy: "\n").first!

        guard let targetRange = project.documentText.range(of: selection) else {
            XCTFail("Expected the selected text to exist")
            return
        }

        let prefix = String(project.documentText[..<targetRange.lowerBound])
        let suffix = String(project.documentText[targetRange.upperBound...])

        let task = Task { @MainActor in
            try await flow.performWritingAction(
                .edit,
                userMessage: "请把这段改得更克制一点",
                selectionText: selection,
                selectionRange: WritingTextSelectionRange(NSRange(targetRange, in: project.documentText))
            )
        }

        try? await Task.sleep(nanoseconds: 90_000_000)
        let interimText = flow.activeProject.documentText

        try await task.value

        let finalText = flow.activeProject.documentText
        XCTAssertTrue(interimText == project.documentText || interimText == finalText)
        XCTAssertTrue(finalText.hasPrefix(prefix))
        XCTAssertTrue(finalText.hasSuffix(suffix))
        XCTAssertTrue(finalText.contains("留一点空白") || finalText.contains("不用说得太满"))
        XCTAssertEqual(flow.activeProject.revisionHistory.last?.action, .edit)
    }

    func testSavingAndReopeningDocumentRestoresMetadataStoreState() throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let initialFlow = VibeWriteAppFlow(storageURL: storageURL)
        let project = WritingProject.quickStart(
            prompt: "写一个雨夜重逢的小说场景",
            mode: .collaboration,
            automationKey: "project.persisted.demo"
        )
        initialFlow.openProject(project)

        var updatedProject = initialFlow.activeProject
        updatedProject.localSummary = "正在收紧雨夜重逢的第一段"
        updatedProject.globalSynopsis = "正在收紧雨夜重逢的第一段"
        updatedProject.currentGoal = "确认角色关系"
        updatedProject.recentDecisions = ["先说明场景", "再处理重逢"]
        for index in 1...25 {
            updatedProject.conversation.append(
                ConversationMessage(
                    role: .user,
                    text: "第 \(index) 轮用户补充",
                    timestamp: "用户 · 刚刚"
                )
            )
            updatedProject.conversation.append(
                ConversationMessage(
                    role: .assistant,
                    text: "第 \(index) 轮 AI 反馈",
                    timestamp: "AI · 刚刚"
                )
            )
        }
        initialFlow.activeProject = updatedProject

        let documentURL = storageURL.deletingPathExtension().appendingPathExtension("md")
        XCTAssertTrue(initialFlow.saveCurrentDocument(to: documentURL))

        let renderedText = try String(contentsOf: documentURL, encoding: .utf8)
        XCTAssertTrue(renderedText.hasPrefix(VibeWriteMarkdownDocument.markerStartToken))
        XCTAssertFalse(renderedText.contains("确认角色关系"))
        XCTAssertFalse(renderedText.contains("第 1 轮用户补充"))

        let reopenedFlow = VibeWriteAppFlow(storageURL: storageURL)
        XCTAssertTrue(reopenedFlow.openDocument(at: documentURL))

        XCTAssertEqual(reopenedFlow.activeProject.id, updatedProject.id)
        XCTAssertEqual(reopenedFlow.activeProject.title, updatedProject.title)
        XCTAssertEqual(reopenedFlow.activeProject.localSummary, updatedProject.localSummary)
        XCTAssertEqual(reopenedFlow.activeProject.globalSynopsis, updatedProject.globalSynopsis)
        XCTAssertEqual(reopenedFlow.activeProject.currentGoal, "确认角色关系")
        XCTAssertEqual(reopenedFlow.activeProject.recentDecisions, updatedProject.recentDecisions)
        XCTAssertEqual(reopenedFlow.activeProject.suggestionChips, updatedProject.suggestionChips)
        XCTAssertEqual(
            reopenedFlow.activeProject.conversation.count,
            VibeWriteDocumentMetadataPolicy.conversationMessageLimit
        )
        XCTAssertEqual(reopenedFlow.activeProject.conversation.first?.text, "第 6 轮用户补充")
        XCTAssertTrue(reopenedFlow.activeProject.documentText.isEmpty)
        XCTAssertTrue(reopenedFlow.recentDocumentEntries.contains(where: { $0.url == documentURL }))
    }

    func testResetLocalDataClearsProjectsAndPersistsBlankStore() throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL)
        let project = WritingProject.entryShell(
            prompt: "写一个雨夜重逢的小说场景",
            mode: .collaboration,
            automationKey: "project.reset.demo"
        )
        flow.openProject(project)

        flow.resetLocalData()

        XCTAssertTrue(flow.projects.isEmpty)
        XCTAssertNil(flow.activeProjectID)
        XCTAssertTrue(flow.recentDocumentEntries.isEmpty)
        XCTAssertNil(flow.currentDocumentURL)

        let restoredFlow = VibeWriteAppFlow(storageURL: storageURL)
        XCTAssertTrue(restoredFlow.projects.isEmpty)
        XCTAssertTrue(restoredFlow.recentDocumentEntries.isEmpty)
    }

    func testOpenDocumentFallsBackToBodyOnlyWhenMetadataStoreIsMalformed() throws {
        let storageURL = try makeTempStorageURL()
        let metadataURL = metadataStorageURL(for: storageURL)
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        try createParentDirectoryIfNeeded(for: metadataURL)
        try """
        { this is not valid json
        """.write(to: metadataURL, atomically: true, encoding: .utf8)

        let documentID = UUID()
        let rawText = VibeWriteMarkdownDocument(
            identityMarker: VibeWriteDocumentIdentityMarker(
                schemaVersion: VibeWriteDocumentMetadataPolicy.schemaVersion,
                documentID: documentID
            ),
            body: """
            林校第一次注意到苏迟，是在图书馆三楼靠窗的位置。
            """
        ).renderedText()

        let documentURL = storageURL.deletingPathExtension().appendingPathExtension("md")
        try rawText.write(to: documentURL, atomically: true, encoding: .utf8)

        let flow = VibeWriteAppFlow(storageURL: storageURL)
        XCTAssertTrue(flow.openDocument(at: documentURL))

        XCTAssertEqual(flow.activeProject.id, documentID)
        XCTAssertEqual(flow.activeProject.title, documentURL.deletingPathExtension().lastPathComponent)
        XCTAssertTrue(flow.activeProject.documentText.contains("林校第一次注意到苏迟"))
        XCTAssertEqual(flow.activeProject.currentGoal, "继续当前正文")
        XCTAssertTrue(flow.activeProject.conversation.isEmpty)
        XCTAssertEqual(flow.activeProject.suggestionChips, ["继续写", "编辑这段", "补一段"])
    }

    func testDocumentIdentityPrefersXattrOverHiddenMarker() throws {
        let storageURL = try makeTempStorageURL()
        let metadataURL = metadataStorageURL(for: storageURL)
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let bodyMarkerID = UUID()
        let xattrID = UUID()
        let bodyText = "正文内容只会出现在文件正文里。"
        let documentURL = storageURL.deletingPathExtension().appendingPathExtension("md")
        let markerDocument = VibeWriteMarkdownDocument(
            identityMarker: VibeWriteDocumentIdentityMarker(
                schemaVersion: VibeWriteDocumentMetadataPolicy.schemaVersion,
                documentID: bodyMarkerID
            ),
            body: bodyText
        )
        try markerDocument.renderedText().write(to: documentURL, atomically: true, encoding: .utf8)

        let identityStore = VibeWriteDocumentIdentityStore()
        XCTAssertTrue(identityStore.writeDocumentID(
            VibeWriteDocumentIdentityMarker(
                schemaVersion: VibeWriteDocumentMetadataPolicy.schemaVersion,
                documentID: xattrID
            ),
            to: documentURL
        ))

        let metadataStore = VibeWriteDocumentMetadataStore(storageURL: metadataURL)
        let xattrProject = WritingProject(
            id: xattrID,
            automationKey: "project.xattr.demo",
            title: "XATTR 版本",
            prompt: "写一个雨夜重逢的小说场景",
            mode: .collaboration,
            localSummary: "XATTR 记录的最新摘要",
            globalSynopsis: "XATTR 记录的模型摘要",
            context: ProjectContext(
                intentSummary: "围绕 xattr 记录恢复协作状态。",
                styleConstraints: ["克制", "平静"],
                currentGoal: "继续推进 xattr 版本",
                recentDecisions: ["xattr 优先"],
                workingMemory: ["测试 xattr 优先级"],
                nextFocus: "继续下一段"
            ),
            conversation: [
                ConversationMessage(role: .user, text: "先看 xattr 能不能优先", timestamp: "用户 · 刚刚"),
                ConversationMessage(role: .assistant, text: "xattr 应该优先于正文隐藏标记。", timestamp: "AI · 刚刚")
            ],
            documentText: bodyText,
            suggestionChips: ["继续写", "编辑这段"],
            revisionHistory: [],
            updatedAt: .now
        )
        metadataStore.save(project: xattrProject)

        let flow = VibeWriteAppFlow(storageURL: storageURL)
        XCTAssertTrue(flow.openDocument(at: documentURL))

        XCTAssertEqual(flow.activeProject.id, xattrID)
        XCTAssertEqual(flow.activeProject.title, "XATTR 版本")
        XCTAssertEqual(flow.activeProject.currentGoal, "继续推进 xattr 版本")
        XCTAssertEqual(flow.activeProject.documentText, bodyText)
        XCTAssertEqual(flow.activeProject.conversation.count, 2)
        XCTAssertEqual(flow.activeProject.globalSynopsis, "XATTR 记录的模型摘要")
    }

    func testMockEngineRevisesSelectedAndWholeDocumentText() {
        let draft = MockWritingEngine.firstDraft(for: "写一篇关于成年人孤独感的公众号文章")
        let draftParagraph = draft.components(separatedBy: "\n\n").first!
        let draftParagraphRange = draft.range(of: draftParagraph)!
        let selectionRange = WritingTextSelectionRange(NSRange(draftParagraphRange, in: draft))

        let continued = MockWritingEngine.revisedText(
            for: draft,
            action: .continueWriting,
            variant: .standard
        )
        let revisedSelection = MockWritingEngine.revisedText(
            for: draft,
            selectedRange: selectionRange,
            action: .edit,
            variant: .standard
        )
        let revisedNoSelection = MockWritingEngine.revisedText(
            for: draft,
            action: .edit,
            variant: .standard
        )

        XCTAssertNotEqual(draft, continued)
        XCTAssertNotEqual(draft, revisedSelection)
        XCTAssertEqual(draft, revisedNoSelection)
        XCTAssertTrue(revisedSelection.contains("留一点空白") || revisedSelection.contains("不用说得太满"))
        XCTAssertTrue(continued.contains("接下来") || continued.contains("继续"))
    }

    func testFailedAIRequestDoesNotMutateActiveProjectState() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: ThrowingWritingAIClient())
        let project = WritingProject.quickStart(
            prompt: "把这段日记整理成更克制的随笔",
            mode: .collaboration,
            automationKey: "project.failure.demo"
        )
        flow.openProject(project)

        let before = flow.activeProject

        do {
            try await flow.performWritingAction(
                .continueWriting,
                userMessage: "请把这段改得更克制一点",
                selectionText: nil
            )
            XCTFail("Expected the AI request to fail")
        } catch {
            XCTAssertNotNil(flow.aiErrorMessage)
        }

        XCTAssertEqual(flow.activeProject.documentText, before.documentText)
        XCTAssertEqual(flow.activeProject.conversation.count, before.conversation.count)
        XCTAssertEqual(Int(flow.activeProject.updatedAt.timeIntervalSince1970), Int(before.updatedAt.timeIntervalSince1970))
        XCTAssertNil(flow.activeEditLock)
    }

    func testContinueWritingProducesWholeDocumentRevision() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: StubWritingAIClient())
        let project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!
        let originalDocumentText = project.documentText
        flow.openProject(project)

        try await flow.performWritingAction(.continueWriting, userMessage: nil, selectionText: nil)

        XCTAssertEqual(flow.activeProject.revisionHistory.last?.action, .continueWriting)
        XCTAssertEqual(flow.activeProject.revisionHistory.last?.patch.action, .continueWriting)
        XCTAssertTrue(flow.activeProject.documentText.contains("推进") || flow.activeProject.documentText.contains("补一段"))
        XCTAssertTrue(flow.activeProject.documentText.hasPrefix(originalDocumentText))
        XCTAssertGreaterThan(flow.activeProject.documentText.count, originalDocumentText.count)
    }

    func testUndoLastRevisionRestoresPreviousLinearPatchState() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: StubWritingAIClient())
        let project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!
        let originalDocumentText = project.documentText
        flow.openProject(project)

        try await flow.performWritingAction(.continueWriting, userMessage: nil, selectionText: nil)

        XCTAssertEqual(flow.activeProject.revisionHistory.last?.action, .continueWriting)
        XCTAssertGreaterThan(flow.activeProject.documentText.count, originalDocumentText.count)

        let undone = flow.undoLastRevision()
        XCTAssertEqual(undone?.action, .continueWriting)
        XCTAssertEqual(flow.activeProject.documentText, originalDocumentText)
        XCTAssertTrue(flow.activeProject.revisionHistory.isEmpty)

        try await flow.performWritingAction(.continueWriting, userMessage: nil, selectionText: nil)
        XCTAssertEqual(flow.activeProject.revisionHistory.last?.action, .continueWriting)
        XCTAssertGreaterThan(flow.activeProject.documentText.count, originalDocumentText.count)
    }

    func testEditUsesSelectionAsPatchTarget() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: StubWritingAIClient())
        let project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!
        flow.openProject(project)
        let selectedText = project.documentText.components(separatedBy: "\n").first!
        let selectedRange = WritingTextSelectionRange(NSRange(project.documentText.range(of: selectedText)!, in: project.documentText))

        try await flow.performWritingAction(.edit, userMessage: nil, selectionText: selectedText, selectionRange: selectedRange)

        XCTAssertEqual(flow.activeProject.revisionHistory.last?.action, .edit)
        XCTAssertEqual(flow.activeProject.revisionHistory.last?.patch.action, .edit)
        XCTAssertEqual(flow.activeProject.revisionHistory.last?.lockedSelectionText, selectedText)
        XCTAssertTrue(flow.activeProject.documentText.contains("留一点空白") || flow.activeProject.documentText.contains("不用说得太满"))
    }

    func testPatchApplicationKeepsUnselectedPrefixAndSuffixIntact() throws {
        let before = WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot
        let targetText = before.documentText.components(separatedBy: "\n").first!
        var afterDocument = before.documentText
        let replacement = targetText + " 这里不用说得太满，留白会更好。"
        guard let targetRange = afterDocument.range(of: targetText) else {
            XCTFail("Expected the target selection to exist")
            return
        }
        let prefix = String(before.documentText[..<targetRange.lowerBound])
        let suffix = String(before.documentText[targetRange.upperBound...])
        afterDocument.replaceSubrange(targetRange, with: replacement)
        let after = before.withDocumentText(afterDocument)

        let patch = try WritingEditPatch.build(
            action: .edit,
            before: before,
            after: after,
            selectionRange: WritingTextSelectionRange(NSRange(targetRange, in: before.documentText)),
            userMessage: "请把这段改得更克制一点"
        )

        let updated = try patch.apply(
            to: before.documentText,
            lock: WritingEditLock(
                action: .edit,
                lockedSelectionText: targetText,
                lockedDocumentText: before.documentText
            )
        )

        XCTAssertTrue(updated.hasPrefix(prefix))
        XCTAssertTrue(updated.hasSuffix(suffix))
        XCTAssertTrue(updated.contains("留白会更好"))
        XCTAssertTrue(updated.contains(targetText))
        XCTAssertEqual(updated, afterDocument)
    }

    func testEditPatchExposesReplacementHighlightRangeForLocalFlash() throws {
        let before = WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot
        let targetText = before.documentText.components(separatedBy: "\n").first!
        var afterDocument = before.documentText
        let replacement = targetText + " 这里不用说得太满，留白会更好。"
        guard let targetRange = afterDocument.range(of: targetText) else {
            XCTFail("Expected the target selection to exist")
            return
        }
        afterDocument.replaceSubrange(targetRange, with: replacement)
        let after = before.withDocumentText(afterDocument)

        let patch = try WritingEditPatch.build(
            action: .edit,
            before: before,
            after: after,
            selectionRange: WritingTextSelectionRange(NSRange(targetRange, in: before.documentText)),
            userMessage: "请把这段改得更克制一点"
        )

        XCTAssertEqual(
            patch.replacementHighlightRange?.nsRange,
            NSRange(
                location: NSRange(targetRange, in: before.documentText).location,
                length: replacement.utf16.count
            )
        )
    }

    func testPatchApplicationRejectsLockMismatchWithoutMutatingDocument() throws {
        let before = WorkspaceFixtures.bootstrapProjects(now: Date()).first!.aiSnapshot
        let targetText = before.documentText.components(separatedBy: "\n").first!
        var afterDocument = before.documentText
        let replacement = targetText + " 这里不用说得太满，留白会更好。"
        guard let targetRange = afterDocument.range(of: targetText) else {
            XCTFail("Expected the target selection to exist")
            return
        }
        let prefix = String(before.documentText[..<targetRange.lowerBound])
        let suffix = String(before.documentText[targetRange.upperBound...])
        afterDocument.replaceSubrange(targetRange, with: replacement)
        let after = before.withDocumentText(afterDocument)

        let patch = try WritingEditPatch.build(
            action: .edit,
            before: before,
            after: after,
            selectionRange: WritingTextSelectionRange(NSRange(targetRange, in: before.documentText)),
            userMessage: nil
        )

        let mismatchedLock = WritingEditLock(
            action: .edit,
            lockedSelectionText: targetText,
            lockedDocumentText: "完全不同的正文"
        )

        do {
            _ = try patch.apply(to: before.documentText, lock: mismatchedLock)
            XCTFail("Expected the patch to reject the mismatched lock")
        } catch let error as WritingEditPatchError {
            XCTAssertEqual(error, .lockMismatch)
        }

        XCTAssertTrue(before.documentText.hasPrefix(prefix))
        XCTAssertTrue(before.documentText.hasSuffix(suffix))
    }

    func testContinueWritingRejectsNonAppendingResponses() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: NonLocalWritingAIClient())
        let project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!
        flow.openProject(project)

        let before = flow.activeProject

        do {
            try await flow.performWritingAction(
                .continueWriting,
                userMessage: "继续往下写",
                selectionText: nil
            )
            XCTFail("Expected the flow to reject the full-document rewrite")
        } catch {
            XCTAssertEqual(flow.activeProject.documentText, before.documentText)
            XCTAssertEqual(flow.activeProject.revisionHistory.count, before.revisionHistory.count)
            XCTAssertNil(flow.activeEditLock)
        }
    }

    func testEditRejectsNonLocalRewriteResponses() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: NonLocalWritingAIClient())
        let project = WorkspaceFixtures.bootstrapProjects(now: Date()).first!
        flow.openProject(project)
        let selectedText = project.documentText.components(separatedBy: "\n").first!
        let selectedRange = WritingTextSelectionRange(NSRange(project.documentText.range(of: selectedText)!, in: project.documentText))

        let before = flow.activeProject

        do {
            try await flow.performWritingAction(
                .edit,
                userMessage: "把这段改得更克制一点",
                selectionText: selectedText,
                selectionRange: selectedRange
            )
            XCTFail("Expected the flow to reject the non-local patch")
        } catch {
            XCTAssertEqual(flow.activeProject.documentText, before.documentText)
            XCTAssertEqual(flow.activeProject.revisionHistory.count, before.revisionHistory.count)
            XCTAssertNil(flow.activeEditLock)
        }
    }

    func testStartDraftKeepsMatchingPromptInRequestWithoutDuplicatingConversation() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let recorder = RequestRecorder()
        let flow = VibeWriteAppFlow(
            storageURL: storageURL,
            aiClient: RecordingWritingAIClient(recorder: recorder)
        )
        let prompt = "写一篇关于成年人孤独感的公众号文章"
        let project = WritingProject.quickStart(
            prompt: prompt,
            mode: .discussion,
            automationKey: "project.startdraft.demo"
        )
        flow.openProject(project)

        try await flow.performWritingAction(
            .startDraft,
            userMessage: prompt,
            selectionText: nil
        )

        let requests = await recorder.allRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.kind, .prose)
        XCTAssertEqual(requests.last?.kind, .metadata)
        XCTAssertEqual(requests.first?.userMessage, prompt)
        XCTAssertEqual(requests.last?.userMessage, prompt)
        XCTAssertTrue(requests.last?.project.documentText.contains("成年人真正感到孤独的时候") ?? false)

        let matchingUserMessages = flow.activeProject.conversation.filter {
            $0.role == .user && $0.text == prompt
        }
        XCTAssertEqual(matchingUserMessages.count, 1)
    }

    func testMetadataFailureLeavesAssistantSuggestionsEmpty() async throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL, aiClient: MetadataFailingWritingAIClient())
        let project = WritingProject.quickStart(
            prompt: "写一篇关于成年人孤独感的公众号文章",
            mode: .collaboration,
            automationKey: "project.metadata.failure"
        )
        flow.openProject(project)

        try await flow.performWritingAction(
            .startDraft,
            userMessage: "写一篇关于成年人孤独感的公众号文章",
            selectionText: nil
        )

        XCTAssertFalse(flow.activeProject.documentText.isEmpty)
        XCTAssertTrue(flow.activeProject.suggestionChips.isEmpty)
        XCTAssertTrue(flow.activeProject.nextFocus.isEmpty)
        XCTAssertNil(flow.aiErrorMessage)
    }

    func testRenameAndDeleteActiveProjectUseLocalFlowActions() throws {
        let storageURL = try makeTempStorageURL()
        defer {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }

        let flow = VibeWriteAppFlow(storageURL: storageURL)
        let project = WritingProject.entryShell(
            prompt: "写一个雨夜重逢的小说场景",
            mode: .collaboration,
            automationKey: "project.rename.delete"
        )
        flow.openProject(project)

        flow.renameActiveProject(to: "雨夜重逢 · 重命名")
        XCTAssertEqual(flow.activeProject.title, "雨夜重逢 · 重命名")
        XCTAssertTrue(flow.recentProjects.contains(where: { $0.title == "雨夜重逢 · 重命名" }))

        flow.deleteActiveProject()
        XCTAssertFalse(flow.recentProjects.contains(where: { $0.id == project.id }))
    }

    private func makeTempStorageURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("local-project-store.json")
    }

    private func metadataStorageURL(for storageURL: URL) -> URL {
        storageURL
            .deletingLastPathComponent()
            .appendingPathComponent("document-collaboration-store.json")
    }

    private func createParentDirectoryIfNeeded(for url: URL) throws {
        let directory = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) {
            return
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        pollIntervalNanoseconds: UInt64 = 25_000_000,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        return condition()
    }
}

private extension WritingProjectSnapshot {
    func withDocumentText(_ documentText: String) -> WritingProjectSnapshot {
        var copy = self
        copy.documentText = documentText
        return copy
    }
}

private actor RequestRecorder {
    private var requests: [WritingAIRequest] = []

    func record(_ request: WritingAIRequest) {
        requests.append(request)
    }

    func lastRequest() -> WritingAIRequest? {
        requests.last
    }

    func allRequests() -> [WritingAIRequest] {
        requests
    }
}

private struct RecordingWritingAIClient: WritingAIClient {
    let recorder: RequestRecorder

    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        await recorder.record(request)
        if request.kind == .metadata {
            return WritingProjectResponseBuilder.response(
                for: request,
                documentText: request.project.documentText,
                metadata: MockWritingEngine.completionMetadata(for: request)
            )
        }

        return WritingProjectResponseBuilder.response(for: request)
    }
}

private struct ThrowingWritingAIClient: WritingAIClient {
    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        throw WritingAIClientError.requestFailed("AI request failed for test")
    }
}

private struct NonLocalWritingAIClient: WritingAIClient {
    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        let snapshot = request.project
        return WritingAIResponse(
            assistantMessage: "我已经重新写了一版。",
            documentText: "完全不同的正文",
            localSummary: "整篇重写",
            globalSynopsis: "整篇重写总览",
            intentSummary: snapshot.context.intentSummary,
            styleConstraints: snapshot.context.styleConstraints,
            currentGoal: snapshot.context.currentGoal,
            recentDecisions: snapshot.context.recentDecisions,
            workingMemory: snapshot.context.workingMemory,
            nextFocus: snapshot.context.nextFocus,
            suggestionChips: snapshot.suggestionChips,
            mode: snapshot.mode
        )
    }
}

private struct MetadataFailingWritingAIClient: WritingAIClient {
    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        if request.kind == .metadata {
            throw WritingAIClientError.requestFailed("metadata request failed")
        }

        return WritingProjectResponseBuilder.response(
            for: request,
            documentText: MockWritingEngine.streamedDocumentText(for: request)
        )
    }
}

private struct DelayedMetadataWritingAIClient: WritingAIClient {
    private let streamClient = StubWritingAIClient()
    private let metadataDelayNanoseconds: UInt64 = 250_000_000

    func streamResponse(for request: WritingAIRequest) -> AsyncThrowingStream<WritingAIStreamEvent, Error> {
        streamClient.streamResponse(for: request)
    }

    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        if request.kind == .metadata {
            try await Task.sleep(nanoseconds: metadataDelayNanoseconds)
            return WritingProjectResponseBuilder.response(
                for: request,
                documentText: request.project.documentText,
                metadata: MockWritingEngine.completionMetadata(for: request)
            )
        }

        return WritingProjectResponseBuilder.response(
            for: request,
            documentText: MockWritingEngine.streamedDocumentText(for: request)
        )
    }
}

private struct OverlappingMetadataWritingAIClient: WritingAIClient {
    private let streamClient = StubWritingAIClient()
    private let firstMetadataDelayNanoseconds: UInt64 = 400_000_000

    func streamResponse(for request: WritingAIRequest) -> AsyncThrowingStream<WritingAIStreamEvent, Error> {
        streamClient.streamResponse(for: request)
    }

    func generateResponse(for request: WritingAIRequest) async throws -> WritingAIResponse {
        if request.kind == .metadata {
            if request.action == .startDraft {
                try await Task.sleep(nanoseconds: firstMetadataDelayNanoseconds)
                return WritingProjectResponseBuilder.response(
                    for: request,
                    documentText: request.project.documentText,
                    metadata: WritingAICompletionMetadata(
                        localSummary: "第一轮摘要",
                        globalSynopsis: "第一轮总览",
                        nextFocus: "第一轮下一步",
                        suggestionChips: ["第一轮建议"]
                    )
                )
            }

            return WritingProjectResponseBuilder.response(
                for: request,
                documentText: request.project.documentText,
                metadata: WritingAICompletionMetadata(
                    localSummary: "继续写摘要",
                    globalSynopsis: "继续写总览",
                    nextFocus: "继续写下一步",
                    suggestionChips: ["继续写建议"]
                )
            )
        }

        return WritingProjectResponseBuilder.response(
            for: request,
            documentText: MockWritingEngine.streamedDocumentText(for: request)
        )
    }
}
