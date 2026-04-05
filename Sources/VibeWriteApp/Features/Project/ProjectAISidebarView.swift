import SwiftUI

struct ProjectAISidebarView: View {
    let project: WritingProject
    let isExpanded: Bool
    let presentation: ProjectSidebarPresentation
    let isRequestInFlight: Bool
    let errorMessage: String?
    let accessibilityIdentifier: String
    let onToggle: () -> Void
    let onSuggestionTap: (String) -> Void

    private var shouldShowSummaryAndSuggestions: Bool { false }

    var body: some View {
        ProjectSidebarShell(
            title: "Vibe Chat",
            subtitle: sidebarSubtitle,
            icon: "sparkles",
            isExpanded: isExpanded,
            presentation: presentation,
            accessibilityIdentifier: accessibilityIdentifier,
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow
                        .accessibilityIdentifier(VibeWriteAutomationID.projectAISidebarStatus)

                    if shouldShowSummaryAndSuggestions {
                        AISection(title: "协作摘要") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(project.summary)
                                    .font(.system(size: 13.2, weight: .semibold, design: .default))
                                    .foregroundStyle(Color.vibeCanvasInk)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(project.context.intentSummary)
                                    .font(.system(size: 11.2, weight: .medium, design: .default))
                                    .foregroundStyle(Color.vibeCanvasInkSoft)
                                    .fixedSize(horizontal: false, vertical: true)

                                VStack(alignment: .leading, spacing: 7) {
                                    AIContextRow(label: "当前目标", value: project.context.currentGoal)
                                    AIContextRow(label: "下一步", value: project.context.nextFocus)
                                    AIContextRow(
                                        label: "最近决策",
                                        value: joinedOrFallback(project.context.recentDecisions, fallback: "还没有新的决策")
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(VibeWriteAutomationID.projectAISidebarSummary)
                    }

                    AISection(title: "最近回复") {
                        VStack(alignment: .leading, spacing: 8) {
                            if conversationPreview.isEmpty {
                                Text("还没有 AI 回复，先从正文或建议开始。")
                                    .font(.system(size: 11.5, weight: .medium, design: .default))
                                    .foregroundStyle(Color.vibeCanvasInkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(conversationPreview) { message in
                                    ProjectAIMessageRow(message: message)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier(VibeWriteAutomationID.projectAISidebarConversation)

                    if shouldShowSummaryAndSuggestions {
                        AISection(title: "下一步建议") {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)],
                                alignment: .leading,
                                spacing: 8
                            ) {
                                ForEach(suggestionChips, id: \.self) { chip in
                                    ActionChip(
                                        chip,
                                        tint: .vibeCanvasAccent,
                                        accessibilityIdentifier: nil
                                    ) {
                                        onSuggestionTap(chip)
                                    }
                                }
                            }
                        }
                        .accessibilityIdentifier(VibeWriteAutomationID.projectAISidebarSuggestions)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .foregroundStyle(Color.red.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(VibeWriteAutomationID.projectAISidebarError)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(VibeWriteAutomationID.projectAISidebarContent)
            },
            action: onToggle
        )
    }

    private var sidebarSubtitle: String {
        if isRequestInFlight {
            return "AI 正在协作，侧栏保留最新上下文。"
        }

        let nextFocus = project.context.nextFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        return nextFocus.isEmpty ? project.mode.stageDescription : nextFocus
    }

    private var conversationPreview: [ConversationMessage] {
        Array(project.conversation.suffix(VibeWriteDocumentMetadataPolicy.conversationMessageLimit))
    }

    private var suggestionChips: [String] {
        normalizedSuggestionChips(project.suggestionChips)
    }

    private var statusRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Spacer(minLength: 0)
        }
    }

    private func normalizedSuggestionChips(_ chips: [String]) -> [String] {
        var seen = Set<String>()
        return chips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private func joinedOrFallback(_ items: [String], fallback: String) -> String {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else {
            return fallback
        }

        return cleaned.prefix(2).joined(separator: " · ")
    }
}

private struct AISection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11.2, weight: .semibold, design: .default))
                .foregroundStyle(Color.vibeCanvasInkSoft)

            content
                .padding(.leading, 2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}

private struct AIContextRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.8, weight: .semibold, design: .default))
                .foregroundStyle(Color.vibeCanvasInkSoft)

            Text(value)
                .font(.system(size: 12.6, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct ProjectAIMessageRow: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(message.role == .assistant ? Color.vibeCanvasAccent.opacity(0.20) : Color.vibeAccentSoft.opacity(0.18))
                .frame(width: 22, height: 22)
                .overlay {
                    Text(message.role == .assistant ? "AI" : "我")
                        .font(.system(size: 8.5, weight: .bold, design: .default))
                        .foregroundStyle(message.role == .assistant ? Color.vibeCanvasAccent : Color.vibeAccentSoft)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(message.timestamp)
                        .font(.system(size: 10.4, weight: .medium, design: .default))
                        .foregroundStyle(Color.vibeCanvasInkMuted)
                }

                Text(message.text)
                    .font(.system(size: 12.5, weight: .medium, design: .default))
                    .foregroundStyle(Color.vibeCanvasInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
    }
}
