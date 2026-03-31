import SwiftUI

@MainActor
struct RootShellView: View {
    @StateObject private var flow = VibeWriteAppFlow()

    var body: some View {
        ZStack {
            AppBackdrop()

            Group {
                switch flow.screen {
                case .home:
                    HomeView(
                        recentProjects: flow.recentProjects,
                        inspirationPrompts: WorkspaceFixtures.inspirationPrompts,
                        onOpenProject: flow.openProject(_:),
                        onCreateNewProject: flow.createNewProject
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))

                case .project:
                    WritingProjectView(
                        flow: flow,
                        onBack: flow.returnHome
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .tint(.vibeAccent)
        .animation(.snappy(duration: 0.28), value: flow.screen)
    }
}
