import SwiftUI

struct HomeView: View {
    let recentProjects: [WritingProject]
    let inspirationPrompts: [String]
    let onOpenProject: (WritingProject) -> Void
    let onCreateNewProject: () -> Void

    @State private var directPrompt = "写一篇关于成年人孤独感的公众号文章"
    @State private var discussionPrompt = "我想写一个雨夜重逢的小说场景"

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                header
                quickStartSection
                recentProjectsSection
                inspirationSection
            }
            .frame(maxWidth: 1180, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 34)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("VibeWrite")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(.primary)

                Text("一个通过对话持续导演文本的极简 AI 写作协作器。")
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            Button(action: onCreateNewProject) {
                Label("新建写作", systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(VibeWriteAutomationID.homeCreateNewProjectButton)
        }
    }

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(
                title: "快速开始",
                subtitle: "两种起稿方式都保留，先轻量进入，再继续往下写。"
            )

            HStack(alignment: .top, spacing: 18) {
                QuickStartCard(
                    title: "直接起稿",
                    description: "输入一句需求，立即开始正文协作。",
                    icon: "sparkles",
                    accent: .vibeAccent,
                    prompt: $directPrompt,
                    buttonTitle: "立即起稿",
                    accessibilityIdentifier: VibeWriteAutomationID.homeDirectStartButton
                ) {
                    onOpenProject(WritingProject.quickStart(prompt: directPrompt, mode: .collaboration))
                }

                QuickStartCard(
                    title: "先讨论再起稿",
                    description: "先聊清楚想法，再进入第一稿。",
                    icon: "bubble.left.and.bubble.right",
                    accent: .vibeAccentSoft,
                    prompt: $discussionPrompt,
                    buttonTitle: "进入讨论模式",
                    accessibilityIdentifier: VibeWriteAutomationID.homeDiscussionStartButton
                ) {
                    onOpenProject(WritingProject.quickStart(prompt: discussionPrompt, mode: .discussion))
                }
            }
        }
    }

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(
                title: "最近写作",
                subtitle: "保留你最近的上下文，回到上一次未完成的协作。"
            )

            VStack(spacing: 14) {
                ForEach(recentProjects) { project in
                    RecentProjectCard(project: project) {
                        onOpenProject(project)
                    }
                }
            }
        }
    }

    private var inspirationSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(
                title: "灵感示例",
                subtitle: "空白时可以直接拿来试，不需要先搭模板。"
            )

            VibeSurface {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(inspirationPrompts, id: \.self) { prompt in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(Color.vibeAccent.opacity(0.20))
                                .frame(width: 8, height: 8)
                                .padding(.top, 7)

                            Text(prompt)
                                .font(.system(size: 14, weight: .medium, design: .default))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }
}

private struct QuickStartCard: View {
    let title: String
    let description: String
    let icon: String
    let accent: Color
    @Binding var prompt: String
    let buttonTitle: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        VibeSurface(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 32, height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(accent.opacity(0.12))
                        }

                    Text(title)
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                }

                Text(description)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)

                TextField("", text: $prompt, prompt: Text("输入一句需求"))
                    .textFieldStyle(.plain)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 14)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    }

                Button(action: action) {
                    Label(buttonTitle, systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(accessibilityIdentifier)
            }
        }
    }
}

private struct RecentProjectCard: View {
    let project: WritingProject
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VibeSurface(cornerRadius: 26) {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(project.title)
                                .font(.system(size: 18, weight: .semibold, design: .default))
                                .foregroundStyle(.primary)

                            AccentPill(title: project.mode.stageTitle, icon: "circle.fill", tint: .vibeAccent)
                        }

                        Text(project.summary)
                            .font(.system(size: 13.5, weight: .medium, design: .default))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Text("更新时间：\(project.updatedLabel)")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Label("继续写", systemImage: "arrow.right")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(project.title)
        .accessibilityIdentifier(VibeWriteAutomationID.homeRecentProjectCard(project.automationKey))
    }
}
