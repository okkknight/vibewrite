import AppKit
import XCTest

@MainActor
final class VibeWriteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBlankWritingShellOpensAndShowsCoreChrome() throws {
        let app = launchApplication(
            bundleIdentifier: "com.knightspace.vibewrite",
            launchArguments: [
                "--vibe-ai-mode=stub"
            ]
        )
        addUIInterruptionMonitor(withDescription: "Dismiss unexpected startup dialog") { dialog in
            if dialog.frame.height < 80 {
                return false
            }

            for label in ["Allow", "OK", "Continue", "取消", "Cancel", "Not Now", "不要", "Don't Allow"] {
                let button = dialog.buttons[label]
                if button.exists {
                    button.click()
                    return true
                }
            }

            if let firstButton = dialog.buttons.allElementsBoundByIndex.first {
                firstButton.click()
                return true
            }

            return false
        }

        let window = app.windows.firstMatch
        XCTAssertTrue(waitForElementToAppear(window, timeout: 15))
        app.activate()
        window.click()

        let bodyEditor = window.textViews.firstMatch
        XCTAssertTrue(waitForElementToAppear(bodyEditor, timeout: 10))

        let paperShell = window.descendants(matching: .any)
            .matching(identifier: "project.paperShell")
            .firstMatch
        XCTAssertTrue(waitForElementToAppear(paperShell, timeout: 10))

        let messageInputField = window.descendants(matching: .any)
            .matching(identifier: "project.messageInput")
            .firstMatch
        XCTAssertTrue(waitForElementToAppear(messageInputField, timeout: 10))

        let assistantRailToggle = window.buttons["AI 侧栏"]
        XCTAssertTrue(waitForElementToAppear(assistantRailToggle, timeout: 10), "assistant rail toggle should appear")

        let assistantRailShell = window.descendants(matching: .any)
            .matching(identifier: "project.assistantRailShell")
            .firstMatch
        XCTAssertFalse(assistantRailShell.exists)

        let historyRailShell = window.descendants(matching: .any)
            .matching(identifier: "project.historyRailShell")
            .firstMatch
        XCTAssertFalse(historyRailShell.exists)

        let historyDrawerContent = window.descendants(matching: .any)
            .matching(identifier: "project.historyDrawerContent")
            .firstMatch
        XCTAssertFalse(historyDrawerContent.exists)
        let historyRailToggle = window.buttons["历史栏"]
        XCTAssertFalse(historyRailToggle.exists)

        let sendButton = window.descendants(matching: .any)
            .matching(identifier: "project.sendButton")
            .firstMatch
        XCTAssertTrue(waitForElementToAppear(sendButton, timeout: 10))
    }

    func testSelectionPopoverShowsPresetOptionsAndTriggersLocalEdit() throws {
        throw XCTSkip("Temporarily disabled because this selection-flow UI test still risks opening a system file panel and stealing focus.")
    }

    func testCompactLayoutShowsSidebarDrawers() throws {
        let app = launchApplication(
            bundleIdentifier: "com.knightspace.vibewrite",
            launchArguments: [
                "--vibe-ai-mode=stub",
                "--force-compact-layout"
            ]
        )
        addUIInterruptionMonitor(withDescription: "Dismiss unexpected startup dialog") { dialog in
            if dialog.frame.height < 80 {
                return false
            }

            for label in ["Allow", "OK", "Continue", "取消", "Cancel", "Not Now", "不要", "Don't Allow"] {
                let button = dialog.buttons[label]
                if button.exists {
                    button.click()
                    return true
                }
            }

            if let firstButton = dialog.buttons.allElementsBoundByIndex.first {
                firstButton.click()
                return true
            }

            return false
        }

        let window = app.windows.firstMatch
        XCTAssertTrue(waitForElementToAppear(window, timeout: 15))
        app.activate()
        window.click()

        let bodyEditor = window.textViews.firstMatch
        XCTAssertTrue(waitForElementToAppear(bodyEditor, timeout: 10))

        let messageInputField = window.descendants(matching: .any)
            .matching(identifier: "project.messageInput")
            .firstMatch
        XCTAssertTrue(waitForElementToAppear(messageInputField, timeout: 10))

        let assistantRailToggle = window.buttons["AI 侧栏"]
        XCTAssertTrue(waitForElementToAppear(assistantRailToggle, timeout: 10))
        assistantRailToggle.click()

        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.aiSidebarContent",
            timeout: 10
        ))

        XCTAssertFalse(window.buttons["历史栏"].exists)
        XCTAssertFalse(currentElement(in: window, identifier: "project.historyDrawerContent").exists)
    }

    private func waitForElementToAppear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return element.exists
    }

    private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return !element.exists
    }

    private func waitForElementToAppear(
        in window: XCUIElement,
        identifier: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if currentElement(in: window, identifier: identifier).exists {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return currentElement(in: window, identifier: identifier).exists
    }

    private func waitForElementToDisappear(
        in window: XCUIElement,
        identifier: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !currentElement(in: window, identifier: identifier).exists {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return !currentElement(in: window, identifier: identifier).exists
    }

    private func currentElement(in window: XCUIElement, identifier: String) -> XCUIElement {
        window.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    private func currentSendButton(in window: XCUIElement) -> XCUIElement {
        currentElement(in: window, identifier: "project.sendButton")
    }

    private func waitForCondition(timeout: TimeInterval, predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return predicate()
    }

    private func terminateAppIfRunning(bundleIdentifier: String) {
        func runningApps() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        }

        for runningApp in runningApps() {
            runningApp.terminate()
        }

        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let activeApps = runningApps()
            if activeApps.isEmpty {
                return
            }

            for runningApp in activeApps {
                runningApp.forceTerminate()
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func launchApplication(
        bundleIdentifier: String,
        launchArguments: [String]
    ) -> XCUIApplication {
        terminateAppIfRunning(bundleIdentifier: bundleIdentifier)

        let app = XCUIApplication()
        app.launchArguments = launchArguments
        app.launchEnvironment = [
            "ApplePersistenceIgnoreState": "YES",
            "VIBEWRITE_AI_MODE": "stub",
            "VIBEWRITE_UI_TEST_RESET_STORAGE": "1"
        ]
        // Disable XCTest's extra idle-animation waiting so post-submit polling stays in control.
        app.setValue(false, forKey: "idleAnimationWaitEnabled")
        app.launch()

        return app
    }

}
