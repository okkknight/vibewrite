import AppKit
import Foundation
import SwiftUI

struct WritingProjectView: View {
    @ObservedObject var flow: VibeWriteAppFlow
    let shellLayoutMode: ProjectShellLayoutMode
    @Binding var appearanceMode: VibeAppearanceMode

    @State private var messageDraft = ""
    @State private var selectedText: String?
    @State private var selectedTextRange: WritingTextSelectionRange?
    @State private var selectionPopoverOrigin: CGPoint?
    @State private var showComparison = false
    @State private var showAssistantLayer = false
    @State private var showHistoryLayer = false
    @State private var isComposerLocked = false
    @FocusState private var messageFieldFocused: Bool

    private var project: WritingProject { flow.activeProject }
    private var projectBinding: Binding<WritingProject> { flow.activeProjectBinding }
    private var currentRevision: WritingProjectRevision? { project.revisionHistory.last }
    private var assistantDrawerWidth: CGFloat { shellLayoutMode.isCompact ? 300 : 280 }
    private var historyDrawerWidth: CGFloat { shellLayoutMode.isCompact ? 372 : 344 }
    private var shouldShowHistorySidebar: Bool { false }
    /// 与右侧透明占位同宽，标题在中间 `frame(maxWidth: .infinity)` 里相对**整行**居中，不会被左侧按钮顶偏。
    private var projectHeaderSideChromeWidth: CGFloat {
        shouldShowHistorySidebar ? 80 : 44
    }
    private var writingContentMaxWidth: CGFloat { 900 }
    private var writingReadableTextWidth: CGFloat { 828 }
    private var writingContentHorizontalPadding: CGFloat { shellLayoutMode.isCompact ? 16 : 30 }

