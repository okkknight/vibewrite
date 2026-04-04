import SwiftUI

struct ProjectHistoryDrawerView: View {
    let project: WritingProject
    let isExpanded: Bool
    let presentation: ProjectSidebarPresentation
    let isComparisonVisible: Bool
    let isRequestInFlight: Bool
    let accessibilityIdentifier: String
    let onToggle: () -> Void
    let onUndo: () -> Void
    let onRetry: () -> Void
    let onToggleComparison: () -> Void

    private var currentRevision: WritingProjectRevision? {
        project.revisionHistory.last
    }

    private var revisionRows: [WritingProjectRevision] {
        Array(project.revisionHistory.suffix(4).reversed())
    }

    private var recentMessages: [ConversationMessage] {
        Array(project.conversation.suffix(VibeWriteDocumentMetadataPolicy.conversationMessageLimit))
    }

    var body: some View {
        ProjectSidebarShell(
            title: "历史与版本",
            subtitle: sidebarSubtitle,
            icon: "clock.arrow.circlepath",
            isExpanded: isExpanded,
            presentation: presentation,
            accessibilityIdentifier: accessibilityIdentifier,
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow

                    if isComparisonVisible, let currentRevision {
                        ProjectHistoryComparePanel(revision: currentRevision)
                    }

                    HistorySection(title: "回退与比较") {
                        actionBar
                    }
                    .accessibilityIdentifier(VibeWriteAutomationID.projectHistoryActions)

                    HistorySection(title: "当前版本摘要") {
                        currentVersionCard
                    }
                    .accessibilityIdentifier(VibeWriteAutomationID.projectHistoryCurrentVersion)

                    HistorySection(title: "最近会话") {
                        recentSessionsList
                    }
                    .accessibilityIdentifier(VibeWriteAutomationID.projectHistoryRecentSessions)

                    HistorySection(title: "线性 patch") {
                        revisionTimeline
                    }
                    .accessibilityIdentifier(VibeWriteAutomationID.projectHistoryRevisionList)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(VibeWriteAutomationID.projectHistoryDrawerContent)
            },
            action: onToggle
        )
    }

    private var sidebarSubtitle: String {
        if let currentRevision {
            return "\(project.revisionHistory.count) 次 patch · \(currentRevision.title)"
        }

        return "最近会话、线性 patch、回退和对比。"
    }

    private var statusRow: some View {
        HStack(alignment: .center, spacing: 8) {
            AccentPill(
                title: currentRevision == nil ? "暂无版本" : "\(project.revisionHistory.count) 个 patch",
                icon: "clock.arrow.circlepath",
                tint: .vibeCanvasAccent
            )

            Spacer(minLength: 0)

            Text(project.updatedLabel)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInkMuted)
        }
    }

    private var currentVersionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(project.summary)
                .font(.system(size: 13.2, weight: .semibold, design: .default))
                .foregroundStyle(Color.vibeCanvasInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(project.context.currentGoal)
                .font(.system(size: 11.2, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if let currentRevision {
                Text(currentRevision.title)
                    .font(.system(size: 11.5, weight: .semibold, design: .default))
                    .foregroundStyle(Color.vibeCanvasInkSoft)

                Text(currentRevision.subtitle)
                    .font(.system(size: 11.2, weight: .medium, design: .default))
                    .foregroundStyle(Color.vibeCanvasInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("先起第一稿，历史抽屉会在这里记录线性 patch。")
                    .font(.system(size: 11.2, weight: .medium, design: .default))
                    .foregroundStyle(Color.vibeCanvasInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recentMessages.isEmpty {
                emptyState(
                    title: "还没有会话",
                    subtitle: "先开始写作，最近会话会和线性历史一起出现在这里。"
                )
            } else {
                ForEach(recentMessages) { message in
                    HistoryMessageRow(message: message)
                }
            }
        }
    }

    private var revisionTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            if revisionRows.isEmpty {
                emptyState(
                    title: "还没有 patch 历史",
                    subtitle: "先生成第一稿，后续的续写和局部修改都会按线性顺序记录。"
                )
            } else {
                ForEach(revisionRows) { revision in
                    HistoryRevisionRow(
                        revision: revision,
                        isCurrent: revision.id == currentRevision?.id
                    )
                }
            }
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                HistoryActionButton(
                    title: "回退上一版",
                    isProminent: false,
                    isEnabled: currentRevision != nil && !isRequestInFlight,
                    accessibilityIdentifier: VibeWriteAutomationID.projectUndoButton,
                    action: onUndo
                )

                HistoryActionButton(
                    title: "重试修改",
                    isProminent: false,
                    isEnabled: currentRevision != nil && !isRequestInFlight,
                    accessibilityIdentifier: VibeWriteAutomationID.projectRetrySectionButton,
                    action: onRetry
                )

                HistoryActionButton(
                    title: isComparisonVisible ? "关闭对比" : "前后对比",
                    isProminent: true,
                    isEnabled: currentRevision != nil && !isRequestInFlight,
                    accessibilityIdentifier: VibeWriteAutomationID.projectCompareButton,
                    action: onToggleComparison
                )
            }

            Text("只保留最近一条线性 patch 的回看关系，不展开版本树。")
                .font(.system(size: 10.8, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .default))
                .foregroundStyle(Color.vibeCanvasInk)

            Text(subtitle)
                .font(.system(size: 10.8, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct HistorySection<Content: View>: View {
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
    }
}

private struct HistoryMessageRow: View {
    let message: ConversationMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AccentPill(
                    title: message.role.displayName,
                    icon: nil,
                    tint: message.role == .assistant ? .vibeCanvasAccent : .vibeAccentSoft
                )

                Spacer(minLength: 0)

                Text(message.timestamp)
                    .font(.system(size: 10.8, weight: .medium, design: .default))
                    .foregroundStyle(Color.vibeCanvasInkMuted)
            }

            Text(message.text)
                .font(.system(size: 12.5, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInk)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
    }
}

private struct HistoryRevisionRow: View {
    let revision: WritingProjectRevision
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(revision.title)
                    .font(.system(size: 12.4, weight: .semibold, design: .default))
                    .foregroundStyle(Color.vibeCanvasInk)

                if isCurrent {
                    AccentPill(title: "当前", icon: nil, tint: .vibeCanvasAccent)
                }

                Spacer(minLength: 0)

                Text(relativeLabel(for: revision.createdAt))
                    .font(.system(size: 10.8, weight: .medium, design: .default))
                    .foregroundStyle(Color.vibeCanvasInkMuted)
            }

            Text(revision.subtitle)
                .font(.system(size: 11.2, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInkSoft)
                .lineLimit(2)
                .truncationMode(.tail)

            Text(revision.patch.summary)
                .font(.system(size: 11.2, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInk)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? Color.vibeCanvasAccent.opacity(0.12) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isCurrent ? Color.vibeCanvasAccent.opacity(0.38) : Color.vibeCanvasStroke.opacity(0.20), lineWidth: 1)
                )
        }
    }

    private func relativeLabel(for date: Date) -> String {
        let interval = Int(Date().timeIntervalSince(date))
        if interval < 60 {
            return "刚刚"
        }

        let minutes = interval / 60
        if minutes < 60 {
            return "\(minutes) 分钟前"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) 小时前"
        }

        let days = hours / 24
        if days < 30 {
            return "\(days) 天前"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }
}

