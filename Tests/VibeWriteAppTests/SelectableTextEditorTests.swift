import AppKit
import SwiftUI
import XCTest
@testable import VibeWriteApp

@MainActor
final class SelectableTextEditorTests: XCTestCase {
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
}
