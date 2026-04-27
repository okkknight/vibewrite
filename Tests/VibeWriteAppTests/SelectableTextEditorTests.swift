import AppKit
import SwiftUI
import XCTest
@testable import VibeWriteApp

@MainActor
final class SelectableTextEditorTests: XCTestCase {
    func testViewportIntentResolvesFollowDocumentEndBeforeSelectionVisibility() {
        XCTAssertEqual(
            SelectableTextEditor.viewportIntent(
                didMutateText: false,
                shouldAutoScrollToDocumentEnd: true
            ),
            .followDocumentEnd
        )

        XCTAssertEqual(
            SelectableTextEditor.viewportIntent(
                didMutateText: true,
                shouldAutoScrollToDocumentEnd: true
            ),
            .followDocumentEnd
        )
    }

    func testViewportIntentPreservesSelectionOnlyAfterTextMutation() {
        XCTAssertEqual(
            SelectableTextEditor.viewportIntent(
                didMutateText: true,
                shouldAutoScrollToDocumentEnd: false
            ),
            .preserveSelectionVisibilityAfterTextMutation
        )
    }

    func testViewportIntentDefaultsToIdleOtherwise() {
        XCTAssertEqual(
            SelectableTextEditor.viewportIntent(
                didMutateText: false,
                shouldAutoScrollToDocumentEnd: false
            ),
            .idle
        )
    }

