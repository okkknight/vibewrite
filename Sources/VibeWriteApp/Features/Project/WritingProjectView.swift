import SwiftUI

struct WritingProjectView: View {
    @ObservedObject var flow: VibeWriteAppFlow
    let onBack: () -> Void

    @State private var messageDraft = ""
    @State private var selectedSegmentIndex: Int?
    @State private var revisionHistory: [String] = []
    @State private var compareBeforeText: String?
    @State private var showComparison = false
    @State private var lastRevision: MockRevisionRecord?
    @FocusState private var messageFieldFocused: Bool

    private var project: WritingProject { flow.activeProject }
    private var projectBinding: Binding<WritingProject> { flow.activeProjectBinding }

    init(flow: VibeWriteAppFlow, onBack: @escaping () -> Void) {
        self.flow = flow
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            projectHeader
            Divider()

            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 24) {
                    ScrollView(showsIndicators: false) {
                        leftColumn
                            .frame(width: 380, alignment: .topLeading)
                    }
                    .frame(width: 380, height: proxy.size.height)

                    ScrollView(showsIndicators: false) {
                        rightColumn
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: proxy.size.height)
                }
                .padding(24)
            }
        }
    }

    private var projectHeader: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                Label("返回", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .semibold, design: .default))
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier(VibeWriteAutomationID.projectBackButton)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier(VibeWriteAutomationID.projectTitle)

                Text(project.mode.stageDescription)
                    .font(.system(size: 12.5, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)
            }

            AccentPill(
                title: project.mode.stageTitle,
                icon: "circle.fill",
                tint: .vibeAccent,
                accessibilityIdentifier: VibeWriteAutomationID.projectStatusBadge
            )

            Spacer(minLength: 12)

            Menu {
                Button("重命名", action: {})
                Button("删除", action: {})
                Button("导出（可后置）", action: {})
            } label: {
                Label("更多", systemImage: "ellipsis")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .padding(.vertical, 9)
                    .padding(.horizontal, 13)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            contextPanel
            conversationPanel
            suggestionsPanel
            inputPanel
        }
    }

    private var contextPanel: some View {
        VibeSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("上下文摘要")
                        .font(.system(size: 15, weight: .semibold, design: .default))
                    Spacer()
                    AccentPill(title: "本地上下文", icon: "note.text", tint: .vibeAccentSoft)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ContextRow(label: "意图", value: project.intentSummary)
                    ContextRow(label: "风格", value: project.styleConstraints.joined(separator: "、"))
                    ContextRow(label: "当前目标", value: project.currentGoal)
                    ContextRow(label: "最近决策", value: project.recentDecisions.joined(separator: "；"))
                    ContextRow(label: "工作记忆", value: project.workingMemory.joined(separator: "；"))
                    ContextRow(label: "下一步", value: project.nextFocus)
                }
            }
        }
    }

    private var conversationPanel: some View {
        VibeSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("对话流")
                    .font(.system(size: 15, weight: .semibold, design: .default))

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(project.conversation) { message in
                        MessageBubble(message: message)
                    }
                }
            }
        }
    }

    private var suggestionsPanel: some View {
        VibeSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("建议继续")
                    .font(.system(size: 15, weight: .semibold, design: .default))

                ChipGrid(items: project.suggestionChips) { chip in
                    ActionChip(chip, tint: .vibeAccentSoft) {
                        handleSuggestionTap(chip)
                    }
                }
            }
        }
    }

    private var inputPanel: some View {
        VibeSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("输入框")
                    .font(.system(size: 15, weight: .semibold, design: .default))

                TextField(
                    project.mode == .discussion
                        ? "继续回答，或告诉 AI 可以开始起稿"
                        : "把第二段改得更克制一点",
                    text: $messageDraft
                )
                .focused($messageFieldFocused)
                .textFieldStyle(.plain)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
                .accessibilityIdentifier(VibeWriteAutomationID.projectMessageInput)
                .accessibilityLabel("消息输入框")

                HStack(alignment: .center) {
                    Text(project.mode == .discussion ? "先聊清楚，再生成第一稿" : "选区带入对话是后续主路径")
                        .font(.system(size: 11.5, weight: .medium, design: .default))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(project.mode == .discussion ? "生成第一稿" : "发送", action: handlePrimaryAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            flow.isAIRequestInFlight ||
                                (messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && project.mode == .collaboration)
                        )
                        .accessibilityIdentifier(VibeWriteAutomationID.projectSendButton)
                }

                if flow.isAIRequestInFlight {
                    Label("AI 正在写作", systemImage: "hourglass")
                        .font(.system(size: 11.5, weight: .medium, design: .default))
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = flow.aiErrorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11.5, weight: .medium, design: .default))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            VibeSurface(cornerRadius: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("当前正文")
                            .font(.system(size: 17, weight: .semibold, design: .default))

                        Spacer()

                        AccentPill(
                            title: project.mode == .discussion ? "还没有正文" : "AI 输出会直接写入正文",
                            icon: project.mode == .discussion ? "doc.text" : "square.and.pencil",
                            tint: .vibeAccent
                        )
                    }

                    if project.mode == .discussion {
                        EmptyDraftHint(onStartDraft: handlePrimaryAction)
                    }

                    SegmentRail(
                        segments: documentSegments,
                        selectedIndex: selectedSegmentIndex,
                        onSelect: { index in
                            selectedSegmentIndex = index
                        }
                    )

                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: projectBinding.documentText)
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 4)
                            .frame(minHeight: 520)
                            .background(Color.clear)
                            .accessibilityIdentifier(VibeWriteAutomationID.projectBodyEditor)
                            .accessibilityLabel("正文编辑区")
                            .onChange(of: project.documentText) { _, newValue in
                                if let selectedSegmentIndex, selectedSegmentIndex >= documentSegments.count {
                                    self.selectedSegmentIndex = nil
                                }
                                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    showComparison = false
                                }
                            }

                        if let selectedSegment = selectedSegment {
                            SelectionPopover(
                                selectedText: selectedSegment,
                                onSendToConversation: bringSelectionIntoConversation,
                                onExpand: { applyRevision(.expand, selectionIndex: selectedSegmentIndex) },
                                onShorten: { applyRevision(.shorten, selectionIndex: selectedSegmentIndex) },
                                onPolish: { applyRevision(.polish, selectionIndex: selectedSegmentIndex) }
                            )
                            .padding(14)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.primary.opacity(0.035))
                    }
                }
            }

            VibeSurface(cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("选区操作")
                        .font(.system(size: 15, weight: .semibold, design: .default))

                    Text("选中段落后，右上角会浮出局部修改入口，主路径是先带入左侧对话再继续导演。")
                        .font(.system(size: 13.5, weight: .medium, design: .default))
                        .foregroundStyle(.secondary)

                    ChipGrid(items: ["在对话中修改这段", "扩写", "缩写", "润色"]) { chip in
                        ActionChip(
                            chip,
                            tint: .vibeAccent,
                            accessibilityIdentifier: selectionChipIdentifier(for: chip)
                        ) {
                            handleSelectionAction(chip)
                        }
                    }
                }
            }

            VibeSurface(cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("版本与回退")
                            .font(.system(size: 15, weight: .semibold, design: .default))

                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button("撤销", action: undoLastChange)
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(VibeWriteAutomationID.projectUndoButton)

                        Button("前后对比", action: toggleComparison)
                            .buttonStyle(.bordered)
                            .disabled(revisionHistory.isEmpty)
                            .accessibilityIdentifier(VibeWriteAutomationID.projectCompareButton)

                        Button("本段重试", action: retryLastChange)
                            .buttonStyle(.bordered)
                            .disabled(lastRevision == nil)
                            .accessibilityIdentifier(VibeWriteAutomationID.projectRetrySectionButton)
                    }
                }
            }

            if showComparison, let compareBeforeText {
                ComparisonPanel(beforeText: compareBeforeText, afterText: project.documentText) {
                    showComparison = false
                }
            }
        }
    }

    private var documentSegments: [String] {
        project.documentText
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var selectedSegment: String? {
        guard let selectedSegmentIndex, documentSegments.indices.contains(selectedSegmentIndex) else {
            return nil
        }

        return documentSegments[selectedSegmentIndex]
    }

    private func handlePrimaryAction() {
        guard !flow.isAIRequestInFlight else { return }

        let trimmed = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if project.mode == .discussion {
            generateFirstDraft(trigger: trimmed.isEmpty ? project.prompt : trimmed)
            return
        }

        guard !trimmed.isEmpty else { return }

        let action = actionForMessage(trimmed)
        applyRevision(
            action,
            selectionIndex: selectedSegmentIndex,
            userMessage: trimmed,
            clearDraftOnSuccess: true
        )
    }

    private func handleSuggestionTap(_ suggestion: String) {
        guard !flow.isAIRequestInFlight else { return }

        switch project.mode {
        case .discussion:
            if suggestion == "开始起稿" {
                generateFirstDraft(trigger: project.prompt)
                return
            }

            if let prompt = MockWritingEngine.assistantPrompt(for: suggestion, mode: project.mode) {
                messageDraft = prompt
                messageFieldFocused = true
            }

        case .collaboration:
            switch suggestion {
            case "调整语气":
                applyRevision(.polish, selectionIndex: selectedSegmentIndex)
            case "继续展开":
                applyRevision(.expand, selectionIndex: selectedSegmentIndex)
            case "收紧结尾":
                applyRevision(.shorten, selectionIndex: selectedSegmentIndex)
            case "降低解释感":
                applyRevision(.polish, selectionIndex: selectedSegmentIndex)
            default:
                break
            }
        }
    }

    private func handleSelectionAction(_ actionTitle: String) {
        guard !flow.isAIRequestInFlight else { return }

        switch actionTitle {
        case "在对话中修改这段":
            bringSelectionIntoConversation()
        case "扩写":
            applyRevision(.expand, selectionIndex: selectedSegmentIndex)
        case "缩写":
            applyRevision(.shorten, selectionIndex: selectedSegmentIndex)
        case "润色":
            applyRevision(.polish, selectionIndex: selectedSegmentIndex)
        default:
            break
        }
    }

    private func bringSelectionIntoConversation() {
        guard let selectedSegment else { return }

        messageDraft = "请把这段改得更克制一点：\(snippet(from: selectedSegment))"
        messageFieldFocused = true
    }

    private func generateFirstDraft(trigger: String) {
        let beforeText = project.documentText
        Task { @MainActor in
            do {
                try await flow.performWritingAction(.startDraft, userMessage: trigger, selectionText: nil)
                recordRevisionHistory(before: beforeText)
                selectedSegmentIndex = nil
                compareBeforeText = beforeText
                showComparison = false
                let currentProject = flow.activeProject
                lastRevision = MockRevisionRecord(
                    action: .startDraft,
                    targetSegmentIndex: nil,
                    selectionText: nil,
                    beforeText: beforeText,
                    afterText: currentProject.documentText
                )
                messageDraft = ""
                messageFieldFocused = false
            } catch {}
        }
    }

    private func applyRevision(
        _ action: MockWritingAction,
        selectionIndex: Int?,
        userMessage: String? = nil,
        variant: MockWritingVariant = .standard,
        clearDraftOnSuccess: Bool = false
    ) {
        let beforeText = project.documentText
        let selectedText = selectedSegment
        Task { @MainActor in
            do {
                try await flow.performWritingAction(
                    action.toWritingAIAction,
                    userMessage: userMessage,
                    selectionText: selectedText
                )
                recordRevisionHistory(before: beforeText)
                let currentProject = flow.activeProject
                lastRevision = MockRevisionRecord(
                    action: action,
                    targetSegmentIndex: selectionIndex,
                    selectionText: selectedText,
                    beforeText: beforeText,
                    afterText: currentProject.documentText
                )
                compareBeforeText = beforeText
                showComparison = true
                if clearDraftOnSuccess {
                    messageDraft = ""
                    messageFieldFocused = false
                }
            } catch {}
        }
    }

    private func retryLastChange() {
        guard !flow.isAIRequestInFlight else { return }
        guard let lastRevision else { return }
        selectedSegmentIndex = lastRevision.targetSegmentIndex
        var updatedProject = flow.activeProject
        updatedProject.documentText = lastRevision.beforeText
        flow.activeProject = updatedProject
        applyRevision(
            lastRevision.action,
            selectionIndex: lastRevision.targetSegmentIndex,
            variant: .retry
        )
    }

    private func undoLastChange() {
        guard let previous = revisionHistory.popLast() else { return }

        var updatedProject = flow.activeProject
        updatedProject.documentText = previous
        updatedProject.currentGoal = "继续推进正文"
        updatedProject.nextFocus = "确认下一步修改方向"
        updatedProject.suggestionChips = suggestionChips(for: project.mode)
        flow.activeProject = updatedProject
        compareBeforeText = nil
        showComparison = false
    }

    private func toggleComparison() {
        if showComparison {
            showComparison = false
            compareBeforeText = nil
            return
        }

        guard let snapshot = revisionHistory.last else { return }
        compareBeforeText = snapshot
        showComparison = true
    }

    private func actionForMessage(_ message: String) -> MockWritingAction {
        if message.contains("扩写") {
            return .expand
        }
        if message.contains("缩写") {
            return .shorten
        }
        if message.contains("润色") || message.contains("更克制") || message.contains("收紧") || message.contains("语气") {
            return .polish
        }
        if selectedSegmentIndex != nil {
            return .selectionModify
        }
        return .polish
    }

    private func recordRevisionHistory(before: String) {
        revisionHistory.append(before)
    }

    private func suggestionChips(for mode: WritingProjectMode) -> [String] {
        switch mode {
        case .discussion:
            return ["明确主题", "确认语气", "开始起稿"]
        case .collaboration:
            return ["调整语气", "继续展开", "收紧结尾", "降低解释感"]
        }
    }

    private func summaryText(for action: MockWritingAction) -> String {
        switch action {
        case .startDraft:
            return "已生成第一稿，正在收紧开头"
        case .expand:
            return "语气保持克制，但内容往外展开了一点"
        case .shorten:
            return "正文被收紧了一些，节奏更干净"
        case .polish:
            return "正文语气更平了，整体更贴近当前风格"
        case .selectionModify:
            return "局部段落通过选区带入对话完成了修改"
        }
    }

    private func goalText(for action: MockWritingAction) -> String {
        switch action {
        case .startDraft:
            return "收紧开头"
        case .expand:
            return "继续推进正文"
        case .shorten:
            return "压缩冗余表达"
        case .polish:
            return "调整语气"
        case .selectionModify:
            return "修改选中文段"
        }
    }

    private func nextFocusText(for action: MockWritingAction) -> String {
        switch action {
        case .startDraft:
            return "继续推进第一段"
        case .expand:
            return "看下一段要不要继续展开"
        case .shorten:
            return "检查结尾是否还需要再收一点"
        case .polish:
            return "决定要不要进一步降低解释感"
        case .selectionModify:
            return "回到正文，继续局部微调"
        }
    }

    private func decisionText(for action: MockWritingAction) -> [String] {
        switch action {
        case .startDraft:
            return ["先生成第一稿", "开头保持克制"]
        case .expand:
            return ["保留主线", "让段落再往外延伸一点"]
        case .shorten:
            return ["压掉多余解释", "让节奏更轻"]
        case .polish:
            return ["语气继续收一收", "避免过度抒情"]
        case .selectionModify:
            return ["选区带入对话", "局部修改优先"]
        }
    }

    private func memoryText(for action: MockWritingAction) -> [String] {
        switch action {
        case .startDraft:
            return ["正文已经进入协作阶段", "后续修改优先围绕主线推进"]
        case .expand:
            return ["当前在做展开", "不要偏离现在的写作主线"]
        case .shorten:
            return ["当前在做收紧", "避免信息密度太高"]
        case .polish:
            return ["当前在做润色", "保留原意，不做风格大改"]
        case .selectionModify:
            return ["当前在改选中文段", "先局部处理，再回到整体"]
        }
    }

    private func snippet(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 36 {
            return cleaned
        }

        return String(cleaned.prefix(36)) + "…"
    }

    private func selectionChipIdentifier(for title: String) -> String? {
        switch title {
        case "在对话中修改这段":
            return VibeWriteAutomationID.projectSelectionModifyButton
        case "扩写":
            return VibeWriteAutomationID.projectSelectionExpandButton
        case "缩写":
            return VibeWriteAutomationID.projectSelectionCondenseButton
        case "润色":
            return VibeWriteAutomationID.projectSelectionPolishButton
        default:
            return nil
        }
    }
}

