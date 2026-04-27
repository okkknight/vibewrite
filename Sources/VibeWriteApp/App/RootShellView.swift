import AppKit
import SwiftUI

@MainActor
struct RootShellView: View {
    let flow: VibeWriteAppFlow
    @State private var appearanceMode: VibeAppearanceMode = .day
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
            .background(
                WindowCloseObserver {
                    flow.handleWindowCloseRequest()
                }
            )
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
                    if let window = NSApp.windows.first(where: { $0.isMainWindow || $0.isKeyWindow }) {
                        VibeWriteLog.launch.info(
                            "RootShellView window probe title=\(window.title.vibewriteLogPreview(maxLength: 40), privacy: .public) number=\(window.windowNumber, privacy: .public) frame=\(String(describing: window.frame), privacy: .public) contentLayoutRect=\(String(describing: window.contentLayoutRect), privacy: .public) visible=\(window.isVisible, privacy: .public) miniaturized=\(window.isMiniaturized, privacy: .public) key=\(window.isKeyWindow, privacy: .public) main=\(window.isMainWindow, privacy: .public) autosave=\(window.frameAutosaveName, privacy: .public)"
                        )
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                    }
                    VibeWriteLog.launch.info(
                        "RootShellView window probe count=\(NSApp.windows.count, privacy: .public)"
                    )
                    for window in NSApp.windows {
                        VibeWriteLog.launch.info(
                            "RootShellView window listed title=\(window.title.vibewriteLogPreview(maxLength: 40), privacy: .public) number=\(window.windowNumber, privacy: .public) frame=\(String(describing: window.frame), privacy: .public) contentLayoutRect=\(String(describing: window.contentLayoutRect), privacy: .public) visible=\(window.isVisible, privacy: .public) miniaturized=\(window.isMiniaturized, privacy: .public) key=\(window.isKeyWindow, privacy: .public) main=\(window.isMainWindow, privacy: .public) autosave=\(window.frameAutosaveName, privacy: .public)"
                        )
                    }
                }
            }
        }
    }
}

private struct WindowCloseObserver: NSViewRepresentable {
    let shouldClose: () -> Bool

    final class ObserverView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldClose: shouldClose)
    }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView(frame: .zero)
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        context.coordinator.shouldClose = shouldClose
        nsView.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        context.coordinator.attach(to: nsView.window)
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        var shouldClose: () -> Bool
        weak var window: NSWindow?

        init(shouldClose: @escaping () -> Bool) {
            self.shouldClose = shouldClose
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            self.window = window
            window.delegate = self
            applyWindowChrome(to: window)
        }

        private func applyWindowChrome(to window: NSWindow) {
            if !window.title.isEmpty {
                window.title = ""
            }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
        }

        func windowDidBecomeMain(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            applyWindowChrome(to: window)
        }

        func windowDidBecomeKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            applyWindowChrome(to: window)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            return shouldClose()
        }
    }
}
