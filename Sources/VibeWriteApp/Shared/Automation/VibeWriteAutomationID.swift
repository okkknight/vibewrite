import Foundation

enum VibeWriteAutomationID {
    static let homeCreateNewProjectButton = "home.createNewProjectButton"
    static let homeDirectStartButton = "home.directStartButton"
    static let homeDiscussionStartButton = "home.discussionStartButton"

    static func homeRecentProjectCard(_ projectKey: String) -> String {
        "home.recentProjectCard.\(projectKey)"
    }

    static let projectBackButton = "project.backButton"
    static let projectTitle = "project.title"
    static let projectStatusBadge = "project.statusBadge"
    static let projectBodyEditor = "project.bodyEditor"
    static let projectMessageInput = "project.messageInput"
    static let projectSendButton = "project.sendButton"
    static let projectUndoButton = "project.undoButton"
    static let projectCompareButton = "project.compareButton"
    static let projectRetrySectionButton = "project.retrySectionButton"
    static let projectStartDraftButton = "project.startDraftButton"
    static let projectSelectionModifyButton = "project.selectionModifyButton"
    static let projectSelectionExpandButton = "project.selectionExpandButton"
    static let projectSelectionCondenseButton = "project.selectionCondenseButton"
    static let projectSelectionPolishButton = "project.selectionPolishButton"
}
