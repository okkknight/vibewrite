import AppKit
import SwiftUI

@main
struct VibeWriteApp: App {
    @StateObject private var flow: VibeWriteAppFlow
    @NSApplicationDelegateAdaptor private var appDelegate: VibeWriteApplicationDelegate

    init() {
        let launchArguments = ProcessInfo.processInfo.arguments
        let launchEnvironment = ProcessInfo.processInfo.environment
        let resolvedCleanLaunch = launchArguments.contains("--clean-launch")
            || launchEnvironment["VIBEWRITE_FORCE_BLANK_STARTUP"] == "1"
        let resolvedForceBlankStartup = resolvedCleanLaunch
            || launchEnvironment["VIBEWRITE_UI_TEST_RESET_STORAGE"] == "1"
        let joinedArguments = launchArguments.joined(separator: " ")

        VibeWriteLog.launch.info(
            "Launch configured with cleanStartup=\(resolvedForceBlankStartup, privacy: .public) cleanLaunch=\(resolvedCleanLaunch, privacy: .public) arguments=\(joinedArguments, privacy: .public)"
        )
        _flow = StateObject(
            wrappedValue: VibeWriteAppFlow(
                aiConfiguration: WritingAIConfiguration.current(
                    ignoreEnvironmentOverrides: resolvedCleanLaunch
                ),
                streamingConfiguration: WritingStreamingConfiguration.current(
                    ignoreEnvironmentOverrides: resolvedCleanLaunch
                ),
                forceBlankStartup: resolvedForceBlankStartup
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootShellView(
                flow: flow
            )
        }
        .defaultSize(width: 1024, height: 700)
        .commands {
            VibeWriteCommands(flow: flow)
        }
    }
}

@MainActor
final class VibeWriteApplicationDelegate: NSObject, NSApplicationDelegate {
    private var keyDownMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let characters = event.characters ?? ""
            let ignoringModifiers = event.charactersIgnoringModifiers ?? ""
            let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            VibeWriteLog.launch.info(
                "app delegate keyDown keyCode=\(event.keyCode, privacy: .public) characters=\(characters.vibewriteLogPreview(maxLength: 8), privacy: .public) ignoringModifiers=\(ignoringModifiers.vibewriteLogPreview(maxLength: 8), privacy: .public) modifiers=\(String(describing: modifierFlags), privacy: .public)"
            )
            return event
        }
        VibeWriteLog.launch.info("app delegate installed keyDown monitor")
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        VibeWriteLog.launch.info(
            "app delegate applicationShouldTerminate activeWindows=\(sender.windows.count, privacy: .public)"
        )
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        VibeWriteLog.launch.info("app delegate applicationWillTerminate")
    }
}
