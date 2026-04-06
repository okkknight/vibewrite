import AppKit
import SwiftUI

struct WritingLocalEditFlash: Equatable, Hashable {
    let id: UUID
    let range: WritingTextSelectionRange

    init(id: UUID = UUID(), range: WritingTextSelectionRange) {
        self.id = id
        self.range = range
    }
}

@MainActor
struct SelectableTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String?
    @Binding var selectedTextRange: WritingTextSelectionRange?
    @Binding var selectionPopoverOrigin: CGPoint?
    var isEditable: Bool = true
    var accessibilityIdentifier: String?
    var shouldAutoScrollToDocumentEnd: Bool = false
    var textFont: NSFont = .systemFont(ofSize: 21, weight: .regular)
    var textColor: NSColor = .labelColor
    var insertionPointColor: NSColor = .vibeAccent
    var selectedTextBackgroundColor: NSColor = NSColor.vibeAccent.withAlphaComponent(0.22)
    var textContainerInset: NSSize = NSSize(width: 18, height: 18)
    var localEditFlash: WritingLocalEditFlash?
    var isViewportLockedDuringLocalEdit: Bool = false
    var shouldPreserveSelectionOverlayDuringPendingLocalEdit: Bool = false
    var onScrollViewReady: ((NSScrollView) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            selectedText: $selectedText,
            selectedTextRange: $selectedTextRange,
            selectionPopoverOrigin: $selectionPopoverOrigin
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = StyledTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = textColor
        textView.insertionPointColor = insertionPointColor
        textView.font = textFont
        textView.typingAttributes = Coordinator.presentationAttributes(
            font: textFont,
            textColor: textColor
        )
        textView.selectedTextAttributes = [
            .backgroundColor: selectedTextBackgroundColor
        ]
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindBar = false
        textView.postsFrameChangedNotifications = true
        textView.textContainerInset = textContainerInset
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.identifier = accessibilityIdentifier.map { NSUserInterfaceItemIdentifier($0) }
        textView.setAccessibilityValue(textView.string as NSString)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.installObservers(for: scrollView, textView: textView)
        context.coordinator.syncTypography(
            isEditable: isEditable,
            font: textFont,
            textColor: textColor,
            insertionPointColor: insertionPointColor,
            selectedTextBackgroundColor: selectedTextBackgroundColor,
            in: textView
        )
        _ = context.coordinator.syncText(text, in: textView)
        context.coordinator.syncSelectionOverlayState(from: textView)

        return scrollView
    }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? NSTextView else {
                return
            }

        context.coordinator.logTextEvent(
            "update nsview start bindingCount=\(text.utf16.count) textViewCount=\(textView.string.utf16.count) selection=\(context.coordinator.debugRange(textView.selectedRange())) editable=\(textView.isEditable)"
        )
        context.coordinator.textView = textView
        context.coordinator.setSelectionOverlayPreservationDuringPendingLocalEdit(
            shouldPreserveSelectionOverlayDuringPendingLocalEdit
        )
        context.coordinator.syncTypography(
            isEditable: isEditable,
            font: textFont,
            textColor: textColor,
            insertionPointColor: insertionPointColor,
            selectedTextBackgroundColor: selectedTextBackgroundColor,
            in: textView
        )
        let didMutateText: Bool
        if context.coordinator.shouldPreserveLiveUserText(in: textView, bindingText: text) {
            context.coordinator.syncLiveUserTextFromView(textView)
            didMutateText = false
        } else {
            didMutateText = context.coordinator.syncText(text, in: textView)
        }
        context.coordinator.syncAccessibilityValue(in: textView)
        context.coordinator.syncLayout(
            in: textView,
            scrollView: scrollView,
            prefersSelectionVisibility: didMutateText == false,
            shouldAutoScrollToDocumentEnd: shouldAutoScrollToDocumentEnd,
            isViewportLockedDuringLocalEdit: isViewportLockedDuringLocalEdit
        )
        context.coordinator.reportScrollViewIfNeeded(scrollView, onScrollViewReady: onScrollViewReady)
        if didMutateText {
            context.coordinator.syncSelectionOverlayState(from: textView)
        }
        if didMutateText {
            context.coordinator.ensureReadableTextAttributes(in: textView)
        }
        context.coordinator.syncLocalEditFlash(
            localEditFlash,
            in: textView,
            scrollView: scrollView
        )
        context.coordinator.logTextEvent(
            "update nsview end bindingCount=\(text.utf16.count) textViewCount=\(textView.string.utf16.count) didMutateText=\(didMutateText) selection=\(context.coordinator.debugRange(textView.selectedRange()))"
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var selectedText: String?
        @Binding private var selectedTextRange: WritingTextSelectionRange?
        @Binding private var selectionPopoverOrigin: CGPoint?
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        weak var reportedScrollView: NSScrollView?
        private var programmaticChangeDepth = 0
        private var lastAppliedIsEditable: Bool?
        private var lastAppliedFont: NSFont?
        private var lastAppliedTextColor: NSColor?
        private var lastAppliedInsertionPointColor: NSColor?
        private var lastAppliedSelectedTextBackgroundColor: NSColor?
        private var lastAppliedAccessibilityValue: String?
        private var needsFullTextRestyle = false
        private var lastLoggedLayoutSignature: String?
        private var isPerformingLayoutSync = false
        private var pendingTextBindingUpdateAfterLayoutSync: String?
        private var pendingUserTextChange: String?
        private var selectionOverlayUpdateGeneration = 0
        private var needsSelectionOverlaySyncAfterLayout = false
        private var lockedViewportOrigin: CGPoint?
        private var lastAppliedLocalEditFlashID: UUID?
        private weak var localEditFlashOverlayView: LocalEditFlashOverlayView?
        private var shouldPreserveSelectionOverlayDuringPendingLocalEdit = false

        private var isApplyingProgrammaticChange: Bool {
            programmaticChangeDepth > 0
        }

        init(
            text: Binding<String>,
            selectedText: Binding<String?>,
            selectedTextRange: Binding<WritingTextSelectionRange?>,
            selectionPopoverOrigin: Binding<CGPoint?>
        ) {
            _text = text
            _selectedText = selectedText
            _selectedTextRange = selectedTextRange
            _selectionPopoverOrigin = selectionPopoverOrigin
        }

        func setSelectionOverlayPreservationDuringPendingLocalEdit(_ shouldPreserve: Bool) {
            shouldPreserveSelectionOverlayDuringPendingLocalEdit = shouldPreserve
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func installObservers(for scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            NotificationCenter.default.removeObserver(self)
            ensureLocalEditFlashOverlay(in: scrollView, textView: textView)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScrollViewBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleTextViewSelectionDidChange(_:)),
                name: NSTextView.didChangeSelectionNotification,
                object: textView
            )
        }

        func reportScrollViewIfNeeded(
            _ scrollView: NSScrollView,
            onScrollViewReady: ((NSScrollView) -> Void)?
        ) {
            guard reportedScrollView !== scrollView else { return }
            reportedScrollView = scrollView
            guard let onScrollViewReady else { return }
            DispatchQueue.main.async {
                onScrollViewReady(scrollView)
            }
        }

        @objc
        private func handleScrollViewBoundsDidChange(_ notification: Notification) {
            guard let scrollView,
                  let textView else { return }

            if !isPerformingLayoutSync {
                lockedViewportOrigin = nil
            }

            syncLayout(
                in: textView,
                scrollView: scrollView,
                prefersSelectionVisibility: false,
                shouldAutoScrollToDocumentEnd: false,
                isViewportLockedDuringLocalEdit: false
            )
            syncSelectionOverlayState(from: textView)
            logSelectionEvent("scroll bounds changed selection=\(debugRange(textView.selectedRange())) origin=\(debugPoint(selectionPopoverOrigin))")
        }

        @objc
        private func handleTextViewSelectionDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            guard !isApplyingProgrammaticChange else { return }

            if !isPerformingLayoutSync {
                lockedViewportOrigin = nil
            }

            if isPerformingLayoutSync {
                needsSelectionOverlaySyncAfterLayout = true
                logSelectionEvent("selection change deferred during layout selection=\(debugRange(textView.selectedRange())) editable=\(textView.isEditable)")
                return
            }

            logSelectionEvent("selection notification changed selection=\(debugRange(textView.selectedRange())) editable=\(textView.isEditable)")
            syncSelectionOverlayState(from: textView)
        }

        func syncTypography(
            isEditable: Bool,
            font: NSFont,
            textColor: NSColor,
            insertionPointColor: NSColor,
            selectedTextBackgroundColor: NSColor,
            in textView: NSTextView
        ) {
            if lastAppliedIsEditable != isEditable {
                textView.isEditable = isEditable
                lastAppliedIsEditable = isEditable
            }

            if lastAppliedFont == nil || !(lastAppliedFont?.isEqual(font) ?? false) {
                textView.font = font
                textView.typingAttributes = Self.presentationAttributes(font: font, textColor: textColor)
                lastAppliedFont = font
                needsFullTextRestyle = true
            }

            if lastAppliedTextColor == nil || !(lastAppliedTextColor?.isEqual(textColor) ?? false) {
                textView.textColor = textColor
                textView.typingAttributes = Self.presentationAttributes(font: font, textColor: textColor)
                lastAppliedTextColor = textColor
                needsFullTextRestyle = true
            }

            if lastAppliedInsertionPointColor == nil || !(lastAppliedInsertionPointColor?.isEqual(insertionPointColor) ?? false) {
                textView.insertionPointColor = insertionPointColor
                lastAppliedInsertionPointColor = insertionPointColor
            }

            if lastAppliedSelectedTextBackgroundColor == nil || !(lastAppliedSelectedTextBackgroundColor?.isEqual(selectedTextBackgroundColor) ?? false) {
                textView.selectedTextAttributes = [
                    .backgroundColor: selectedTextBackgroundColor
                ]
                lastAppliedSelectedTextBackgroundColor = selectedTextBackgroundColor
            }
        }

        func ensureReadableTextAttributes(in textView: NSTextView) {
            guard needsFullTextRestyle else { return }
            guard let textStorage = textView.textStorage else {
                needsFullTextRestyle = false
                return
            }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else {
                needsFullTextRestyle = false
                return
            }

            textStorage.beginEditing()
            textStorage.setAttributes(Self.presentationAttributes(font: lastAppliedFont ?? textView.font ?? .systemFont(ofSize: 21, weight: .regular), textColor: lastAppliedTextColor ?? textView.textColor ?? .labelColor), range: fullRange)
            textStorage.endEditing()
            needsFullTextRestyle = false
        }

        static func presentationAttributes(font: NSFont, textColor: NSColor) -> [NSAttributedString.Key: Any] {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 6
            paragraphStyle.paragraphSpacing = 14

            return [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
        }

        func syncText(_ newText: String, in textView: NSTextView) -> Bool {
            if let pendingTextBindingUpdateAfterLayoutSync,
               pendingTextBindingUpdateAfterLayoutSync != newText {
                logTextEvent(
                    "sync text skipped pending user edit pendingCount=\(pendingTextBindingUpdateAfterLayoutSync.utf16.count) requestedCount=\(newText.utf16.count) applyingProgrammatic=\(isApplyingProgrammaticChange) layoutSync=\(isPerformingLayoutSync)"
                )
                return false
            }

            logTextEvent(
                "sync text start currentCount=\(textView.string.utf16.count) requestedCount=\(newText.utf16.count) applyingProgrammatic=\(isApplyingProgrammaticChange) layoutSync=\(isPerformingLayoutSync)"
            )
            guard textView.string != newText else {
                logTextEvent("sync text skipped identical requestedCount=\(newText.utf16.count)")
                if pendingUserTextChange == newText {
                    pendingUserTextChange = nil
                }
                lastAppliedAccessibilityValue = newText
                return false
            }

            beginProgrammaticChange()
            defer {
                endProgrammaticChange()
            }

            let oldText = textView.string as NSString
            let newTextString = newText as NSString
            let existingSelection = textView.selectedRange()

            if let textStorage = textView.textStorage {
                let prefixLength = commonPrefixLength(between: oldText, and: newTextString)
                let suffixLength = commonSuffixLength(
                    between: oldText,
                    and: newTextString,
                    prefixLength: prefixLength
                )
                let oldMiddleLength = max(oldText.length - prefixLength - suffixLength, 0)
                let newMiddleLength = max(newTextString.length - prefixLength - suffixLength, 0)
                let replacementRange = NSRange(location: prefixLength, length: oldMiddleLength)
                let replacement = newTextString.substring(with: NSRange(location: prefixLength, length: newMiddleLength))

                textStorage.beginEditing()
                textStorage.replaceCharacters(in: replacementRange, with: replacement)
                textStorage.endEditing()

                let adjustedSelection = adjustedSelection(
                    existingSelection,
                    newTextLength: newTextString.length,
                    replacementRange: replacementRange,
                    replacementLength: newMiddleLength
                )
                if adjustedSelection != existingSelection {
                    textView.setSelectedRange(adjustedSelection)
                }
            } else {
                textView.string = newText
            }

            needsFullTextRestyle = true
            ensureReadableTextAttributes(in: textView)
            textView.setAccessibilityValue(newText as NSString)
            lastAppliedAccessibilityValue = newText
            pendingUserTextChange = nil
            logTextEvent(
                "sync text applied oldCount=\(oldText.length) newCount=\(newTextString.length) didMutate=true selection=\(debugRange(textView.selectedRange()))"
            )
            return true
        }

        func shouldPreserveLiveUserText(in textView: NSTextView, bindingText: String) -> Bool {
            guard textView.isEditable else { return false }
            guard textView.string != bindingText else { return false }
            guard textView.window?.firstResponder === textView else { return false }
            guard !isApplyingProgrammaticChange else { return false }
            guard hasUncommittedUserText(in: textView) else { return false }

            return true
        }

        private func hasUncommittedUserText(in textView: NSTextView) -> Bool {
            pendingUserTextChange != nil || pendingTextBindingUpdateAfterLayoutSync != nil
        }

        func syncLiveUserTextFromView(_ textView: NSTextView) {
            let currentText = textView.string
            logTextEvent(
                "live user text preserved viewCount=\(currentText.utf16.count) bindingCount=\(text.utf16.count) selection=\(debugRange(textView.selectedRange()))"
            )
            setTextIfNeeded(currentText)
            pendingUserTextChange = nil
        }

        func syncSelectionOverlayState(from textView: NSTextView) {
            guard !isApplyingProgrammaticChange else { return }
            guard !isPerformingLayoutSync else { return }

            let range = textView.selectedRange()
            guard let snapshot = selectionSnapshot(from: textView, selection: range) else {
                if shouldPreserveSelectionOverlayDuringPendingLocalEdit {
                    logSelectionEvent("selection preserved during pending local edit selection=\(debugRange(range))")
                    return
                }
                enqueueSelectionOverlayUpdate(selectedText: nil, selectedTextRange: nil, origin: nil)
                if range.length == 0 {
                    logSelectionEvent("selection cleared selection=\(debugRange(range))")
                    logSelectionEvent("popover origin cleared empty selection=\(debugRange(range))")
                }
                return
            }

            enqueueSelectionOverlayUpdate(
                selectedText: snapshot.selectedText,
                selectedTextRange: snapshot.selectionRange,
                origin: snapshot.origin
            )
            logSelectionEvent(
                "selection updated selection=\(debugRange(range)) preview=\(snapshot.selectedText.vibewriteLogPreview(maxLength: 60))"
            )
            logSelectionEvent(
                "popover origin updated selection=\(debugRange(range)) rect=\(debugRect(snapshot.rectInScrollView)) visible=\(debugSize(snapshot.visibleWidth, snapshot.visibleHeight)) origin=\(debugPoint(snapshot.origin))"
            )
        }

        func syncAccessibilityValue(in textView: NSTextView) {
            let currentValue = textView.string
            guard lastAppliedAccessibilityValue != currentValue else {
                return
            }

            textView.setAccessibilityValue(currentValue as NSString)
            lastAppliedAccessibilityValue = currentValue
        }

        func syncLayout(
            in textView: NSTextView,
            scrollView: NSScrollView,
            prefersSelectionVisibility: Bool,
            shouldAutoScrollToDocumentEnd: Bool,
            isViewportLockedDuringLocalEdit: Bool
        ) {
            guard let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }

            let clipBounds = scrollView.contentView.bounds
            let visibleWidth = max(clipBounds.width, 1)
            let visibleHeight = max(clipBounds.height, 1)
            let textInsetY = max(textView.textContainerInset.height, 0)
            let textInsetX = max(textView.textContainerInset.width, 0)
            let horizontalInset = textInsetX
            let containerWidth = max(visibleWidth - (textInsetX * 2), 1)

            guard visibleWidth > 1, visibleHeight > 1 else { return }

            if isViewportLockedDuringLocalEdit {
                if lockedViewportOrigin == nil {
                    lockedViewportOrigin = clipBounds.origin
                }
            }

            isPerformingLayoutSync = true
            defer {
                isPerformingLayoutSync = false
                flushDeferredTextBindingUpdateIfNeeded(for: textView)
                flushDeferredSelectionOverlaySyncIfNeeded(for: textView)
            }

            let desiredContainerSize = NSSize(
                width: containerWidth,
                height: CGFloat.greatestFiniteMagnitude
            )

            if textContainer.containerSize != desiredContainerSize {
                textContainer.containerSize = desiredContainerSize
            }
            let desiredInset = NSSize(width: horizontalInset, height: textInsetY)
            if textView.textContainerInset != desiredInset {
                textView.textContainerInset = desiredInset
            }
            textView.minSize = NSSize(width: visibleWidth, height: visibleHeight)
            textView.maxSize = NSSize(width: visibleWidth, height: CGFloat.greatestFiniteMagnitude)

            layoutManager.ensureLayout(for: textContainer)

            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let contentHeight = max(
                visibleHeight,
                ceil(usedHeight + (textInsetY * 2))
            )
            let resolvedSize = NSSize(width: visibleWidth, height: contentHeight)
            if textView.frame.size != resolvedSize {
                textView.setFrameSize(resolvedSize)
            }

            textView.needsDisplay = true

            if let lockedViewportOrigin {
                scrollView.contentView.scroll(to: lockedViewportOrigin)
            } else if shouldAutoScrollToDocumentEnd {
                let endRange = NSRange(location: textView.string.utf16.count, length: 0)
                textView.scrollRangeToVisible(endRange)
            } else if prefersSelectionVisibility {
                let selection = textView.selectedRange()
                if selection.location <= textView.string.utf16.count {
                    textView.scrollRangeToVisible(selection)
                }
            }

            scrollView.reflectScrolledClipView(scrollView.contentView)
            localEditFlashOverlayView?.needsDisplay = true
            logLayoutIfNeeded(
                textView: textView,
                scrollView: scrollView,
                visibleWidth: visibleWidth,
                visibleHeight: visibleHeight,
                contentHeight: contentHeight,
                usedHeight: usedHeight,
                shouldAutoScrollToDocumentEnd: shouldAutoScrollToDocumentEnd,
                isViewportLockedDuringLocalEdit: isViewportLockedDuringLocalEdit,
                prefersSelectionVisibility: prefersSelectionVisibility
            )
        }

        func syncLocalEditFlash(
            _ localEditFlash: WritingLocalEditFlash?,
            in textView: NSTextView,
            scrollView: NSScrollView
        ) {
            ensureLocalEditFlashOverlay(in: scrollView, textView: textView)
            guard let localEditFlashOverlayView else { return }

            guard let localEditFlash else {
                logSelectionEvent("local flash sync cleared overlay")
                clearLocalEditFlash(in: localEditFlashOverlayView)
                return
            }

            guard lastAppliedLocalEditFlashID != localEditFlash.id else {
                logSelectionEvent("local flash sync skipped duplicate id=\(localEditFlash.id.uuidString)")
                return
            }

            clearLocalEditFlash(in: localEditFlashOverlayView)

            logSelectionEvent(
                "local flash sync incoming id=\(localEditFlash.id.uuidString) sourceRange=\(localEditFlash.range.nsRange.debugDescription) textCount=\(textView.string.utf16.count)"
            )
            guard let flashRange = localEditFlash.range.range(in: textView.string),
                  flashRange.lowerBound < flashRange.upperBound else {
                logSelectionEvent("local flash sync invalid range id=\(localEditFlash.id.uuidString)")
                lastAppliedLocalEditFlashID = nil
                return
            }

            let highlightRange = NSRange(flashRange, in: textView.string)
            logSelectionEvent(
                "local flash sync apply id=\(localEditFlash.id.uuidString) highlightRange=\(highlightRange.debugDescription)"
            )
            localEditFlashOverlayView.applyFlash(range: highlightRange, in: textView)
            lastAppliedLocalEditFlashID = localEditFlash.id
        }

        private func clearLocalEditFlash(in overlayView: LocalEditFlashOverlayView) {
            guard lastAppliedLocalEditFlashID != nil || overlayView.hasActiveFlash else {
                lastAppliedLocalEditFlashID = nil
                return
            }

            overlayView.clearFlash()
            lastAppliedLocalEditFlashID = nil
        }

        private func ensureLocalEditFlashOverlay(in scrollView: NSScrollView, textView: NSTextView) {
            if let localEditFlashOverlayView {
                localEditFlashOverlayView.attach(to: textView)
                localEditFlashOverlayView.needsDisplay = true
                return
            }

            let overlayView = LocalEditFlashOverlayView(frame: scrollView.contentView.bounds)
            overlayView.autoresizingMask = [.width, .height]
            overlayView.attach(to: textView)
            scrollView.contentView.addSubview(overlayView, positioned: .above, relativeTo: textView)
            localEditFlashOverlayView = overlayView
            logSelectionEvent("local flash overlay created frame=\(debugRect(overlayView.frame))")
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            let currentStringCount = textView.string.utf16.count
            let currentSelection = debugRange(textView.selectedRange())
            let isProgrammatic = isApplyingProgrammaticChange
            let isLayoutSync = isPerformingLayoutSync
            let isEditable = textView.isEditable
            VibeWriteLog.ai.info(
                "textDidChange entry stringCount=\(currentStringCount, privacy: .public) applyingProgrammatic=\(isProgrammatic, privacy: .public) layoutSync=\(isLayoutSync, privacy: .public) editable=\(isEditable, privacy: .public) selection=\(currentSelection, privacy: .public)"
            )
            logTextEvent(
                "text did change stringCount=\(currentStringCount) applyingProgrammatic=\(isProgrammatic) layoutSync=\(isLayoutSync) editable=\(isEditable) selection=\(currentSelection)"
            )
            guard textView.isEditable else { return }
            guard !isApplyingProgrammaticChange else { return }
            pendingUserTextChange = textView.string
            if isPerformingLayoutSync {
                pendingTextBindingUpdateAfterLayoutSync = textView.string
                let pendingCount = textView.string.utf16.count
                let pendingSelection = debugRange(textView.selectedRange())
                VibeWriteLog.ai.info(
                    "textDidChange deferred during layout pendingCount=\(pendingCount, privacy: .public) selection=\(pendingSelection, privacy: .public)"
                )
                logTextEvent(
                    "text change deferred during layout pendingCount=\(pendingCount) selection=\(pendingSelection)"
                )
                return
            }

            pendingTextBindingUpdateAfterLayoutSync = nil
            let commitCount = textView.string.utf16.count
            let commitSelection = debugRange(textView.selectedRange())
            VibeWriteLog.ai.info(
                "textDidChange immediate commit count=\(commitCount, privacy: .public) selection=\(commitSelection, privacy: .public)"
            )
            setTextIfNeeded(textView.string)
            syncSelectionOverlayState(from: textView)
        }

        fileprivate func setTextIfNeeded(_ newText: String) {
            guard text != newText else {
                VibeWriteLog.ai.info(
                    "binding text unchanged count=\(newText.utf16.count, privacy: .public)"
                )
                logTextEvent("binding text unchanged count=\(newText.utf16.count)")
                return
            }
            VibeWriteLog.ai.info(
                "binding text updated count=\(newText.utf16.count, privacy: .public)"
            )
            logTextEvent("binding text updated count=\(newText.utf16.count)")
            text = newText
        }

        private func flushDeferredSelectionOverlaySyncIfNeeded(for textView: NSTextView) {
            guard needsSelectionOverlaySyncAfterLayout else { return }
            needsSelectionOverlaySyncAfterLayout = false

            logSelectionEvent("selection change flushed after layout selection=\(debugRange(textView.selectedRange())) editable=\(textView.isEditable)")
            syncSelectionOverlayState(from: textView)
        }

        private func flushDeferredTextBindingUpdateIfNeeded(for textView: NSTextView) {
            guard let pendingTextBindingUpdateAfterLayoutSync else { return }
            self.pendingTextBindingUpdateAfterLayoutSync = nil

            let pendingCount = pendingTextBindingUpdateAfterLayoutSync.utf16.count
            let pendingSelection = debugRange(textView.selectedRange())
            VibeWriteLog.ai.info(
                "textDidChange flushed after layout pendingCount=\(pendingCount, privacy: .public) selection=\(pendingSelection, privacy: .public)"
            )
            logTextEvent(
                "text change flushed after layout pendingCount=\(pendingCount) selection=\(pendingSelection)"
            )
            setTextIfNeeded(pendingTextBindingUpdateAfterLayoutSync)
            pendingUserTextChange = nil
            syncSelectionOverlayState(from: textView)
        }

        private func enqueueSelectionOverlayUpdate(selectedText newSelectedText: String?, origin newOrigin: CGPoint?) {
            enqueueSelectionOverlayUpdate(
                selectedText: newSelectedText,
                selectedTextRange: nil,
                origin: newOrigin
            )
        }

        private func enqueueSelectionOverlayUpdate(
            selectedText newSelectedText: String?,
            selectedTextRange newSelectedTextRange: WritingTextSelectionRange?,
            origin newOrigin: CGPoint?
        ) {
            guard selectedText != newSelectedText || selectedTextRange != newSelectedTextRange || selectionPopoverOrigin != newOrigin else { return }

            selectionOverlayUpdateGeneration += 1
            let generation = selectionOverlayUpdateGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.selectionOverlayUpdateGeneration == generation else { return }

                if self.selectedText != newSelectedText {
                    self.selectedText = newSelectedText
                }
                if self.selectedTextRange != newSelectedTextRange {
                    self.selectedTextRange = newSelectedTextRange
                }
                if self.selectionPopoverOrigin != newOrigin {
                    self.selectionPopoverOrigin = newOrigin
                }
            }
        }

        private func selectionSnapshot(
            from textView: NSTextView,
            selection: NSRange
        ) -> (selectedText: String, selectionRange: WritingTextSelectionRange, origin: CGPoint, rectInScrollView: CGRect, visibleWidth: CGFloat, visibleHeight: CGFloat)? {
            guard selection.length > 0 else { return nil }

            let string = textView.string as NSString
            guard selection.location + selection.length <= string.length else {
                logSelectionEvent("selection out of bounds selection=\(debugRange(selection)) stringLength=\(string.length)")
                return nil
            }

            let selectedText = string.substring(with: selection)
            guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            guard let scrollView else {
                logSelectionEvent("popover origin skipped missing scroll view selection=\(debugRange(selection))")
                return nil
            }

            guard let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else {
                logSelectionEvent("popover origin skipped missing layout objects selection=\(debugRange(selection))")
                return nil
            }

            let stringLength = textView.string.utf16.count
            guard selection.location < stringLength else {
                logSelectionEvent("popover origin skipped selection past string length selection=\(debugRange(selection)) stringLength=\(stringLength)")
                return nil
            }

            let clampedLength = min(selection.length, stringLength - selection.location)
            let characterRange = NSRange(location: selection.location, length: clampedLength)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )

            guard glyphRange.length > 0 else {
                logSelectionEvent("popover origin skipped empty glyph range selection=\(debugRange(selection))")
                return nil
            }

            var selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            selectionRect.origin.x += textView.textContainerOrigin.x
            selectionRect.origin.y += textView.textContainerOrigin.y
            let selectionRectInScrollView = textView.convert(selectionRect, to: scrollView)

            let visibleBounds = scrollView.contentView.bounds
            let visibleWidth = max(visibleBounds.width, 1)
            let visibleHeight = max(visibleBounds.height, 1)

            let maxPopoverWidth: CGFloat = 320
            let estimatedPopoverHeight: CGFloat = 76
            let horizontalPadding: CGFloat = 12
            let verticalPadding: CGFloat = 10

            let clampedX = min(
                max(selectionRectInScrollView.minX, horizontalPadding),
                max(visibleWidth - maxPopoverWidth - horizontalPadding, horizontalPadding)
            )
            let topLeadingY = selectionRectInScrollView.minY - estimatedPopoverHeight - verticalPadding
            let clampedY = min(
                max(topLeadingY, verticalPadding),
                max(visibleHeight - estimatedPopoverHeight - verticalPadding, verticalPadding)
            )

            return (
                selectedText: selectedText,
                selectionRange: WritingTextSelectionRange(selection),
                origin: CGPoint(x: clampedX, y: clampedY),
                rectInScrollView: selectionRectInScrollView,
                visibleWidth: visibleWidth,
                visibleHeight: visibleHeight
            )
        }

        private func logSelectionEvent(_ message: String) {
            VibeWriteDebugTrace.append("selection editor \(message)")
            VibeWriteLog.launch.info("selection editor \(message, privacy: .public)")
        }

        fileprivate func logTextEvent(_ message: String) {
            VibeWriteDebugTrace.append("text editor binding \(message)")
            VibeWriteLog.launch.info("text editor binding \(message, privacy: .public)")
        }

        fileprivate func debugRange(_ range: NSRange) -> String {
            "loc=\(range.location) len=\(range.length)"
        }

        private func debugPoint(_ point: CGPoint?) -> String {
            guard let point else { return "nil" }
            return String(format: "(%.1f, %.1f)", Double(point.x), Double(point.y))
        }

        private func debugPoint(_ point: CGPoint) -> String {
            String(format: "(%.1f, %.1f)", Double(point.x), Double(point.y))
        }

        private func debugRect(_ rect: CGRect) -> String {
            String(
                format: "(%.1f, %.1f, %.1f, %.1f)",
                Double(rect.origin.x),
                Double(rect.origin.y),
                Double(rect.size.width),
                Double(rect.size.height)
            )
        }

        private func debugSize(_ width: CGFloat, _ height: CGFloat) -> String {
            String(format: "(%.1f x %.1f)", Double(width), Double(height))
        }

        private func commonPrefixLength(between oldText: NSString, and newText: NSString) -> Int {
            let upperBound = min(oldText.length, newText.length)
            var index = 0

            while index < upperBound {
                if oldText.character(at: index) != newText.character(at: index) {
                    break
                }

                index += 1
            }

            return index
        }

        private func commonSuffixLength(
            between oldText: NSString,
            and newText: NSString,
            prefixLength: Int
        ) -> Int {
            let maxLength = min(oldText.length, newText.length)
            guard prefixLength < maxLength else { return 0 }

            var suffixLength = 0
            while suffixLength < (maxLength - prefixLength) {
                let oldIndex = oldText.length - 1 - suffixLength
                let newIndex = newText.length - 1 - suffixLength
                if oldText.character(at: oldIndex) != newText.character(at: newIndex) {
                    break
                }

                suffixLength += 1
            }

            return suffixLength
        }

        private func adjustedSelection(
            _ existingSelection: NSRange,
            newTextLength: Int,
            replacementRange: NSRange,
            replacementLength: Int
        ) -> NSRange {
            guard existingSelection.length == 0 else {
                let clampedLocation = min(existingSelection.location, max(newTextLength, 0))
                return NSRange(location: clampedLocation, length: 0)
            }

            let oldReplacementEnd = replacementRange.location + replacementRange.length
            let delta = replacementLength - replacementRange.length

            if existingSelection.location >= oldReplacementEnd {
                let adjustedLocation = min(max(existingSelection.location + delta, 0), max(newTextLength, 0))
                return NSRange(location: adjustedLocation, length: 0)
            }

            if existingSelection.location >= replacementRange.location {
                let adjustedLocation = min(replacementRange.location + replacementLength, max(newTextLength, 0))
                return NSRange(location: adjustedLocation, length: 0)
            }

            let clampedLocation = min(existingSelection.location, max(newTextLength, 0))
            return NSRange(location: clampedLocation, length: 0)
        }

        private func beginProgrammaticChange() {
            programmaticChangeDepth += 1
        }

        private func endProgrammaticChange() {
            programmaticChangeDepth = max(programmaticChangeDepth - 1, 0)
        }

        private func logLayoutIfNeeded(
            textView: NSTextView,
            scrollView: NSScrollView,
            visibleWidth: CGFloat,
            visibleHeight: CGFloat,
            contentHeight: CGFloat,
            usedHeight: CGFloat,
            shouldAutoScrollToDocumentEnd: Bool,
            isViewportLockedDuringLocalEdit: Bool,
            prefersSelectionVisibility: Bool
        ) {
            let contentBounds = scrollView.contentView.bounds
            let textLength = textView.string.utf16.count
            let selection = textView.selectedRange()
            let signature = [
                "text=\(textLength)",
                "visible=\(safeDimensionString(visibleWidth))x\(safeDimensionString(visibleHeight))",
                "frame=\(safeDimensionString(textView.frame.width))x\(safeDimensionString(textView.frame.height))",
                "container=\(safeDimensionString(textView.textContainer?.containerSize.width ?? 0))x\(safeDimensionString(textView.textContainer?.containerSize.height ?? 0))",
                "bounds=\(safeDimensionString(contentBounds.origin.x)),\(safeDimensionString(contentBounds.origin.y)) \(safeDimensionString(contentBounds.width))x\(safeDimensionString(contentBounds.height))",
                "used=\(safeDimensionString(usedHeight))",
                "content=\(safeDimensionString(contentHeight))",
                "autoScroll=\(shouldAutoScrollToDocumentEnd)",
                "viewportLock=\(isViewportLockedDuringLocalEdit)",
                "prefersSelection=\(prefersSelectionVisibility)",
                "selection=\(selection.location),\(selection.length)"
            ].joined(separator: " | ")

            guard signature != lastLoggedLayoutSignature else { return }
            lastLoggedLayoutSignature = signature

            VibeWriteDebugTrace.append("text editor layout \(signature)")
            VibeWriteLog.launch.info(
                "text editor layout \(signature, privacy: .public)"
            )
        }

        private func safeDimensionString(_ value: CGFloat) -> String {
            guard value.isFinite else {
                return value.sign == .minus ? "-inf" : "inf"
            }

            let intMaxAsCGFloat = CGFloat(Int.max)
            let intMinAsCGFloat = CGFloat(Int.min)
            if value > intMaxAsCGFloat || value < intMinAsCGFloat {
                return String(format: "%.2f", Double(value))
            }

            let rounded = value.rounded()
            if rounded >= CGFloat(Int.min) && rounded <= CGFloat(Int.max) {
                return String(Int(rounded))
            }

            return String(format: "%.2f", Double(value))
        }
    }
}

