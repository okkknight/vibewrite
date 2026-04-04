import SwiftUI

@main
struct VibeWriteApp: App {
    @StateObject private var flow: VibeWriteAppFlow

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
        .commands {
            VibeWriteCommands(flow: flow)
        }
    }
}
