import AppKit
import SwiftUI

struct VibeWriteCommands: Commands {
    @ObservedObject var flow: VibeWriteAppFlow
    @FocusedValue(\.vibeWriteUndoAction) private var vibeWriteUndoAction

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                VibeWriteLog.ai.info(
                    "command undo triggered activeCount=\(flow.activeDocumentText.count, privacy: .public) dirty=\(flow.isCurrentDocumentDirty, privacy: .public) revisionCount=\(flow.activeProject.revisionHistory.count, privacy: .public)"
                )
                let outcome = flow.handleUndoShortcut(
                    systemUndo: { NSApp.sendAction(#selector(UndoManager.undo), to: nil, from: nil) },
                    aiUndo: vibeWriteUndoAction
                )
                VibeWriteLog.ai.info(
                    "command undo resolved outcome=\(outcome.rawValue, privacy: .public) activeCount=\(flow.activeDocumentText.count, privacy: .public) revisionCount=\(flow.activeProject.revisionHistory.count, privacy: .public)"
                )
            }
            .keyboardShortcut("z")

            Button("Redo") {
                VibeWriteLog.ai.info(
                    "command redo triggered activeCount=\(flow.activeDocumentText.count, privacy: .public) dirty=\(flow.isCurrentDocumentDirty, privacy: .public)"
                )
                _ = NSApp.sendAction(#selector(UndoManager.redo), to: nil, from: nil)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .newItem) {
            Button("New") {
                VibeWriteLog.ai.info(
                    "command new triggered activeCount=\(flow.activeDocumentText.count, privacy: .public) dirty=\(flow.isCurrentDocumentDirty, privacy: .public)"
                )
                flow.createNewProject()
            }
            .keyboardShortcut("n")
        }

        CommandGroup(after: .newItem) {
            Button("Open...") {
                VibeWriteLog.ai.info(
                    "command open triggered activeCount=\(flow.activeDocumentText.count, privacy: .public) dirty=\(flow.isCurrentDocumentDirty, privacy: .public)"
                )
                _ = flow.openDocumentFromPanel()
            }
            .keyboardShortcut("o")

            Button("Save") {
                VibeWriteLog.ai.info(
                    "command save triggered activeCount=\(flow.activeDocumentText.count, privacy: .public) dirty=\(flow.isCurrentDocumentDirty, privacy: .public) currentURL=\(flow.currentDocumentURL?.lastPathComponent ?? "nil", privacy: .public)"
                )
                _ = flow.saveCurrentDocument()
            }
            .keyboardShortcut("s")

            Button("Save As...") {
                VibeWriteLog.ai.info(
                    "command saveAs triggered activeCount=\(flow.activeDocumentText.count, privacy: .public) dirty=\(flow.isCurrentDocumentDirty, privacy: .public) currentURL=\(flow.currentDocumentURL?.lastPathComponent ?? "nil", privacy: .public)"
                )
                _ = flow.saveCurrentDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            if !flow.recentDocumentEntries.isEmpty {
                Divider()

                Menu("Open Recent") {
                    ForEach(flow.recentDocumentEntries) { entry in
                        Button(entry.displayName) {
                            VibeWriteLog.ai.info(
                                "command openRecent triggered title=\(entry.title.vibewriteLogPreview(maxLength: 60), privacy: .public) url=\(entry.url.lastPathComponent, privacy: .public)"
                            )
                            _ = flow.openRecentDocument(entry)
                        }
                    }
                }
            }
        }
    }
}