private struct HistoryActionButton: View {
    let title: String
    let isProminent: Bool
    let isEnabled: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        if isProminent {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .default))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(BorderedProminentButtonStyle())
            .controlSize(.small)
            .tint(.vibeCanvasAccent)
            .disabled(!isEnabled)
            .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .default))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(BorderedButtonStyle())
            .controlSize(.small)
            .tint(.vibeCanvasAccent)
            .disabled(!isEnabled)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
    }
}

private struct ProjectHistoryComparePanel: View {
    let revision: WritingProjectRevision

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("前后对比")
                    .font(.system(size: 12.5, weight: .semibold, design: .default))
                    .foregroundStyle(Color.vibeCanvasInk)

                Spacer(minLength: 0)

                Text(revision.patch.scopeLabel)
                    .font(.system(size: 10.8, weight: .medium, design: .default))
                    .foregroundStyle(Color.vibeCanvasInkMuted)
            }

            comparisonBlock(title: "修改前", text: revision.before.documentText)
            comparisonBlock(title: "修改后", text: revision.after.documentText)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.vibeCanvasRaised.opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.vibeCanvasAccent.opacity(0.24), lineWidth: 1)
                )
        }
        .accessibilityIdentifier(VibeWriteAutomationID.projectComparisonPanel)
    }

    private func comparisonBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .default))
                .foregroundStyle(Color.vibeCanvasInkSoft)

            Text(text)
                .font(.system(size: 11.8, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeCanvasInk)
                .lineLimit(4)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.08)
        }
    }
}
