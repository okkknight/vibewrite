import AppKit
import SwiftUI

final class VibeWriteUndoActionBox: ObservableObject {
    var perform: () -> Bool

    init(perform: @escaping () -> Bool) {
        self.perform = perform
    }
}

final class VibeWriteRedoActionBox: ObservableObject {
    var perform: () -> Bool

    init(perform: @escaping () -> Bool) {
        self.perform = perform
    }
}

struct VibeWriteCommands: Commands {
    @ObservedObject var flow: VibeWriteAppFlow
    @FocusedObject private var vibeWriteUndoActionBox: VibeWriteUndoActionBox?
    @FocusedObject private var vibeWriteRedoActionBox: VibeWriteRedoActionBox?

    @MainActor
    static func performNativeUndo(
        undoManagerProvider: @MainActor () -> UndoManager? = currentUndoManager
    ) -> Bool {
        guard let undoManager = undoManagerProvider(),
              undoManager.canUndo else {
            return false
        }

        undoManager.undo()
        return true
    }

    @MainActor
    static func performNativeRedo(
        undoManagerProvider: @MainActor () -> UndoManager? = currentUndoManager
    ) -> Bool {
        guard let undoManager = undoManagerProvider(),
              undoManager.canRedo else {
            return false
        }

        undoManager.redo()
        return true
    }

    private static func currentUndoManager() -> UndoManager? {
        if let keyResponder = NSApp.keyWindow?.firstResponder as? NSResponder,
           let undoManager = keyResponder.undoManager {
            return undoManager
        }

        if let mainResponder = NSApp.mainWindow?.firstResponder as? NSResponder,
           let undoManager = mainResponder.undoManager {
            return undoManager
        }

        if let keyUndoManager = NSApp.keyWindow?.undoManager {
            return keyUndoManager
        }

        return NSApp.mainWindow?.undoManager
    }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                VibeWriteLog.ai.info(
                    "command undo triggered activeCount=\(flow.activeDocumentText.count, privacy: .public) dirty=\(flow.isCurrentDocumentDirty, privacy: .public) revisionCount=\(flow.activeProject.revisionHistory.count, privacy: .public)"
                )
                let outcome = flow.handleUndoShortcut(
                    systemUndo: { Self.performNativeUndo() },
                    aiUndo: vibeWriteUndoActionBox.map { box in
                        { box.perform() }
                    }
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
                let outcome = flow.handleRedoShortcut(
                    systemRedo: { Self.performNativeRedo() },
                    aiRedo: vibeWriteRedoActionBox.map { box in
                        { box.perform() }
                    }
                )
                VibeWriteLog.ai.info(
                    "command redo resolved outcome=\(outcome.rawValue, privacy: .public) activeCount=\(flow.activeDocumentText.count, privacy: .public) revisionCount=\(flow.activeProject.revisionHistory.count, privacy: .public)"
                )
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
