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
    @State private var localEditFlash: WritingLocalEditFlash?
    @State private var isLocalEditViewportLocked = false
    @State private var isDocumentEndFollowActive = false
    @State private var bodyEditorScrollView: NSScrollView?
    @State private var showComparison = false
    @State private var showAssistantLayer = false
    @State private var showHistoryLayer = false
    @State private var isComposerLocked = false
    @FocusState private var messageFieldFocused: Bool

    private var project: WritingProject { flow.activeEditingProject }
    private var currentRevision: WritingProjectRevision? { project.revisionHistory.last }
    private var assistantDrawerWidth: CGFloat { shellLayoutMode.isCompact ? 300 : 280 }
    private var historyDrawerWidth: CGFloat { shellLayoutMode.isCompact ? 372 : 344 }
    private var shouldShowHistorySidebar: Bool { false }
    /// 与右侧透明占位同宽，标题在中间 `frame(maxWidth: .infinity)` 里相对**整行**居中，不会被左侧按钮顶偏。
    private var projectHeaderSideChromeWidth: CGFloat {
        shouldShowHistorySidebar ? 80 : 44
    }
    private var writingContentMaxWidth: CGFloat { 900 }
    private var writingContentHorizontalPadding: CGFloat { shellLayoutMode.isCompact ? 16 : 30 }
    private var projectHeaderVerticalPadding: CGFloat { shellLayoutMode.isCompact ? 7 : 8 }
    private var composerRailBottomInset: CGFloat { 73 }
    /// 正文编辑器的文本起始 inset，跟 composer 的输入节奏保持同一条视觉基线。
    private var writingBodyTextContainerInset: NSSize {
        NSSize(width: 12, height: 18)
    }
    private var bodyEdgeFadeHeight: CGFloat { shellLayoutMode.isCompact ? 14 : 18 }

    private var projectTitleBinding: Binding<String> {
        let projectID = project.id
        return Binding(
            get: { project.title },
            set: { newTitle in
                let activeProjectID = flow.activeProject.id.uuidString
                let isHydrationProtected = flow.isDocumentHydrationProtected(for: projectID)
                VibeWriteDebugTrace.append(
                    "project title binding writeback projectID=\(projectID.uuidString) activeProjectID=\(activeProjectID) titleCount=\(newTitle.count)"
                )
                VibeWriteLog.launch.info(
                    "project title binding writeback projectID=\(projectID.uuidString, privacy: .public) activeProjectID=\(activeProjectID, privacy: .public) titleCount=\(newTitle.count, privacy: .public) hydrationProtected=\(isHydrationProtected, privacy: .public)"
                )
                guard flow.activeProject.id == projectID else { return }
                guard !isHydrationProtected else {
                    VibeWriteDebugTrace.append(
                        "project title binding suppressed during document hydration projectID=\(projectID.uuidString) titleCount=\(newTitle.count)"
                    )
                    VibeWriteLog.launch.info(
                        "project title binding suppressed during document hydration projectID=\(projectID.uuidString, privacy: .public) titleCount=\(newTitle.count, privacy: .public)"
                    )
                    return
                }
                VibeWriteDebugTrace.append(
                    "project title binding accepted projectID=\(projectID.uuidString) newTitleCount=\(newTitle.count)"
                )
                VibeWriteLog.launch.info(
                    "project title binding accepted projectID=\(projectID.uuidString, privacy: .public) newTitleCount=\(newTitle.count, privacy: .public)"
                )
                var updatedProject = flow.activeEditingProject
                updatedProject.title = newTitle
                flow.openProject(updatedProject)
            }
        )
    }

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
            localEditFlash = nil
            isLocalEditViewportLocked = false
            isDocumentEndFollowActive = false
            bodyEditorScrollView = nil
            showComparison = false
            showAssistantLayer = false
            showHistoryLayer = false
            isComposerLocked = false
            messageDraft = ""
            messageFieldFocused = false
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
        ZStack(alignment: .topTrailing) {
            wideWorkspace
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let bodyEditorScrollView {
                ExternalVerticalScroller(scrollView: bodyEditorScrollView)
                    .frame(width: 12)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
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
                .padding(.vertical, projectHeaderVerticalPadding)
                .simultaneousGesture(TapGesture().onEnded {
                    messageFieldFocused = false
                })

            VStack(spacing: 0) {
                writingBodyPane(topPadding: 16, bottomPadding: 0)
                composerSection(verticalPadding: 0)
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var wideAssistantRail: some View {
        assistantLayer
            .frame(width: assistantDrawerWidth)
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .simultaneousGesture(TapGesture().onEnded {
                messageFieldFocused = false
            })
    }

    private var wideHistoryRail: some View {
        historyLayer
            .frame(width: historyDrawerWidth)
            .padding(.vertical, 10)
            .padding(.trailing, 10)
            .simultaneousGesture(TapGesture().onEnded {
                messageFieldFocused = false
            })
    }

    private var centerStage: some View {
        VStack(spacing: 0) {
            projectHeader
                .padding(.horizontal, shellLayoutMode.isCompact ? 18 : 22)
                .padding(.vertical, projectHeaderVerticalPadding)
                .simultaneousGesture(TapGesture().onEnded {
                    messageFieldFocused = false
                })

            VStack(spacing: 0) {
                writingBodyPane(
                    topPadding: shellLayoutMode.isCompact ? 14 : 16,
                    bottomPadding: 0
                )
                composerSection(verticalPadding: 0)
            }
            .padding(.bottom, shellLayoutMode.isCompact ? 14 : 16)
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
                TextField("未命名写作", text: projectTitleBinding)
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

            if flow.isProseRequestInFlight {
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

        let trimmedSummary = project.localSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedSummary.isEmpty ? project.mode.stageDescription : trimmedSummary
    }

    private func editorBody(minimumHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .topLeading) {
                SelectableTextEditor(
                    text: flow.activeDocumentTextBinding,
                    selectedText: $selectedText,
                    selectedTextRange: $selectedTextRange,
                    selectionPopoverOrigin: $selectionPopoverOrigin,
                    isEditable: !flow.isAIRequestInFlight && flow.activeEditLock == nil,
                    accessibilityIdentifier: VibeWriteAutomationID.projectBodyEditor,
                    shouldAutoScrollToDocumentEnd: flow.isProseRequestInFlight || isDocumentEndFollowActive,
                    textFont: NSFont.systemFont(ofSize: 16, weight: .regular),
                    textColor: NSColor.vibeCanvasInk,
                    insertionPointColor: NSColor.vibeAccent,
                    selectedTextBackgroundColor: NSColor.vibeAccent.withAlphaComponent(0.30),
                    textContainerInset: writingBodyTextContainerInset,
                    localEditFlash: localEditFlash,
                    isViewportLockedDuringLocalEdit: isLocalEditViewportLocked,
                    shouldPreserveSelectionOverlayDuringPendingLocalEdit: isComposerLocked,
                    onScrollViewReady: { scrollView in
                        bodyEditorScrollView = scrollView
                    }
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

                bodyTopFadeOverlay
            }
            .overlay {
                BodyEditorScrollToBottomOverlay(
                    scrollView: bodyEditorScrollView,
                    appearanceMode: appearanceMode,
                    onScrollToBottom: scrollBodyEditorToBottom
                )
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

    private func scrollBodyEditorToBottom() {
        guard let scrollView = bodyEditorScrollView,
              let textView = scrollView.documentView as? NSTextView else { return }

        let endRange = NSRange(location: textView.string.utf16.count, length: 0)
        selectedText = nil
        selectedTextRange = WritingTextSelectionRange(location: endRange.location, length: 0)
        isDocumentEndFollowActive = true
        textView.setSelectedRange(endRange)
        textView.scrollRangeToVisible(endRange)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if isDocumentEndFollowActive {
                isDocumentEndFollowActive = false
            }
        }
    }

    private var assistantLayer: some View {
        ProjectAISidebarView(
            project: project,
            isExpanded: true,
            presentation: shellLayoutMode.isCompact ? .drawer : .column,
            isRequestInFlight: flow.isProseRequestInFlight,
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
            isRequestInFlight: flow.isProseRequestInFlight,
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
        let renderable = normalizedSelectedText != nil
        let message = "selection state \(trigger) selection=\(selectionPreview) origin=\(originPreview) renderable=\(renderable)"
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
            return "开场"
        case .continueWriting:
            return "续写"
        case .edit:
            return "润色"
        }
    }

    private var shouldShowAssistantSuggestions: Bool {
        normalizedSelectedText == nil
    }

    private var messageFieldPlaceholder: String {
        switch primaryAction {
        case .startDraft:
            return "先从一段开场，开启写作之旅。"
        case .continueWriting:
            return assistantNextFocusPlaceholderText
        case .edit:
            return "输入你的修改建议"
        }
    }

    private var assistantNextFocusPlaceholderText: String {
        let trimmedNextFocus = project.nextFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNextFocus.isEmpty ? "你想怎么展开下一段。" : trimmedNextFocus
    }

    private var composerBar: some View {
        ProjectComposerBar(
            messageDraft: $messageDraft,
            appearanceMode: appearanceMode,
            primaryActionTitle: primaryActionTitle,
            messageFieldPlaceholder: messageFieldPlaceholder,
            showsAssistantSuggestions: shouldShowAssistantSuggestions,
            assistantSuggestionChips: project.suggestionChips,
            isComposerLocked: isComposerLocked,
            isRequestInFlight: flow.isAIRequestInFlight,
            isPrimaryActionInFlight: flow.isProseRequestInFlight,
            isSuggestionGenerationInFlight: flow.isMetadataRequestInFlight,
            messageFieldFocused: $messageFieldFocused,
            isMessageFieldHighlighted: normalizedSelectedText != nil,
            guidanceRailBottomInset: composerRailBottomInset,
            accessibilityIdentifier: VibeWriteAutomationID.projectComposerBar,
            messageInputIdentifier: VibeWriteAutomationID.projectMessageInput,
            sendButtonIdentifier: VibeWriteAutomationID.projectSendButton,
            onSubmit: handlePrimaryAction,
            onAssistantSuggestionTap: handleSuggestionTap
        )
        .frame(maxWidth: writingContentMaxWidth, alignment: .leading)
    }

    private func composerSection(verticalPadding: CGFloat) -> some View {
        writingContentColumn {
            composerBar
                .padding(.vertical, verticalPadding)
                .overlay(alignment: .bottomLeading) {
                    if normalizedSelectedText != nil {
                        SelectionContextRail(
                            isRequestInFlight: flow.isAIRequestInFlight || isComposerLocked,
                            onPresetTap: triggerSelectionPresetEdit
                        )
                        .padding(.horizontal, 14)
                        .padding(.bottom, composerRailBottomInset)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: normalizedSelectedText != nil)
        }
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
            guard let userMessage = draftInstructionText() else {
                messageFieldFocused = true
                return
            }
            beginComposerThinking()
            beginLocalEditPresentation()
            applyRevision(
                .edit,
                selectionText: selection,
                selectionRange: selectedTextRange,
                userMessage: userMessage,
                clearDraftOnSuccess: true
            )
        }
    }

    private func triggerSelectionPresetEdit(_ preset: SelectionEditPreset) {
        guard !flow.isAIRequestInFlight else { return }
        guard let selection = normalizedSelectedText else { return }

        beginComposerThinking()
        beginLocalEditPresentation()
        applyRevision(
            .edit,
            selectionText: selection,
            selectionRange: selectedTextRange,
            userMessage: preset.prompt,
            clearDraftOnSuccess: true
        )
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
        beginDocumentEndFollow()
        Task { @MainActor in
            do {
                try await flow.performWritingAction(.startDraft, userMessage: trigger, selectionText: nil)
                schedulePostActionCleanup(
                    action: .startDraft,
                    clearDraftOnSuccess: true,
                    keepHistoryDrawerOpen: false
                )
            } catch {
                endDocumentEndFollow()
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
        if action == .startDraft || action == .continueWriting {
            beginDocumentEndFollow()
        }
        Task { @MainActor in
            do {
                try await flow.performWritingAction(
                    action,
                    userMessage: userMessage,
                    selectionText: selectionText,
                    selectionRange: selectionRange
                )
                schedulePostActionCleanup(
                    action: action,
                    clearDraftOnSuccess: clearDraftOnSuccess,
                    keepHistoryDrawerOpen: keepHistoryDrawerOpen
                )
            } catch {
                if action == .startDraft || action == .continueWriting {
                    endDocumentEndFollow()
                }
                unlockComposerAfterRequest()
            }
        }
    }

    private func beginComposerThinking() {
        isComposerLocked = true
        messageFieldFocused = false
    }

    private func beginDocumentEndFollow() {
        isDocumentEndFollowActive = true
    }

    private func endDocumentEndFollow() {
        isDocumentEndFollowActive = false
    }

    private func schedulePostActionCleanup(
        action: WritingAIAction,
        clearDraftOnSuccess: Bool,
        keepHistoryDrawerOpen: Bool
    ) {
        let shouldClearSelection = selectedText != nil
        let shouldCloseComparison = showComparison
        let shouldUpdateHistoryDrawer = shouldShowHistorySidebar && showHistoryLayer != keepHistoryDrawerOpen
        let shouldClearDraft = clearDraftOnSuccess && !messageDraft.isEmpty
        let shouldReleaseFocus = clearDraftOnSuccess && messageFieldFocused
        let latestRevision = project.revisionHistory.last
        let shouldFlashLocalEdit = action == .edit && latestRevision?.patch.replacementHighlightRange != nil
        let flash = latestRevision?.patch.replacementHighlightRange.map {
            WritingLocalEditFlash(range: $0)
        }
        let flashRangePreview = latestRevision?.patch.replacementHighlightRange?.nsRange.debugDescription ?? "nil"
        let shouldPinCaretToDocumentEnd = action == .startDraft || action == .continueWriting
        let documentEndSelection = WritingTextSelectionRange(
            location: project.documentText.utf16.count,
            length: 0
        )

        DispatchQueue.main.async {
            VibeWriteDebugTrace.append(
                "local edit cleanup action=\(action.rawValue) shouldFlash=\(shouldFlashLocalEdit) flashRange=\(flashRangePreview)"
            )
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

            if shouldPinCaretToDocumentEnd {
                selectedText = nil
                selectedTextRange = documentEndSelection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    if isDocumentEndFollowActive {
                        isDocumentEndFollowActive = false
                    }
                }
            }

            if shouldFlashLocalEdit, let flash {
                VibeWriteDebugTrace.append(
                    "local edit flash scheduled id=\(flash.id.uuidString) range=\(flash.range.nsRange.debugDescription)"
                )
                localEditFlash = flash
                isLocalEditViewportLocked = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if localEditFlash?.id == flash.id {
                        VibeWriteDebugTrace.append(
                            "local edit flash cleared id=\(flash.id.uuidString)"
                        )
                        localEditFlash = nil
                        isLocalEditViewportLocked = false
                    }
                }
            } else if action == .edit {
                VibeWriteDebugTrace.append("local edit flash skipped action=edit reason=missing-range")
                localEditFlash = nil
                isLocalEditViewportLocked = false
            } else {
                localEditFlash = nil
                isLocalEditViewportLocked = false
            }
        }
    }

    private func unlockComposerAfterRequest() {
        isComposerLocked = false
        localEditFlash = nil
        isLocalEditViewportLocked = false
    }

    private func beginLocalEditPresentation() {
        isLocalEditViewportLocked = true
        localEditFlash = nil
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

        if revision.action == .edit {
            beginComposerThinking()
            beginLocalEditPresentation()
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

    private var bodyTopFadeOverlay: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.vibeCanvas.opacity(0.94),
                    Color.vibeCanvas.opacity(0.46),
                    Color.vibeCanvas.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: bodyEdgeFadeHeight)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BodyEditorScrollToBottomOverlay: View {
    let scrollView: NSScrollView?
    let appearanceMode: VibeAppearanceMode
    let onScrollToBottom: () -> Void

    @State private var viewportState = SelectableTextEditorViewportState()

    var body: some View {
        ZStack(alignment: .bottom) {
            if shouldShowButton {
                Button(action: onScrollToBottom) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 12.8, weight: .semibold, design: .default))
                        .foregroundStyle(Color.vibeCanvasInk)
                        .frame(width: 30, height: 30)
                        .background {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(
                                    appearanceMode == .day
                                        ? Color.vibeCanvasLift.opacity(0.84)
                                        : Color.vibeCanvasLift.opacity(0.82)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.02),
                                                    .clear
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .blendMode(.softLight)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .strokeBorder(Color.vibeCanvasStroke.opacity(0.28), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(appearanceMode == .day ? 0.08 : 0.14), radius: 8, x: 0, y: 3)
                        }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel("回到底端")
                .accessibilityIdentifier("scrollToBottomButton")
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(true)
        .background {
            ScrollViewportStateReader(scrollView: scrollView) { viewportState = $0 }
        }
        .animation(.easeInOut(duration: 0.16), value: shouldShowButton)
    }

    private var shouldShowButton: Bool {
        viewportState.canScrollDown && !viewportState.isAtDocumentEnd
    }
}

private struct ScrollViewportStateReader: NSViewRepresentable {
    let scrollView: NSScrollView?
    let onChange: (SelectableTextEditorViewportState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.attach(to: scrollView)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: (SelectableTextEditorViewportState) -> Void
        weak var scrollView: NSScrollView?
        weak var observedContentView: NSClipView?
        weak var observedTextView: NSTextView?
        private var lastReportedState: SelectableTextEditorViewportState?

        init(onChange: @escaping (SelectableTextEditorViewportState) -> Void) {
            self.onChange = onChange
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to scrollView: NSScrollView?) {
            guard self.scrollView !== scrollView else {
                emitCurrentState()
                return
            }

            NotificationCenter.default.removeObserver(self)
            self.scrollView = scrollView
            observedContentView = nil
            observedTextView = nil

            guard let scrollView else {
                lastReportedState = nil
                return
            }

            let contentView = scrollView.contentView
            let textView = scrollView.documentView as? NSTextView
            observedContentView = contentView
            observedTextView = textView

            contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleViewportDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )

            if let textView {
                textView.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleViewportDidChange(_:)),
                    name: NSView.frameDidChangeNotification,
                    object: textView
                )
            }

            emitCurrentState()
        }

        @objc
        private func handleViewportDidChange(_ notification: Notification) {
            emitCurrentState()
        }

        private func emitCurrentState() {
            guard let scrollView,
                  let textView = scrollView.documentView as? NSTextView else { return }

            let visibleHeight = max(scrollView.contentView.bounds.height, 1)
            let contentHeight = max(textView.frame.height, visibleHeight)
            let maximumScrollOffsetY = max(contentHeight - visibleHeight, 0)
            let currentScrollOffsetY = max(scrollView.contentView.bounds.origin.y, 0)
            let viewportState = SelectableTextEditorViewportState(
                contentHeight: contentHeight,
                visibleHeight: visibleHeight,
                currentScrollOffsetY: currentScrollOffsetY,
                maximumScrollOffsetY: maximumScrollOffsetY
            )

            guard lastReportedState != viewportState else { return }
            lastReportedState = viewportState
            onChange(viewportState)
        }
    }
}

private enum SelectionEditPreset: CaseIterable, Hashable {
    case moreVisual
    case moreRestrained
    case moreCompelling

    var title: String {
        switch self {
        case .moreVisual:
            return "更画面"
        case .moreRestrained:
            return "更克制"
        case .moreCompelling:
            return "更抓人"
        }
    }

    var prompt: String {
        switch self {
        case .moreVisual:
            return "把这段改得更有画面感，更具体、更可感，但保持原意，不要明显扩写。"
        case .moreRestrained:
            return "把这段改得更克制、更收一点，减少解释和用力过猛，保持原意。"
        case .moreCompelling:
            return "把这段改得更抓人、更有吸引力，但不要浮夸，保持原意。"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .moreVisual:
            return VibeWriteAutomationID.projectSelectionVisualButton
        case .moreRestrained:
            return VibeWriteAutomationID.projectSelectionRestrainedButton
        case .moreCompelling:
            return VibeWriteAutomationID.projectSelectionCompellingButton
        }
    }
}

private struct SelectionContextRail: View {
    let isRequestInFlight: Bool
    let onPresetTap: (SelectionEditPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TwoRowFlowLayout(itemSpacing: 8, rowSpacing: 8) {
                ForEach(SelectionEditPreset.allCases, id: \.self) { preset in
                    ActionChip(
                        preset.title,
                        tint: .vibeCanvasAccent,
                        accessibilityIdentifier: preset.accessibilityIdentifier
                    ) {
                        onPresetTap(preset)
                    }
                    .opacity(isRequestInFlight ? 0.58 : 1)
                    .disabled(isRequestInFlight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
