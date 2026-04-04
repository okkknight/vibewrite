import AppKit
import SwiftUI

@MainActor
struct RootShellView: View {
    @ObservedObject var flow: VibeWriteAppFlow
    @State private var appearanceMode: VibeAppearanceMode = .night
    @State private var didRequestActivation = false
    private let isRunningInPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    init(flow: VibeWriteAppFlow) {
        self.flow = flow
    }

    var body: some View {
        GeometryReader { proxy in
            let launchArguments = ProcessInfo.processInfo.arguments
            let layoutMode = ProjectShellLayoutMode(
                windowWidth: Double(proxy.size.width),
                forceCompact: launchArguments.contains("--force-compact-layout")
                    || ProcessInfo.processInfo.environment["VIBEWRITE_UI_TEST_FORCE_COMPACT_LAYOUT"] == "1"
            )

            ZStack {
                ProjectBackdrop()

                WritingProjectView(
                    flow: flow,
                    shellLayoutMode: layoutMode,
                    appearanceMode: $appearanceMode
                )
            }
            .tint(.vibeAccent)
            .preferredColorScheme(appearanceMode.colorScheme)
            .toolbarRole(.editor)
            .toolbarBackground(.hidden, for: .windowToolbar)
            .onAppear {
                guard didRequestActivation == false else { return }
                didRequestActivation = true
                guard !isRunningInPreview else { return }

                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.unhide(nil)

                    for window in NSApp.windows {
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                }
            }
        }
    }
}
