import AppKit
import XCTest
@testable import VibeWriteApp

@MainActor
final class SelectableTextEditorTests: XCTestCase {
    func testLiveUserTextPreservationRequiresUncommittedText() {
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

        textView.setMarkedText(
            NSAttributedString(string: "typed draft"),
            selectedRange: NSRange(location: 11, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertTrue(coordinator.shouldPreserveLiveUserText(in: textView, bindingText: "loaded body"))
    }
}
