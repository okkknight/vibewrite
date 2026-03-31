import XCTest

@MainActor
final class VibeWriteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDiscussionStartDraftButtonIsUniqueAndStartsDraft() throws {
        let app = XCUIApplication(bundleIdentifier: "com.knightspace.vibewrite")
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibewrite-ui-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        app.launchEnvironment["VIBEWRITE_STORAGE_URL"] = storageURL.path
        app.launchEnvironment["VIBEWRITE_AI_MODE"] = "stub"
        app.launch()

        let discussionStartButton = app.buttons["home.discussionStartButton"]
        XCTAssertTrue(discussionStartButton.waitForExistence(timeout: 5))
        discussionStartButton.click()

        let startDraftButtons = app.buttons.matching(identifier: "project.startDraftButton")
        XCTAssertEqual(startDraftButtons.count, 1)

        let startDraftButton = startDraftButtons.firstMatch
        XCTAssertTrue(startDraftButton.waitForExistence(timeout: 5))
        startDraftButton.click()

        XCTAssertTrue(app.buttons["project.backButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["project.bodyEditor"].waitForExistence(timeout: 5))
    }
}