private final class LocalEditFlashOverlayView: NSView {
    private weak var textView: NSTextView?
    private var flashRange: NSRange?
    private var lastLoggedDrawSignature: String?
    private var flashOpacity: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }
    private var flashFadeWorkItem: DispatchWorkItem?
    private var flashFadeTimer: DispatchSourceTimer?

    var hasActiveFlash: Bool {
        flashRange != nil
    }

    override var isFlipped: Bool { true }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        alphaValue = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func attach(to textView: NSTextView) {
        self.textView = textView
    }

    func applyFlash(range: NSRange, in textView: NSTextView) {
        self.textView = textView
        flashRange = range
        lastLoggedDrawSignature = nil
        isHidden = false
        cancelFlashFade()
        alphaValue = 1
        flashOpacity = 1
        needsDisplay = true
        VibeWriteDebugTrace.append(
            "local edit flash overlay apply range=\(NSStringFromRange(range)) textLength=\(textView.string.utf16.count) frame=\(NSStringFromRect(frame))"
        )

        let fadeDelay: TimeInterval = 0.12
        let fadeDuration: TimeInterval = 1.68
        let fadeStepInterval: TimeInterval = 1.0 / 30.0

        let fadeWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.startFlashFade(duration: fadeDuration, stepInterval: fadeStepInterval)
        }
        flashFadeWorkItem = fadeWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay, execute: fadeWorkItem)
    }

    func clearFlash() {
        cancelFlashFade()
        VibeWriteDebugTrace.append(
            "local edit flash overlay clear hadRange=\(flashRange.map { NSStringFromRange($0) } ?? "nil")"
        )
        flashRange = nil
        lastLoggedDrawSignature = nil
        flashOpacity = 0
        alphaValue = 0
        isHidden = true
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let flashRange,
              flashRange.length > 0,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: flashRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }

        let textOrigin = textView.textContainerOrigin
        let paddingX: CGFloat = 2
        let paddingY: CGFloat = 1.5
        let radius: CGFloat = 6
        let fillColor = NSColor.systemYellow.withAlphaComponent(0.10 * flashOpacity)
        var enclosingRectCount = 0

        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: 0, length: 0),
            in: textContainer
        ) { rect, _ in
            enclosingRectCount += 1
            var adjustedRect = rect.offsetBy(dx: textOrigin.x, dy: textOrigin.y)
            adjustedRect = adjustedRect.insetBy(dx: -paddingX, dy: -paddingY)
            adjustedRect = textView.convert(adjustedRect, to: self)

            let roundedRadius = min(radius, adjustedRect.width / 2, adjustedRect.height / 2)
            guard roundedRadius > 0 else { return }
            let roundedPath = NSBezierPath(roundedRect: adjustedRect, xRadius: roundedRadius, yRadius: roundedRadius)
            fillColor.setFill()
            roundedPath.fill()
        }

        let signature = [
            "range=\(NSStringFromRange(flashRange))",
            "glyph=\(NSStringFromRange(glyphRange))",
            "rectCount=\(enclosingRectCount)",
            "opacity=\(String(format: "%.2f", Double(flashOpacity)))",
            "frame=\(NSStringFromRect(frame))"
        ].joined(separator: " | ")

        guard signature != lastLoggedDrawSignature else { return }
        lastLoggedDrawSignature = signature
        VibeWriteDebugTrace.append("local edit flash overlay draw \(signature)")
    }

    private func startFlashFade(duration: TimeInterval, stepInterval: TimeInterval) {
        guard let flashRange = flashRange else { return }
        cancelFlashFade(keepLog: false)

        let startTime = CACurrentMediaTime()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: stepInterval, leeway: .milliseconds(8))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let flashRange = self.flashRange else {
                self.cancelFlashFade(keepLog: false)
                return
            }

            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(max(elapsed / duration, 0), 1)
            let remainingOpacity = 1 - progress
            self.flashOpacity = remainingOpacity

            if progress >= 1 {
                VibeWriteDebugTrace.append(
                    "local edit flash overlay fade completed range=\(NSStringFromRange(flashRange))"
                )
                self.cancelFlashFade(keepLog: false)
            }
        }
        flashFadeTimer = timer
        VibeWriteDebugTrace.append(
            "local edit flash overlay fade started range=\(NSStringFromRange(flashRange)) duration=\(String(format: "%.2f", duration))"
        )
        timer.resume()
    }

    private func cancelFlashFade(keepLog: Bool = true) {
        flashFadeWorkItem?.cancel()
        flashFadeWorkItem = nil
        flashFadeTimer?.cancel()
        flashFadeTimer = nil
        if keepLog {
            flashOpacity = 0
        }
    }
}

