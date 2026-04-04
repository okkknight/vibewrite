import AppKit
import XCTest

@MainActor
final class VibeWriteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBlankWritingShellOpensAndCanStartDraft() throws {
        let app = launchApplication(
            bundleIdentifier: "com.knightspace.vibewrite",
            launchArguments: [
                "--vibe-ai-mode=stub"
            ]
        )
        addUIInterruptionMonitor(withDescription: "Dismiss unexpected startup dialog") { dialog in
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
        window.click()

        let bodyEditor = window.textViews["project.bodyEditor"]
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

        let historyRailToggle = window.buttons["历史栏"]
        XCTAssertTrue(waitForElementToAppear(historyRailToggle, timeout: 10))

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

        let sendButton = window.descendants(matching: .any)
            .matching(identifier: "project.sendButton")
            .firstMatch
        XCTAssertTrue(waitForElementToAppear(sendButton, timeout: 10))

        messageInputField.click()
        messageInputField.typeText("Write about adult loneliness.")
        NSLog("phase: submitting first draft")
        messageInputField.typeKey(.return, modifierFlags: [])
        NSLog("phase: first draft submission event sent")

        NSLog("phase: waiting for first draft text to appear")
        XCTAssertTrue(waitForCondition(timeout: 12) {
            let currentBodyText = (bodyEditor.value as? String) ?? ""
            return !currentBodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }, "project.bodyEditor should populate after the first send")
        let firstDraftText = (bodyEditor.value as? String) ?? ""
        XCTAssertFalse(firstDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        NSLog("phase: waiting for request status to clear")
        XCTAssertTrue(waitForElementToDisappear(
            window.staticTexts["AI 正在写作"],
            timeout: 12
        ), "AI 正在写作 should disappear before the continue action")
        NSLog("phase: request status cleared")
        _ = currentSendButton(in: window)
        NSLog("phase: located continued draft send button")
        NSLog("phase: submitting continued draft")
        messageInputField.click()
        messageInputField.typeKey(.return, modifierFlags: [])
        NSLog("phase: continued draft submission event sent")

        NSLog("phase: waiting for continued draft status to clear")
        XCTAssertTrue(waitForElementToDisappear(
            window.staticTexts["正在续写下一段"],
            timeout: 12
        ), "正在续写下一段 should disappear after continuing the draft")
        NSLog("phase: continued draft status cleared")
        let continuedText = (bodyEditor.value as? String) ?? ""
        XCTAssertTrue(continuedText.count >= firstDraftText.count)

        assistantRailToggle.click()
        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.assistantRailShell",
            timeout: 10
        ))

        historyRailToggle.click()
        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.historyRailShell",
            timeout: 10
        ))

        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.aiSidebarSummary",
            timeout: 10
        ))

        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.aiSidebarConversation",
            timeout: 10
        ))

        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.historyDrawerContent",
            timeout: 10
        ))

        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.historyCurrentVersion",
            timeout: 10
        ))

        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.historyRecentSessions",
            timeout: 10
        ))

        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.historyRevisionList",
            timeout: 10
        ))

        let undoButton = window.descendants(matching: .any)
            .matching(identifier: "project.undoButton")
            .firstMatch
        XCTAssertTrue(waitForElementToAppear(undoButton, timeout: 10))
        XCTAssertTrue(waitForCondition(timeout: 10) {
            undoButton.isEnabled
        })

        let retryButton = window.descendants(matching: .any)
            .matching(identifier: "project.retrySectionButton")
            .firstMatch
        XCTAssertTrue(waitForElementToAppear(retryButton, timeout: 10))

        let compareButton = window.descendants(matching: .any)
            .matching(identifier: "project.compareButton")
            .firstMatch
        XCTAssertTrue(waitForElementToAppear(compareButton, timeout: 10))

        let comparePanel = window.descendants(matching: .any)
            .matching(identifier: "project.comparisonPanel")
            .firstMatch
        XCTAssertFalse(comparePanel.exists)

        compareButton.click()
        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.comparisonPanel",
            timeout: 10
        ))

        undoButton.click()
        NSLog("phase: waiting for undo to restore the first draft")
        XCTAssertTrue(waitForCondition(timeout: 12) {
            let currentBodyText = (bodyEditor.value as? String) ?? ""
            return currentBodyText != continuedText
        }, "project.bodyEditor should change after undo")
        let undoneText = (bodyEditor.value as? String) ?? ""
        XCTAssertEqual(undoneText, firstDraftText)
        XCTAssertTrue(waitForElementToDisappear(
            in: window,
            identifier: "project.comparisonPanel",
            timeout: 10
        ))

        XCTAssertTrue(waitForElementToAppear(window.staticTexts["我已经根据你的方向起了一版第一稿。"], timeout: 10))

        bodyEditor.click()
        bodyEditor.typeKey("a", modifierFlags: .command)

        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.editSelectionButton",
            timeout: 10
        ))

        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.selectionContinueButton",
            timeout: 10
        ))

        let selectionContinueButton = window.descendants(matching: .any)
            .matching(identifier: "project.selectionContinueButton")
            .firstMatch

        selectionContinueButton.click()
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
        window.click()

        let bodyEditor = window.textViews["project.bodyEditor"]
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

        let historyRailToggle = window.buttons["历史栏"]
        XCTAssertTrue(waitForElementToAppear(historyRailToggle, timeout: 10))
        historyRailToggle.click()

        XCTAssertTrue(waitForElementToAppear(
            in: window,
            identifier: "project.historyDrawerContent",
            timeout: 10
        ))
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
