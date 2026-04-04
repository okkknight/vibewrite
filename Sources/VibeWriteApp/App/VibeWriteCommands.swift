import SwiftUI

struct VibeWriteCommands: Commands {
    @ObservedObject var flow: VibeWriteAppFlow

    var body: some Commands {
        CommandMenu("File") {
            Button("New") {
                flow.createNewProject()
            }
            .keyboardShortcut("n")

            Button("Open...") {
                _ = flow.openDocumentFromPanel()
            }
            .keyboardShortcut("o")

            Button("Save") {
                _ = flow.saveCurrentDocument()
            }
            .keyboardShortcut("s")

            Button("Save As...") {
                _ = flow.saveCurrentDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            if !flow.recentDocumentEntries.isEmpty {
                Divider()

                Menu("Open Recent") {
                    ForEach(flow.recentDocumentEntries) { entry in
                        Button(entry.displayName) {
                            _ = flow.openRecentDocument(entry)
                        }
                    }
                }
            }
        }
    }
}
