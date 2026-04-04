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
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
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
        let didMutateText = context.coordinator.syncText(text, in: textView)
        context.coordinator.syncAccessibilityValue(in: textView)
        context.coordinator.syncLayout(
            in: textView,
            scrollView: scrollView,
            prefersSelectionVisibility: didMutateText == false,
            shouldAutoScrollToDocumentEnd: shouldAutoScrollToDocumentEnd,
            isViewportLockedDuringLocalEdit: isViewportLockedDuringLocalEdit
        )
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
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var selectedText: String?
        @Binding private var selectedTextRange: WritingTextSelectionRange?
        @Binding private var selectionPopoverOrigin: CGPoint?
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
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
            guard textView.string != newText else {
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
            return true
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
                clearLocalEditFlash(in: localEditFlashOverlayView)
                return
            }

            guard lastAppliedLocalEditFlashID != localEditFlash.id else {
                return
            }

            clearLocalEditFlash(in: localEditFlashOverlayView)

            guard let flashRange = localEditFlash.range.range(in: textView.string),
                  flashRange.lowerBound < flashRange.upperBound else {
                lastAppliedLocalEditFlashID = nil
                return
            }

            let highlightRange = NSRange(flashRange, in: textView.string)
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
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            guard textView.isEditable else { return }
            guard !isApplyingProgrammaticChange else { return }
            guard !isPerformingLayoutSync else { return }

            setTextIfNeeded(textView.string)
            syncSelectionOverlayState(from: textView)
        }

        private func setTextIfNeeded(_ newText: String) {
            guard text != newText else { return }
            text = newText
        }

        private func flushDeferredSelectionOverlaySyncIfNeeded(for textView: NSTextView) {
            guard needsSelectionOverlaySyncAfterLayout else { return }
            needsSelectionOverlaySyncAfterLayout = false

            logSelectionEvent("selection change flushed after layout selection=\(debugRange(textView.selectedRange())) editable=\(textView.isEditable)")
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

        private func debugRange(_ range: NSRange) -> String {
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
        isHidden = false
        layer?.removeAllAnimations()
        alphaValue = 1
        needsDisplay = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.8
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 0
        }
    }

    func clearFlash() {
        layer?.removeAllAnimations()
        flashRange = nil
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
        let fillColor = NSColor.systemYellow.withAlphaComponent(0.10)

        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: 0, length: 0),
            in: textContainer
        ) { rect, _ in
            var adjustedRect = rect.offsetBy(dx: textOrigin.x, dy: textOrigin.y)
            adjustedRect = adjustedRect.insetBy(dx: -paddingX, dy: -paddingY)
            adjustedRect = textView.convert(adjustedRect, to: self)

            let roundedRadius = min(radius, adjustedRect.width / 2, adjustedRect.height / 2)
            guard roundedRadius > 0 else { return }
            let roundedPath = NSBezierPath(roundedRect: adjustedRect, xRadius: roundedRadius, yRadius: roundedRadius)
            fillColor.setFill()
            roundedPath.fill()
        }
    }
}

private final class StyledTextView: NSTextView {
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

        let width = max(bounds.width, 1)
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
}