private final class StyledTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        let chars = debugEventString(event.characters)
        let ignoringModifiers = debugEventString(event.charactersIgnoringModifiers)
        let modifierFlags = debugModifierFlags(event.modifierFlags)
        let firstResponderName = debugFirstResponder()
        let textCount = self.string.utf16.count
        VibeWriteLog.launch.info(
            "styled text view keyDown keyCode=\(event.keyCode, privacy: .public) chars=\(chars, privacy: .public) ignoringModifiers=\(ignoringModifiers, privacy: .public) modifiers=\(modifierFlags, privacy: .public) firstResponder=\(firstResponderName, privacy: .public) editable=\(self.isEditable, privacy: .public) textCount=\(textCount, privacy: .public)"
        )
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let chars = debugEventString(event.characters)
        let ignoringModifiers = debugEventString(event.charactersIgnoringModifiers)
        let modifierFlags = debugModifierFlags(event.modifierFlags)
        let firstResponderName = debugFirstResponder()
        let handled = super.performKeyEquivalent(with: event)
        VibeWriteLog.launch.info(
            "styled text view performKeyEquivalent keyCode=\(event.keyCode, privacy: .public) chars=\(chars, privacy: .public) ignoringModifiers=\(ignoringModifiers, privacy: .public) modifiers=\(modifierFlags, privacy: .public) handled=\(handled, privacy: .public) firstResponder=\(firstResponderName, privacy: .public)"
        )
        return handled
    }

    override func doCommand(by selector: Selector) {
        let firstResponderName = debugFirstResponder()
        let textCount = string.utf16.count
        VibeWriteLog.launch.info(
            "styled text view doCommand selector=\(NSStringFromSelector(selector), privacy: .public) firstResponder=\(firstResponderName, privacy: .public) textCount=\(textCount, privacy: .public)"
        )
        super.doCommand(by: selector)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let textPreview: String
        if let string = insertString as? String {
            textPreview = string.vibewriteLogPreview(maxLength: 32)
        } else if let attributed = insertString as? NSAttributedString {
            textPreview = attributed.string.vibewriteLogPreview(maxLength: 32)
        } else {
            textPreview = String(describing: type(of: insertString))
        }
        let firstResponderName = debugFirstResponder()
        let beforeCount = string.utf16.count

        VibeWriteLog.launch.info(
            "styled text view insertText replacementRange=\(NSStringFromRange(replacementRange), privacy: .public) text=\(textPreview, privacy: .public) firstResponder=\(firstResponderName, privacy: .public) textCountBefore=\(beforeCount, privacy: .public)"
        )
        super.insertText(insertString, replacementRange: replacementRange)
        let afterCount = string.utf16.count
        let selection = NSStringFromRange(selectedRange())
        VibeWriteLog.launch.info(
            "styled text view insertText applied textCountAfter=\(afterCount, privacy: .public) selection=\(selection, privacy: .public)"
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        let clampedSize = NSSize(
            width: max(newSize.width, 1),
            height: max(newSize.height, 1)
        )

        super.setFrameSize(clampedSize)
        refreshLayoutAfterResize()
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        refreshLayoutAfterResize()
    }

    override func layout() {
        super.layout()
        refreshLayoutAfterResize()
    }

    private func refreshLayoutAfterResize() {
        guard let textContainer else { return }

        let horizontalInset = max(textContainerInset.width, 0)
        let width = max(bounds.width - (horizontalInset * 2), 1)
        let desiredContainerSize = NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )

        if textContainer.containerSize != desiredContainerSize {
            textContainer.containerSize = desiredContainerSize
        }

        layoutManager?.ensureLayout(for: textContainer)
        needsDisplay = true
        if let scrollView = enclosingScrollView {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func debugEventString(_ string: String?) -> String {
        string?.vibewriteLogPreview(maxLength: 12) ?? "nil"
    }

    private func debugModifierFlags(_ flags: NSEvent.ModifierFlags) -> String {
        let resolved = flags.intersection(.deviceIndependentFlagsMask)
        return String(describing: resolved)
    }

    private func debugFirstResponder() -> String {
        guard let window else { return "nil" }
        if window.firstResponder === self {
            return "self"
        }
        guard let firstResponder = window.firstResponder else { return "nil" }
        return String(describing: type(of: firstResponder))
    }
}

struct ExternalVerticalScroller: NSViewRepresentable {
    let scrollView: NSScrollView?

    func makeNSView(context: Context) -> ExternalVerticalScrollerView {
        let view = ExternalVerticalScrollerView()
        view.scrollView = scrollView
        view.syncVisibilityForCurrentContent()
        return view
    }

    func updateNSView(_ nsView: ExternalVerticalScrollerView, context: Context) {
        nsView.scrollView = scrollView
        nsView.syncVisibilityForCurrentContent()
    }
}

final class ExternalVerticalScrollerView: NSView {
    private let trackInset: CGFloat = 2
    private let verticalInset: CGFloat = 12
    private let minimumKnobHeight: CGFloat = 30
    private let trackWidth: CGFloat = 5
    private let knobWidth: CGFloat = 5
    private let autoHideDelay: TimeInterval = 1.1
    private let fadeInDuration: TimeInterval = 0.10
    private let fadeOutDuration: TimeInterval = 0.18
    private let trackColor = NSColor.vibeCanvasInk.withAlphaComponent(0.06)
    private let knobColor = NSColor.vibeCanvasInk.withAlphaComponent(0.42)
    private let knobHoverColor = NSColor.vibeCanvasInk.withAlphaComponent(0.60)
    private var dragAnchorOffsetY: CGFloat?
    private var autoHideWorkItem: DispatchWorkItem?

    weak var scrollView: NSScrollView? {
        didSet {
            guard oldValue !== scrollView else { return }
            resetObservers()
            installObservers()
            syncVisibilityForCurrentContent()
        }
    }

    override var isFlipped: Bool { true }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private var shouldHideScroller: Bool {
        guard let scrollView,
              let documentView = scrollView.documentView else {
            return true
        }

        let visibleHeight = max(scrollView.contentView.bounds.height, 1)
        let documentHeight = max(documentView.bounds.height, 1)
        return documentHeight <= visibleHeight + 1
    }

    private var trackRect: CGRect {
        bounds.insetBy(dx: trackInset, dy: verticalInset)
    }

    private func knobMetrics() -> (thumbRect: CGRect, maxOffset: CGFloat)? {
        guard let scrollView,
              let documentView = scrollView.documentView else {
            return nil
        }

        let visibleHeight = max(scrollView.contentView.bounds.height, 1)
        let documentHeight = max(documentView.bounds.height, 1)
        guard documentHeight > visibleHeight + 1 else { return nil }

        let track = trackRect
        let knobProportion = min(1, visibleHeight / documentHeight)
        let thumbHeight = max(track.height * knobProportion, minimumKnobHeight)
        let travel = max(track.height - thumbHeight, 1)
        let maxOffset = max(documentHeight - visibleHeight, 1)
        let offsetY = min(max(scrollView.contentView.bounds.origin.y, 0), maxOffset)
        let progress = offsetY / maxOffset
        let thumbY = track.minY + (travel * progress)
        let thumbRect = CGRect(
            x: bounds.midX - (knobWidth / 2),
            y: thumbY,
            width: knobWidth,
            height: thumbHeight
        )
        return (thumbRect, maxOffset)
    }

    private func resetObservers() {
        NotificationCenter.default.removeObserver(self)
    }

    private func installObservers() {
        guard let scrollView else { return }

        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView?.postsFrameChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        if let documentView = scrollView.documentView {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleDocumentViewFrameDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: documentView
            )
        }
    }

    @MainActor
    func syncVisibilityForCurrentContent() {
        cancelAutoHideSchedule()

        guard hasScrollableContent else {
            hideImmediately()
            return
        }

        if isHidden == false {
            scheduleAutoHide()
        }
    }

    @objc
    private func handleScrollViewBoundsDidChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.revealTemporarily()
        }
    }

    @objc
    private func handleDocumentViewFrameDidChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.syncVisibilityForCurrentContent()
        }
    }

    private var hasScrollableContent: Bool {
        !shouldHideScroller
    }

    @MainActor
    private func revealTemporarily() {
        guard hasScrollableContent else {
            hideImmediately()
            return
        }

        showTemporarily()
        scheduleAutoHide()
    }

    @MainActor
    private func hideNow() {
        cancelAutoHideSchedule()
        guard isHidden == false else { return }
        animateVisibility(to: 0, duration: fadeOutDuration) { [weak self] in
            self?.isHidden = true
            self?.needsDisplay = true
        }
    }

    @MainActor
    private func scheduleAutoHide() {
        cancelAutoHideSchedule()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.hideNow()
            }
        }
        autoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay, execute: workItem)
    }

    @MainActor
    private func cancelAutoHideSchedule() {
        autoHideWorkItem?.cancel()
        autoHideWorkItem = nil
    }

    @MainActor
    private func hideImmediately() {
        cancelAutoHideSchedule()
        layer?.removeAllAnimations()
        alphaValue = 0
        isHidden = true
        needsDisplay = true
    }

    @MainActor
    private func showTemporarily() {
        cancelAutoHideSchedule()
        layer?.removeAllAnimations()

        if isHidden {
            alphaValue = 0
            isHidden = false
            needsDisplay = true
            animateVisibility(to: 1, duration: fadeInDuration, completion: nil)
            return
        }

        isHidden = false
        needsDisplay = true
        if alphaValue < 1 {
            animateVisibility(to: 1, duration: fadeInDuration, completion: nil)
        } else {
            alphaValue = 1
        }
    }

    @MainActor
    private func animateVisibility(
        to targetAlpha: CGFloat,
        duration: TimeInterval,
        completion: (() -> Void)?
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = targetAlpha
        } completionHandler: {
            completion?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard shouldHideScroller == false,
              let metrics = knobMetrics() else { return }

        let track = trackRect
        let thumb = metrics.thumbRect.integral
        let thumbRadius = min(thumb.width / 2, thumb.height / 2)
        let knobAppearance = knobAnchorColor(for: thumb)

        let trackPath = NSBezierPath(roundedRect: track, xRadius: track.width / 2, yRadius: track.width / 2)
        trackColor.setFill()
        trackPath.fill()

        let thumbPath = NSBezierPath(roundedRect: thumb, xRadius: thumbRadius, yRadius: thumbRadius)
        knobAppearance.setFill()
        thumbPath.fill()
    }

    private func knobAnchorColor(for thumb: CGRect) -> NSColor {
        let currentMouseLocation = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        if let currentMouseLocation, thumb.contains(currentMouseLocation) {
            return knobHoverColor
        }
        return knobColor
    }

    override func mouseDown(with event: NSEvent) {
        guard shouldHideScroller == false,
              let metrics = knobMetrics() else { return }

        Task { @MainActor [weak self] in
            self?.revealTemporarily()
        }

        let location = convert(event.locationInWindow, from: nil)
        let thumb = metrics.thumbRect

        if thumb.contains(location) {
            dragAnchorOffsetY = location.y - thumb.minY
        } else {
            let currentOffset = scrollView?.contentView.bounds.origin.y ?? 0
            let targetOffset = location.y > thumb.maxY
                ? currentOffset - max(bounds.height * 0.85, 1)
                : currentOffset + max(bounds.height * 0.85, 1)
            scroll(to: targetOffset, maxOffset: metrics.maxOffset)
            return
        }

        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragAnchorOffsetY else { return }
        guard shouldHideScroller == false,
              let metrics = knobMetrics() else { return }

        Task { @MainActor [weak self] in
            self?.revealTemporarily()
        }

        let location = convert(event.locationInWindow, from: nil)
        let track = trackRect
        let thumbHeight = metrics.thumbRect.height
        let travel = max(track.height - thumbHeight, 1)
        let desiredThumbMinY = min(max(location.y - dragAnchorOffsetY, track.minY), track.minY + travel)
        let progress = (desiredThumbMinY - track.minY) / travel
        let targetOffset = metrics.maxOffset * progress
        scroll(to: targetOffset, maxOffset: metrics.maxOffset)
    }

    override func mouseUp(with event: NSEvent) {
        dragAnchorOffsetY = nil
    }

    private func scroll(to targetOffset: CGFloat, maxOffset: CGFloat) {
        guard let scrollView else { return }

        let clampedOffset = min(max(targetOffset, 0), maxOffset)
        let clipBounds = scrollView.contentView.bounds
        scrollView.contentView.scroll(to: CGPoint(x: clipBounds.origin.x, y: clampedOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        Task { @MainActor [weak self] in
            self?.revealTemporarily()
        }
    }
}