    func testLiveUserTextPreservationRequiresPendingUserTextChange() {
        let editor = SelectableTextEditor(
            text: .constant("loaded body"),
            selectedText: .constant(nil),
            selectedTextRange: .constant(nil),
            selectionPopoverOrigin: .constant(nil)
        )
        let coordinator = editor.makeCoordinator()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.isEditable = true
        textView.string = ""
        window.contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView?.addSubview(textView)
        _ = window.makeFirstResponder(textView)

        XCTAssertFalse(coordinator.shouldPreserveLiveUserText(in: textView, bindingText: "loaded body"))

        textView.string = "typed draft"
        coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: textView)
        )

        XCTAssertTrue(coordinator.shouldPreserveLiveUserText(in: textView, bindingText: "loaded body"))
    }

    func testBootstrapEmptyDelegateMutationDoesNotClearLoadedBinding() {
        final class Box {
            var value: String

            init(_ value: String) {
                self.value = value
            }
        }

        let box = Box("loaded body")
        let editor = SelectableTextEditor(
            text: Binding(
                get: { box.value },
                set: { box.value = $0 }
            ),
            selectedText: .constant(nil),
            selectedTextRange: .constant(nil),
            selectionPopoverOrigin: .constant(nil)
        )
        let coordinator = editor.makeCoordinator()

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.isEditable = true
        textView.string = ""

        coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: textView)
        )
        coordinator.textDidEndEditing(
            Notification(name: NSText.didEndEditingNotification, object: textView)
        )

        XCTAssertEqual(box.value, "loaded body")
    }

    func testTextDidEndEditingCommitsLiveTextToBinding() {
        final class Box {
            var value: String

            init(_ value: String) {
                self.value = value
            }
        }

        let box = Box("loaded body")
        let editor = SelectableTextEditor(
            text: Binding(
                get: { box.value },
                set: { box.value = $0 }
            ),
            selectedText: .constant(nil),
            selectedTextRange: .constant(nil),
            selectionPopoverOrigin: .constant(nil)
        )
        let coordinator = editor.makeCoordinator()

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.isEditable = true
        textView.string = "typed draft"

        coordinator.textDidEndEditing(
            Notification(name: NSText.didEndEditingNotification, object: textView)
        )

        XCTAssertEqual(box.value, "typed draft")
    }

    func testLiveTextMutationCommitsShorterTextToBinding() {
        final class Box {
            var value: String

            init(_ value: String) {
                self.value = value
            }
        }

        let box = Box("loaded body")
        let editor = SelectableTextEditor(
            text: Binding(
                get: { box.value },
                set: { box.value = $0 }
            ),
            selectedText: .constant(nil),
            selectedTextRange: .constant(nil),
            selectionPopoverOrigin: .constant(nil)
        )
        let coordinator = editor.makeCoordinator()

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.isEditable = true
        textView.string = "loaded bod"

        coordinator.handleLiveTextMutation(
            from: textView,
            source: "doCommand(deleteBackward:)"
        )

        XCTAssertEqual(box.value, "loaded bod")
    }

    func testLiveTextMutationCommitsDeletionToEmptyBinding() {
        final class Box {
            var value: String

            init(_ value: String) {
                self.value = value
            }
        }

        let box = Box("loaded body")
        let editor = SelectableTextEditor(
            text: Binding(
                get: { box.value },
                set: { box.value = $0 }
            ),
            selectedText: .constant(nil),
            selectedTextRange: .constant(nil),
            selectionPopoverOrigin: .constant(nil)
        )
        let coordinator = editor.makeCoordinator()

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.isEditable = true
        textView.string = ""

        coordinator.handleLiveTextMutation(
            from: textView,
            source: "doCommand(deleteBackward:)"
        )

        XCTAssertEqual(box.value, "")
    }

    func testSelectionChangeStagesPendingTextBeforeTextDidChangeForCutLikeMutation() {
        final class Box {
            var value: String

            init(_ value: String) {
                self.value = value
            }
        }

        let box = Box("abcdef")
        let editor = SelectableTextEditor(
            text: Binding(
                get: { box.value },
                set: { box.value = $0 }
            ),
            selectedText: .constant(nil),
            selectedTextRange: .constant(nil),
            selectionPopoverOrigin: .constant(nil)
        )
        let coordinator = editor.makeCoordinator()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = StyledTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.isEditable = true
        textView.isSelectable = true
        textView.string = "abcdef"
        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.documentView = textView
        window.contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView?.addSubview(scrollView)
        coordinator.installObservers(for: scrollView, textView: textView)
        _ = window.makeFirstResponder(textView)

        textView.string = "abef"
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        NotificationCenter.default.post(
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )

        XCTAssertTrue(coordinator.shouldPreserveLiveUserText(in: textView, bindingText: box.value))

        coordinator.syncLiveUserTextFromView(textView)

        XCTAssertEqual(box.value, "abef")
    }

    func testProgrammaticSyncPreservesNonEmptySelectionAcrossReplacement() {
        let editor = SelectableTextEditor(
            text: .constant(""),
            selectedText: .constant(nil),
            selectedTextRange: .constant(nil),
            selectionPopoverOrigin: .constant(nil)
        )
        let coordinator = editor.makeCoordinator()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = StyledTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.isEditable = true
        textView.isSelectable = true
        textView.string = "abcdef"
        textView.setSelectedRange(NSRange(location: 2, length: 2))
        window.contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView?.addSubview(textView)
        _ = window.makeFirstResponder(textView)

        XCTAssertTrue(coordinator.syncText("abZef", in: textView))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 1))
    }

    func testProgrammaticSyncClearsBodyUndoHistory() {
        let editor = SelectableTextEditor(
            text: .constant(""),
            selectedText: .constant(nil),
            selectedTextRange: .constant(nil),
            selectionPopoverOrigin: .constant(nil)
        )
        let coordinator = editor.makeCoordinator()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = StyledTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.allowsUndo = true
        window.contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView?.addSubview(textView)
        _ = window.makeFirstResponder(textView)

        textView.insertText("手输", replacementRange: textView.selectedRange())
        textView.undoManager?.undo()
        textView.undoManager?.redo()
        XCTAssertTrue(textView.undoManager?.canUndo == true)

        XCTAssertTrue(coordinator.syncText("第一段\n\n第二段", in: textView))
        XCTAssertFalse(textView.undoManager?.canUndo == true)
        XCTAssertFalse(textView.undoManager?.canRedo == true)
    }

    func testUserEditAfterProgrammaticSyncRemainsUndoableWithoutStaleUndoEntries() {
        let editor = SelectableTextEditor(
            text: .constant(""),
            selectedText: .constant(nil),
            selectedTextRange: .constant(nil),
            selectionPopoverOrigin: .constant(nil)
        )
        let coordinator = editor.makeCoordinator()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = StyledTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.allowsUndo = true
        window.contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView?.addSubview(textView)
        _ = window.makeFirstResponder(textView)

        XCTAssertTrue(coordinator.syncText("第一段\n\n第二段", in: textView))
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertText("补字", replacementRange: textView.selectedRange())

        XCTAssertTrue(textView.undoManager?.canUndo == true)
        textView.undoManager?.undo()

        XCTAssertEqual(textView.string, "第一段\n\n第二段")
        XCTAssertFalse(textView.undoManager?.canUndo == true)
    }
}
