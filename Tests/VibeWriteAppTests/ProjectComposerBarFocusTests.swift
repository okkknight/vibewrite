import AppKit
import SwiftUI
import XCTest
@testable import VibeWriteApp

@MainActor
final class ProjectComposerBarFocusTests: XCTestCase {
    func testComposerKeepsFocusAfterTypingFirstCharacter() {
        _ = VibeWriteDebugTrace.drain()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))

        let hostingView = NSHostingView(
            rootView: ComposerFocusHarnessView()
        )
        hostingView.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)

        pumpRunLoop(for: 0.2)

        guard let textView = findFirstTextView(in: window.contentView) else {
            let traces = VibeWriteDebugTrace.drain()
            XCTFail("Could not find composer text view. Traces:\n\(traces.joined(separator: "\n"))")
            return
        }

        _ = window.makeFirstResponder(textView)
        pumpRunLoop(for: 0.1)

        textView.insertText("a", replacementRange: NSRange(location: NSNotFound, length: 0))
        pumpRunLoop(for: 0.2)

        let traces = VibeWriteDebugTrace.drain()
        print(traces.joined(separator: "\n"))

        XCTAssertTrue(
            window.firstResponder === textView,
            "Composer lost focus after the first typed character. Traces:\n\(traces.joined(separator: "\n"))"
        )
    }

    func testComposerTakesFocusAfterAssistantSuggestionTapEvenWhenBodyEditorIsFocused() {
        _ = VibeWriteDebugTrace.drain()

        var focusState = true
        var transitions: [Bool] = []

        requestComposerFocusAfterSuggestionTap(setMessageFieldFocused: { newValue in
            focusState = newValue
            transitions.append(newValue)
        })
        XCTAssertEqual(transitions, [false])

        pumpRunLoop(for: 0.1)

        let traces = VibeWriteDebugTrace.drain()
        print(traces.joined(separator: "\n"))

        XCTAssertEqual(transitions, [false, true], "Suggestion tap did not re-request composer focus. Traces:\n\(traces.joined(separator: "\n"))")
        XCTAssertTrue(focusState, "Suggestion tap did not leave the composer focus requested. Traces:\n\(traces.joined(separator: "\n"))")
    }
}

@MainActor
private struct ComposerFocusHarnessView: View {
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        ProjectComposerBar(
            messageDraft: $draft,
            appearanceMode: .day,
            primaryActionTitle: "开场",
            messageFieldPlaceholder: "写一个地狱爱情故事",
            showsAssistantSuggestions: true,
            assistantSuggestionChips: [
                "写一个具体工具：手机备忘录、口袋本或语音备忘，立即开始实践",
                "设计个人系统的迭代方式：根据使用习惯调整工具和记录方式",
                "从今天起记录灵感到来时刻：时间、地点、状态、观察规律"
            ],
            isComposerLocked: false,
            isRequestInFlight: false,
            isPrimaryOutputInFlight: false,
            isPrimaryActionInFlight: false,
            isSuggestionGenerationInFlight: false,
            messageFieldFocused: $focused,
            isMessageFieldHighlighted: focused,
            accessibilityIdentifier: "composer-bar",
            messageInputIdentifier: "composer-input",
            sendButtonIdentifier: "composer-submit",
            onSubmit: {},
            onAssistantSuggestionTap: { _ in }
        )
        .frame(width: 720, height: 260)
        .onAppear {
            focused = true
        }
    }
}

@MainActor
private func findFirstTextView(in view: NSView?) -> NSTextView? {
    guard let view else { return nil }

    if let textView = view as? NSTextView {
        return textView
    }

    for subview in view.subviews {
        if let textView = findFirstTextView(in: subview) {
            return textView
        }
    }

    return nil
}

@MainActor
private func findTextView(in view: NSView?, identifier: String) -> NSTextView? {
    guard let view else { return nil }

    if let textView = view as? NSTextView,
       textView.identifier?.rawValue == identifier {
        return textView
    }

    for subview in view.subviews {
        if let textView = findTextView(in: subview, identifier: identifier) {
            return textView
        }
    }

    return nil
}

@MainActor
private func findComposerTextView(in view: NSView?) -> NSTextView? {
    guard let view else { return nil }

    var candidateTextViews: [NSTextView] = []

    func collectTextViews(in nestedView: NSView?) {
        guard let nestedView else { return }

        if let textView = nestedView as? NSTextView {
            candidateTextViews.append(textView)
        }

        for subview in nestedView.subviews {
            collectTextViews(in: subview)
        }
    }

    collectTextViews(in: view)
    return candidateTextViews.last
}

@MainActor
private func findButton(in view: NSView?, titleContaining text: String) -> NSButton? {
    guard let view else { return nil }

    if let button = view as? NSButton, button.title.contains(text) {
        return button
    }

    for subview in view.subviews {
        if let button = findButton(in: subview, titleContaining: text) {
            return button
        }
    }

    return nil
}

@MainActor
private func dumpViewTree(_ view: NSView?, depth: Int = 0, maxDepth: Int = 6) -> [String] {
    guard let view else { return [] }

    let indent = String(repeating: "  ", count: depth)
    let label: String
    if let button = view as? NSButton {
        label = " title=\(button.title)"
    } else if let control = view as? NSControl {
        let controlLabel = control.accessibilityLabel() ?? "nil"
        label = " label=\(controlLabel)"
    } else {
        label = ""
    }

    var lines = ["\(indent)\(type(of: view))\(label)"]
    guard depth < maxDepth else { return lines }

    for subview in view.subviews {
        lines.append(contentsOf: dumpViewTree(subview, depth: depth + 1, maxDepth: maxDepth))
    }

    return lines
}

private func pumpRunLoop(for seconds: TimeInterval) {
    let endDate = Date().addingTimeInterval(seconds)
    while Date() < endDate {
        RunLoop.main.run(mode: .default, before: endDate)
    }
}