    init(
        flow: VibeWriteAppFlow,
        shellLayoutMode: ProjectShellLayoutMode,
        appearanceMode: Binding<VibeAppearanceMode>
    ) {
        self.flow = flow
        self.shellLayoutMode = shellLayoutMode
        _appearanceMode = appearanceMode
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.vibeCanvas
                .ignoresSafeArea()

            projectWorkspace
        }
        .onChange(of: project.id) { _, _ in
            selectedText = nil
            selectedTextRange = nil
            selectionPopoverOrigin = nil
            showComparison = false
            showAssistantLayer = false
            showHistoryLayer = false
            isComposerLocked = false
            messageDraft = ""
            messageFieldFocused = false
        }
        .onChange(of: showAssistantLayer) { _, newValue in
            VibeWriteLog.launch.info("assistant layer visibility changed isVisible=\(newValue, privacy: .public)")
        }
        .onChange(of: showHistoryLayer) { _, newValue in
            VibeWriteLog.launch.info("history layer visibility changed isVisible=\(newValue, privacy: .public)")
        }
        .onChange(of: selectedText) { _, _ in
            logSelectionOverlayState(trigger: "selectedText changed")
        }
        .onChange(of: selectionPopoverOrigin) { _, _ in
            logSelectionOverlayState(trigger: "selectionPopoverOrigin changed")
        }
        .onAppear {
            logSelectionOverlayState(trigger: "writing project appeared")
        }
    }

    private var projectWorkspace: some View {
        wideWorkspace
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier(VibeWriteAutomationID.projectPaperShell)
    }

    private var wideWorkspace: some View {
        HStack(alignment: .top, spacing: 12) {
            if showAssistantLayer {
                wideAssistantRail
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            widePageStage
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if shouldShowHistorySidebar && showHistoryLayer {
                wideHistoryRail
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.22), value: showAssistantLayer)
        .animation(.snappy(duration: 0.22), value: showHistoryLayer)
    }

    private var widePageStage: some View {
        VStack(spacing: 0) {
            projectHeader
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 8)

            writingBodyPane(topPadding: 26, bottomPadding: 18)

            writingContentColumn {
                composerBar
                    .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var wideAssistantRail: some View {
        assistantLayer
            .frame(width: assistantDrawerWidth)
            .padding(.vertical, 10)
            .padding(.leading, 10)
    }

    private var wideHistoryRail: some View {
        historyLayer
            .frame(width: historyDrawerWidth)
            .padding(.vertical, 10)
            .padding(.trailing, 10)
    }

    private var centerStage: some View {
        VStack(spacing: 0) {
            projectHeader
                .padding(.horizontal, shellLayoutMode.isCompact ? 18 : 22)
                .padding(.top, shellLayoutMode.isCompact ? 10 : 10)
                .padding(.bottom, shellLayoutMode.isCompact ? 8 : 8)

            writingBodyPane(
                topPadding: shellLayoutMode.isCompact ? 22 : 28,
                bottomPadding: 18
            )

            writingContentColumn {
                composerBar
                    .padding(.vertical, shellLayoutMode.isCompact ? 14 : 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: shellLayoutMode.isCompact ? .infinity : 872, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: shellLayoutMode.isCompact ? 28 : 34, style: .continuous)
                .fill(Color.vibeCanvasRaised.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: shellLayoutMode.isCompact ? 28 : 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.04),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.softLight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: shellLayoutMode.isCompact ? 28 : 34, style: .continuous)
                        .strokeBorder(Color.vibeCanvasStroke.opacity(0.72), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.26), radius: 22, x: 0, y: 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: shellLayoutMode.isCompact ? 28 : 34, style: .continuous))
    }

    private var projectHeader: some View {
        ZStack(alignment: .center) {
            VStack(spacing: 4) {
                TextField("未命名写作", text: projectBinding.title)
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .foregroundStyle(Color.vibeCanvasInk)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(VibeWriteAutomationID.projectTitle)
                    .textFieldStyle(.plain)

                statusSubtitle
            }
            .frame(maxWidth: 360, alignment: .center)
            // 与按钮占位同宽，标题在整行内居中且不与左侧按钮抢排版宽度
            .padding(.horizontal, projectHeaderSideChromeWidth)

            HStack {
                HStack(spacing: 8) {
                    ProjectSidebarToggleButton(
                        title: "AI 侧栏",
                        systemImage: "sidebar.left",
                        isOn: showAssistantLayer,
                        accessibilityIdentifier: VibeWriteAutomationID.projectAssistantRailToggle
                    ) {
                        toggleAssistantLayer()
                    }

                    if shouldShowHistorySidebar {
                        ProjectSidebarToggleButton(
                            title: "历史栏",
                            systemImage: "sidebar.right",
                            isOn: showHistoryLayer,
                            accessibilityIdentifier: VibeWriteAutomationID.projectHistoryRailToggle
                        ) {
                            toggleHistoryLayer()
                        }
                    }
                }
                Spacer(minLength: 0)

                ProjectSidebarToggleButton(
                    title: appearanceMode.toggleTitle,
                    systemImage: appearanceMode.toggleSymbolName,
                    isOn: appearanceMode == .day
                ) {
                    toggleAppearanceMode()
                }
            }
        }
        .padding(.horizontal, shellLayoutMode.isCompact ? 12 : 16)
        .padding(.vertical, 2)
    }

    private var statusSubtitle: some View {
        HStack(spacing: 4) {
            Text(projectStatusSubtitleText)
                .font(.system(size: 11.5, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInkSoft)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)

            if flow.isAIRequestInFlight {
                ThinkingDots()
                    .font(.system(size: 11.5, weight: .medium, design: .default))
                    .foregroundStyle(Color.vibeCanvasInkSoft)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

    private var projectStatusSubtitleText: String {
        let trimmedDocumentText = project.documentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDocumentText.isEmpty {
            return project.mode.stageDescription
        }

        let trimmedSummary = project.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSummary.isEmpty ? project.mode.stageDescription : trimmedSummary
    }

    private func editorBody(minimumHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .topLeading) {
                SelectableTextEditor(
                    text: projectBinding.documentText,
                    selectedText: $selectedText,
                    selectedTextRange: $selectedTextRange,
                    selectionPopoverOrigin: $selectionPopoverOrigin,
                    isEditable: !flow.isAIRequestInFlight && flow.activeEditLock == nil,
                    accessibilityIdentifier: VibeWriteAutomationID.projectBodyEditor,
                    shouldAutoScrollToDocumentEnd: flow.isAIRequestInFlight,
                    readableContentWidth: writingReadableTextWidth,
                    textFont: NSFont.systemFont(ofSize: 16, weight: .regular),
                    textColor: NSColor.vibeCanvasInk,
                    insertionPointColor: NSColor.vibeAccent,
                    selectedTextBackgroundColor: NSColor.vibeAccent.withAlphaComponent(0.30)
                )
                .id(project.id)
                .frame(
                    maxWidth: .infinity,
                    minHeight: minimumHeight,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .onChange(of: project.documentText) { _, newValue in
                    if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        showComparison = false
                    }
                }

                if let selectedText = normalizedSelectedText,
                   let selectionPopoverOrigin {
                    SelectionPopover(
                        selectedText: selectedText,
                        onEditSelection: {
                            applyRevision(
                                .edit,
                                selectionText: selectedText,
                                selectionRange: selectedTextRange,
                                userMessage: draftInstructionText(),
                                clearDraftOnSuccess: true
                            )
                        }
                    )
                    .offset(x: selectionPopoverOrigin.x, y: selectionPopoverOrigin.y)
                    .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let errorMessage = flow.aiErrorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5, weight: .medium, design: .default))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func writingBodyPane(topPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        GeometryReader { proxy in
            let availableHeight = max(
                proxy.size.height - topPadding - bottomPadding,
                shellLayoutMode.isCompact ? 360 : 480
            )

            writingContentColumn {
                VStack(alignment: .leading, spacing: 18) {
                    editorBody(minimumHeight: availableHeight)
                }
            }
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var assistantLayer: some View {
        ProjectAISidebarView(
            project: project,
            isExpanded: true,
            presentation: shellLayoutMode.isCompact ? .drawer : .column,
            isRequestInFlight: flow.isAIRequestInFlight,
            errorMessage: flow.aiErrorMessage,
            accessibilityIdentifier: VibeWriteAutomationID.projectAssistantRailShell,
            onToggle: toggleAssistantLayer,
            onSuggestionTap: handleSuggestionTap
        )
    }

    private var historyLayer: some View {
        ProjectHistoryDrawerView(
            project: project,
            isExpanded: true,
            presentation: shellLayoutMode.isCompact ? .drawer : .column,
            isComparisonVisible: showComparison,
            isRequestInFlight: flow.isAIRequestInFlight,
            accessibilityIdentifier: VibeWriteAutomationID.projectHistoryRailShell,
            onToggle: toggleHistoryLayer,
            onUndo: undoLastChange,
            onRetry: retryLastChange,
            onToggleComparison: toggleComparison
        )
    }

    private func assistantDrawerOverlay(isCompact: Bool) -> some View {
        assistantLayer
            .frame(width: assistantDrawerWidth)
            .padding(.vertical, isCompact ? 12 : 10)
            .transition(.move(edge: .leading).combined(with: .opacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, isCompact ? 12 : 10)
            .padding(.top, isCompact ? 12 : 10)
    }

    private func historyDrawerOverlay(isCompact: Bool) -> some View {
        historyLayer
            .frame(width: historyDrawerWidth)
            .padding(.vertical, isCompact ? 12 : 10)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, isCompact ? 12 : 10)
            .padding(.top, isCompact ? 12 : 10)
    }

    private var normalizedSelectedText: String? {
        let trimmed = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func logSelectionOverlayState(trigger: String) {
        let selectionPreview = normalizedSelectedText?.vibewriteLogPreview(maxLength: 60) ?? "nil"
        let originPreview = selectionPopoverOrigin.map {
            String(format: "(%.1f, %.1f)", Double($0.x), Double($0.y))
        } ?? "nil"
        let renderable = normalizedSelectedText != nil && selectionPopoverOrigin != nil
        let message = "selection overlay \(trigger) selection=\(selectionPreview) origin=\(originPreview) renderable=\(renderable)"
        VibeWriteDebugTrace.append(message)
        VibeWriteLog.launch.info("\(message, privacy: .public)")
    }

    private var primaryAction: WritingAIAction {
        if normalizedSelectedText != nil {
            return .edit
        }

        if project.documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .startDraft
        }

        return .continueWriting
    }

    private var primaryActionTitle: String {
        switch primaryAction {
        case .startDraft:
            return "生成开场"
        case .continueWriting:
            return "继续写"
        case .edit:
            return "润色此处"
        }
    }

    private var shouldShowAssistantSuggestions: Bool {
        !project.documentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var messageFieldPlaceholder: String {
        switch primaryAction {
        case .startDraft:
            return "写下一个想法，点亮一个世界"
        case .continueWriting:
            return "想继续往哪儿写，可以补一句"
        case .edit:
            return "听听你的修改建议"
        }
    }

    private var composerBar: some View {
        ProjectComposerBar(
            messageDraft: $messageDraft,
            primaryActionTitle: primaryActionTitle,
            messageFieldPlaceholder: messageFieldPlaceholder,
            showsAssistantSuggestions: shouldShowAssistantSuggestions,
            assistantNextFocus: project.nextFocus,
            assistantSuggestionChips: project.suggestionChips,
            isComposerLocked: isComposerLocked,
            isRequestInFlight: flow.isAIRequestInFlight,
            messageFieldFocused: $messageFieldFocused,
            accessibilityIdentifier: VibeWriteAutomationID.projectComposerBar,
            messageInputIdentifier: VibeWriteAutomationID.projectMessageInput,
            sendButtonIdentifier: VibeWriteAutomationID.projectSendButton,
            onSubmit: handlePrimaryAction,
            onAssistantSuggestionTap: handleSuggestionTap
        )
        .frame(maxWidth: writingContentMaxWidth, alignment: .leading)
    }

    private func writingContentColumn<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: writingContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, writingContentHorizontalPadding)
    }

    private func toggleAssistantLayer() {
        withAnimation(.snappy(duration: 0.2)) {
            showAssistantLayer.toggle()
            VibeWriteLog.launch.info("assistant layer toggle action requested isVisible=\(showAssistantLayer, privacy: .public)")
        }
    }

    private func toggleAppearanceMode() {
        withAnimation(.snappy(duration: 0.18)) {
            appearanceMode = appearanceMode == .night ? .day : .night
        }
    }

    private func toggleHistoryLayer() {
        guard shouldShowHistorySidebar else { return }

        withAnimation(.snappy(duration: 0.2)) {
            if showHistoryLayer {
                showComparison = false
            }

            showHistoryLayer.toggle()
            VibeWriteLog.launch.info("history layer toggle action requested isVisible=\(showHistoryLayer, privacy: .public)")
        }
    }

    private func draftTriggerText() -> String {
        let trimmedDraft = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDraft.isEmpty {
            return trimmedDraft
        }

        let trimmedPrompt = project.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            return trimmedPrompt
        }

        return "先根据当前方向起草第一稿"
    }

    private func draftInstructionText() -> String? {
        let trimmed = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func handlePrimaryAction() {
        guard !flow.isAIRequestInFlight else { return }

        switch primaryAction {
        case .startDraft:
            beginComposerThinking()
            generateFirstDraft(trigger: draftInstructionText() ?? draftTriggerText())

        case .continueWriting:
            beginComposerThinking()
            applyRevision(
                .continueWriting,
                selectionText: nil,
                userMessage: draftInstructionText(),
                clearDraftOnSuccess: true
            )

        case .edit:
            guard let selection = selectedText,
                  !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            beginComposerThinking()
            applyRevision(
                .edit,
                selectionText: selection,
                selectionRange: selectedTextRange,
                userMessage: draftInstructionText(),
                clearDraftOnSuccess: true
            )
        }
    }

    private func handleSuggestionTap(_ suggestion: String) {
        guard !flow.isAIRequestInFlight else { return }

        messageFieldFocused = true
        DispatchQueue.main.async {
            messageDraft = suggestion
        }
    }

    private struct ThinkingDots: View {
        var body: some View {
            TimelineView(.animation) { context in
                let phase = Int((context.date.timeIntervalSinceReferenceDate * 2).rounded(.down)) % 4
                Text(String(repeating: ".", count: phase))
            }
        }
    }

    private func generateFirstDraft(trigger: String) {
        Task { @MainActor in
            do {
                try await flow.performWritingAction(.startDraft, userMessage: trigger, selectionText: nil)
                schedulePostActionCleanup(clearDraftOnSuccess: true, keepHistoryDrawerOpen: false)
            } catch {
                unlockComposerAfterRequest()
            }
        }
    }

    private func applyRevision(
        _ action: WritingAIAction,
        selectionText: String?,
        selectionRange: WritingTextSelectionRange? = nil,
        userMessage: String? = nil,
        clearDraftOnSuccess: Bool = false,
        keepHistoryDrawerOpen: Bool = false
    ) {
        Task { @MainActor in
            do {
                try await flow.performWritingAction(
                    action,
                    userMessage: userMessage,
                    selectionText: selectionText,
                    selectionRange: selectionRange
                )
                schedulePostActionCleanup(
                    clearDraftOnSuccess: clearDraftOnSuccess,
                    keepHistoryDrawerOpen: keepHistoryDrawerOpen
                )
            } catch {
                unlockComposerAfterRequest()
            }
        }
    }

    private func beginComposerThinking() {
        isComposerLocked = true
        messageFieldFocused = false
    }

    private func schedulePostActionCleanup(
        clearDraftOnSuccess: Bool,
        keepHistoryDrawerOpen: Bool
    ) {
        let shouldClearSelection = selectedText != nil
        let shouldCloseComparison = showComparison
        let shouldUpdateHistoryDrawer = shouldShowHistorySidebar && showHistoryLayer != keepHistoryDrawerOpen
        let shouldClearDraft = clearDraftOnSuccess && !messageDraft.isEmpty
        let shouldReleaseFocus = clearDraftOnSuccess && messageFieldFocused

        DispatchQueue.main.async {
            isComposerLocked = false
            if shouldClearSelection {
                selectedText = nil
                selectedTextRange = nil
            }
            if shouldCloseComparison {
                showComparison = false
            }
            if shouldUpdateHistoryDrawer {
                showHistoryLayer = keepHistoryDrawerOpen
            }
            if shouldClearDraft {
                messageDraft = ""
            }
            if shouldReleaseFocus {
                messageFieldFocused = false
            }
        }
    }

    private func unlockComposerAfterRequest() {
        isComposerLocked = false
    }

    private func retryLastChange() {
        guard !flow.isAIRequestInFlight else { return }
        guard let revision = currentRevision else { return }

        _ = flow.undoLastRevision()
        selectedText = revision.lockedSelectionText
        selectedTextRange = revision.lockedSelectionRange
        showComparison = false
        if shouldShowHistorySidebar {
            showHistoryLayer = true
        }

        applyRevision(
            revision.action,
            selectionText: revision.lockedSelectionText,
            selectionRange: revision.lockedSelectionRange,
            userMessage: revision.patch.userMessage,
            clearDraftOnSuccess: revision.patch.userMessage != nil || revision.action == .startDraft,
            keepHistoryDrawerOpen: true
        )
    }

    private func undoLastChange() {
        guard !flow.isAIRequestInFlight else { return }
        guard flow.undoLastRevision() != nil else { return }

        selectedText = nil
        selectedTextRange = nil
        showComparison = false
        if shouldShowHistorySidebar {
            showHistoryLayer = true
        }
        messageDraft = ""
        messageFieldFocused = false
    }

    private func toggleComparison() {
        if showComparison {
            showComparison = false
            return
        }

        guard currentRevision != nil else { return }
        showComparison = true
        if shouldShowHistorySidebar {
            showHistoryLayer = true
        }
    }
}

private struct ChipGrid<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 106), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

private struct SelectionPopover: View {
    let selectedText: String
    let onEditSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(selectedText)
                .font(.system(size: 12.2, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInk)
                .lineLimit(2)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                ActionChip(
                    "润色此处",
                    tint: .vibeCanvasAccent,
                    accessibilityIdentifier: VibeWriteAutomationID.projectEditSelectionButton
                ) {
                    onEditSelection()
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: 300, alignment: .leading)
        .onAppear {
            let preview = selectedText.vibewriteLogPreview(maxLength: 60)
            let message = "selection popover appeared selection=\(preview)"
            VibeWriteDebugTrace.append(message)
            VibeWriteLog.launch.info("\(message, privacy: .public)")
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.vibeCanvasRaised.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.04),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.softLight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.vibeCanvasAccent.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.20), radius: 12, x: 0, y: 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(VibeWriteAutomationID.projectSelectionPopover)
    }
}
@MainActor
private enum WritingProjectPreviewFactory {
    static func flow() -> VibeWriteAppFlow {
        let previewStorageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibewrite-writing-project-preview-\(UUID().uuidString).json")
        let flow = VibeWriteAppFlow(
            storageURL: previewStorageURL,
            aiClient: StubWritingAIClient(),
            aiConfiguration: .configuration(
                from: [:],
                environment: ["VIBEWRITE_AI_DEFAULT_MODE": "stub"]
            ),
            forceBlankStartup: true
        )

        if let project = WorkspaceFixtures.bootstrapProjects().first {
            flow.openProject(project)
        } else {
            flow.createNewProject()
        }
        return flow
    }
}

#Preview("Writing Project - Wide") {
    WritingProjectView(
        flow: WritingProjectPreviewFactory.flow(),
        shellLayoutMode: .wide,
        appearanceMode: .constant(.night)
    )
    .frame(width: 1320, height: 860)
    .preferredColorScheme(.dark)
}

#Preview("Writing Project - Compact") {
    WritingProjectView(
        flow: WritingProjectPreviewFactory.flow(),
        shellLayoutMode: .compact,
        appearanceMode: .constant(.night)
    )
    .frame(width: 980, height: 860)
    .preferredColorScheme(.dark)
}

#Preview("Writing Project - Day") {
    WritingProjectView(
        flow: WritingProjectPreviewFactory.flow(),
        shellLayoutMode: .wide,
        appearanceMode: .constant(.day)
    )
    .frame(width: 1320, height: 860)
    .preferredColorScheme(.light)
}