private extension MockWritingAction {
    var toWritingAIAction: WritingAIAction {
        switch self {
        case .startDraft:
            return .startDraft
        case .expand:
            return .expand
        case .shorten:
            return .shorten
        case .polish:
            return .polish
        case .selectionModify:
            return .selectionModify
        }
    }
}

private struct ContextRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold, design: .default))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 13.5, weight: .medium, design: .default))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(message.role == .assistant ? Color.vibeAccent.opacity(0.18) : Color.vibeAccentSoft.opacity(0.18))
                .frame(width: 26, height: 26)
                .overlay {
                    Text(message.role == .assistant ? "AI" : "我")
                        .font(.system(size: 10, weight: .bold, design: .default))
                        .foregroundStyle(message.role == .assistant ? Color.vibeAccent : Color.vibeAccentSoft)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(message.role.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                    Text(message.timestamp)
                        .font(.system(size: 11.5, weight: .medium, design: .default))
                        .foregroundStyle(.secondary)
                }

                Text(message.text)
                    .font(.system(size: 13.5, weight: .medium, design: .default))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.035))
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

private struct SegmentRail: View {
    let segments: [String]
    let selectedIndex: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("段落选区")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(.secondary)

            if segments.isEmpty {
                Text("先生成第一稿，这里会显示可选段落。")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                            Button(action: { onSelect(index) }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("段落 \(index + 1)")
                                        .font(.system(size: 11, weight: .semibold, design: .default))
                                        .foregroundStyle(index == selectedIndex ? Color.vibeAccent : .secondary)

                                    Text(segment)
                                        .font(.system(size: 12, weight: .medium, design: .default))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(maxWidth: 220, alignment: .leading)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .frame(width: 240, alignment: .leading)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(index == selectedIndex ? Color.vibeAccent.opacity(0.11) : Color.primary.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(index == selectedIndex ? Color.vibeAccent.opacity(0.35) : Color.clear, lineWidth: 1)
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct EmptyDraftHint: View {
    let onStartDraft: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没有正文。先和 AI 聊清楚方向，再生成第一稿。")
                .font(.system(size: 13.5, weight: .medium, design: .default))
                .foregroundStyle(.secondary)

            Button("开始起稿", action: onStartDraft)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(VibeWriteAutomationID.projectStartDraftButton)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
    }
}

private struct SelectionPopover: View {
    let selectedText: String
    let onSendToConversation: () -> Void
    let onExpand: () -> Void
    let onShorten: () -> Void
    let onPolish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选区浮层")
                .font(.system(size: 11.5, weight: .semibold, design: .default))
                .foregroundStyle(.secondary)

            Text(selectedText)
                .font(.system(size: 12.5, weight: .medium, design: .default))
                .foregroundStyle(.primary)
                .lineLimit(4)

            ChipGrid(items: ["在对话中修改这段", "扩写", "缩写", "润色"]) { chip in
                ActionChip(chip, tint: .vibeAccent) {
                    switch chip {
                    case "在对话中修改这段":
                        onSendToConversation()
                    case "扩写":
                        onExpand()
                    case "缩写":
                        onShorten()
                    case "润色":
                        onPolish()
                    default:
                        break
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 318, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
        }
    }
}

private struct ComparisonPanel: View {
    let beforeText: String
    let afterText: String
    let onClose: () -> Void

    var body: some View {
        VibeSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("前后对比")
                        .font(.system(size: 15, weight: .semibold, design: .default))

                    Spacer()

                    Button("关闭", action: onClose)
                        .buttonStyle(.bordered)
                }

                HStack(alignment: .top, spacing: 14) {
                    comparisonColumn(title: "修改前", text: beforeText)
                    comparisonColumn(title: "修改后", text: afterText)
                }
            }
        }
    }

    private func comparisonColumn(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.system(size: 13.5, weight: .medium, design: .default))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 180)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
