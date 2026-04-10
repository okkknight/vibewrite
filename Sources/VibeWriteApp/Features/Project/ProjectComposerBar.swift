import SwiftUI

struct ProjectComposerBar: View {
    @Binding var messageDraft: String
    let appearanceMode: VibeAppearanceMode
    let primaryActionTitle: String
    let messageFieldPlaceholder: String
    let showsAssistantSuggestions: Bool
    let assistantSuggestionChips: [String]
    let isComposerLocked: Bool
    let isRequestInFlight: Bool
    let isPrimaryOutputInFlight: Bool
    let isPrimaryActionInFlight: Bool
    let isSuggestionGenerationInFlight: Bool
    let messageFieldFocused: FocusState<Bool>.Binding
    let isMessageFieldHighlighted: Bool
    let guidanceRailBottomInset: CGFloat
    let accessibilityIdentifier: String
    let messageInputIdentifier: String
    let sendButtonIdentifier: String
    let onSubmit: () -> Void
    let onAssistantSuggestionTap: (String) -> Void

    var body: some View {
        composerSurface
            .overlay(alignment: .bottomLeading) {
                if shouldShowGuidanceRail {
                    guidanceRail
                        .padding(.bottom, guidanceRailBottomInset)
                }
            }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var guidanceRail: some View {
        if shouldShowGuidanceRail {
            SingleLineOverflowHidingLayout(itemSpacing: 8) {
                if isSuggestionGenerationInFlight {
                    suggestionLoadingPill
                } else if isOpeningState {
                    guidanceExampleChip(title: openingExampleTitle)
                } else {
                    ForEach(normalizedAssistantSuggestionChips, id: \.self) { chip in
                        AssistantSuggestionChip(title: chip) {
                            onAssistantSuggestionTap(chip)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var composerSurface: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(composerBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(gradientOpacity),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.softLight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(composerStrokeColor, lineWidth: 1)
                )
                .shadow(color: composerShadowColor, radius: composerShadowRadius, x: 0, y: composerShadowYOffset)

            TextEditor(text: $messageDraft)
                .focused(messageFieldFocused)
                .scrollContentBackground(.hidden)
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundStyle(textColor)
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.top, 14)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .disabled(isComposerLocked)
                .accessibilityLabel("协作输入框")
                .accessibilityIdentifier(messageInputIdentifier)

            if messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(messageFieldPlaceholder)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(textColor.opacity(0.48))
                    .padding(.leading, 18)
                    .padding(.top, 18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            Button(action: onSubmit) {
                submitButtonVisual
                    .environment(\.isEnabled, true)
            }
            .buttonStyle(.plain)
            .disabled(isRequestInFlight)
            .frame(width: 84, height: 34)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .accessibilityIdentifier(sendButtonIdentifier)
            .accessibilityLabel(primaryActionTitle)
        }
        .frame(height: 132, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var submitButtonVisual: some View {
        HStack(spacing: 7) {
            if isPrimaryActionInFlight {
                ThinkingPulseDot(color: submitButtonTextColor)
                    .padding(.leading, 1)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(submitButtonTextColor)
            }

            Text(submitButtonTitle)
                .font(.system(size: 12.7, weight: .semibold, design: .default))
                .foregroundStyle(submitButtonTextColor)
        }
        .frame(width: 84, height: 34)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(submitButtonBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(submitButtonStrokeColor, lineWidth: 1)
                )
                .shadow(color: submitButtonShadowColor, radius: 5, x: 0, y: 2)
        }
    }

    private var submitButtonBackgroundColor: Color {
        return appearanceMode == .day
            ? Color.vibeCanvasAccent.opacity(0.96)
            : Color.vibeCanvasAccent.opacity(0.88)
    }

    private var submitButtonStrokeColor: Color {
        Color.white.opacity(appearanceMode == .day ? 0.20 : 0.10)
    }

    private var submitButtonTextColor: Color {
        Color.white.opacity(0.96)
    }

    private var submitButtonTitle: String {
        if isPrimaryActionInFlight {
            return "\(primaryActionTitle)中"
        }

        return primaryActionTitle
    }

    private var submitButtonShadowColor: Color {
        Color.black.opacity(appearanceMode == .day ? 0.14 : 0.22)
    }

    private var isOpeningState: Bool {
        primaryActionTitle == "开场"
    }

    private var openingExampleTitle: String {
        "写一个XXX"
    }

    private var shouldShowGuidanceRail: Bool {
        if isOpeningState {
            return true
        }

        if isSuggestionGenerationInFlight {
            return !isPrimaryOutputInFlight
        }

        return showsAssistantSuggestions && !normalizedAssistantSuggestionChips.isEmpty
    }

    private var normalizedAssistantSuggestionChips: [String] {
        assistantSuggestionChips.compactMap { chip in
            let trimmed = chip.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private var gradientOpacity: Double {
        if isPrimaryActionInFlight {
            return 0.01
        }

        return isMessageFieldHighlighted ? 0.022 : 0.014
    }

    private var composerBackgroundColor: Color {
        if isMessageFieldHighlighted {
            return appearanceMode == .day
                ? Color.vibeCanvasRaised.opacity(0.985)
                : Color.vibeCanvasRaised.opacity(0.965)
        }

        return Color.vibeCanvasRaised.opacity(appearanceMode == .day ? 0.975 : 0.955)
    }

    private var composerStrokeColor: Color {
        if isPrimaryActionInFlight {
            return Color.vibeCanvasAccent.opacity(0.38)
        }

        return isMessageFieldHighlighted
            ? Color.vibeCanvasAccent.opacity(0.20)
            : Color.vibeCanvasStroke.opacity(appearanceMode == .day ? 0.64 : 0.50)
    }

    private var textColor: Color {
        isPrimaryActionInFlight ? Color.vibeCanvasInkMuted : Color.vibeCanvasInkSoft
    }

    private var composerShadowColor: Color {
        switch appearanceMode {
        case .day:
            return Color.black.opacity(0.12)
        case .night:
            return Color.black.opacity(0.20)
        }
    }

    private var composerShadowRadius: CGFloat {
        switch appearanceMode {
        case .day:
            return 12
        case .night:
            return 16
        }
    }

    private var composerShadowYOffset: CGFloat {
        switch appearanceMode {
        case .day:
            return 6
        case .night:
            return 9
        }
    }

    private var suggestionLoadingPill: some View {
        HStack(spacing: 7) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(Color.vibeCanvasAccent)

            Text("建议生成中")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(Color.vibeCanvasInkSoft)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background {
            Capsule(style: .continuous)
                .fill(Color.vibeCanvasLift.opacity(0.62))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.vibeCanvasStroke.opacity(0.30), lineWidth: 1)
                )
        }
        .accessibilityLabel("建议生成中")
    }

    private struct ThinkingPulseDot: View {
        let color: Color

        var body: some View {
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let phase = (sin(time * 5.2) + 1) / 2
                Circle()
                    .fill(color)
                    .frame(width: 5.5, height: 5.5)
                    .opacity(0.42 + (phase * 0.58))
                    .scaleEffect(0.82 + (phase * 0.32))
                    .accessibilityHidden(true)
            }
            .frame(width: 9, height: 9)
        }
    }

    private func guidanceExampleChip(title: String) -> some View {
        ActionChip(
            title,
            tint: .vibeCanvasAccent,
            action: {
                onAssistantSuggestionTap(title)
            }
        )
    }
}

private struct AssistantSuggestionChip: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(foregroundColor)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background {
                    Capsule(style: .continuous)
                        .fill(backgroundColor)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(strokeColor, lineWidth: 1)
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        Color.vibeCapsuleForeground(.interactive, colorScheme: colorScheme)
    }

    private var backgroundColor: Color {
        Color.vibeCapsuleBackground(.interactive, tint: .vibeCanvasAccent, colorScheme: colorScheme)
    }

    private var strokeColor: Color {
        Color.vibeCapsuleStroke(.interactive, colorScheme: colorScheme)
    }
}

struct TwoRowFlowLayout: Layout {
    let itemSpacing: CGFloat
    let rowSpacing: CGFloat

    init(itemSpacing: CGFloat = 8, rowSpacing: CGFloat = 8) {
        self.itemSpacing = itemSpacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = measuredRows(maxWidth: maxWidth, subviews: subviews)
        let width = rows.map { row in row.width }.max() ?? 0
        let height = rows.enumerated().reduce(CGFloat.zero) { partial, entry in
            partial + entry.element.height + (entry.offset == 0 ? 0 : rowSpacing)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = measuredRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for element in row.elements {
                subviews[element.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(element.size)
                )
                x += element.size.width + itemSpacing
            }
            y += row.height + rowSpacing
        }
    }

    private func measuredRows(maxWidth: CGFloat, subviews: Subviews) -> [MeasuredRow] {
        var rows: [MeasuredRow] = []
        var currentElements: [MeasuredElement] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = currentElements.isEmpty ? size.width : currentWidth + itemSpacing + size.width

            if !currentElements.isEmpty && proposedWidth > maxWidth {
                rows.append(MeasuredRow(elements: currentElements, width: currentWidth, height: currentHeight))
                if rows.count == 2 {
                    return rows
                }
                currentElements = []
                currentWidth = 0
                currentHeight = 0
            }

            currentElements.append(MeasuredElement(index: index, size: size))
            currentWidth = currentElements.count == 1 ? size.width : currentWidth + itemSpacing + size.width
            currentHeight = max(currentHeight, size.height)
        }

        if !currentElements.isEmpty && rows.count < 2 {
            rows.append(MeasuredRow(elements: currentElements, width: currentWidth, height: currentHeight))
        }

        return rows
    }

    private struct MeasuredRow {
        let elements: [MeasuredElement]
        let width: CGFloat
        let height: CGFloat
    }

    private struct MeasuredElement {
        let index: Int
        let size: CGSize
    }
}

struct SingleLineOverflowHidingLayout: Layout {
    let itemSpacing: CGFloat

    init(itemSpacing: CGFloat = 8) {
        self.itemSpacing = itemSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let line = SingleLineOverflowHidingLayoutMetrics.line(
            maxWidth: maxWidth,
            itemSpacing: itemSpacing,
            sizes: sizes
        )
        return CGSize(width: line.width, height: line.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let line = SingleLineOverflowHidingLayoutMetrics.line(
            maxWidth: bounds.width,
            itemSpacing: itemSpacing,
            sizes: sizes
        )
        var x = bounds.minX

        for element in line.elements {
            subviews[element.index].place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(element.size)
            )
            x += element.size.width + itemSpacing
        }
    }
}

enum SingleLineOverflowHidingLayoutMetrics {
    struct Line {
        let elements: [Element]
        let width: CGFloat
        let height: CGFloat
    }

    struct Element {
        let index: Int
        let size: CGSize
    }

    static func line(maxWidth: CGFloat, itemSpacing: CGFloat, sizes: [CGSize]) -> Line {
        var elements: [Element] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for (index, size) in sizes.enumerated() {
            let proposedWidth = elements.isEmpty ? size.width : currentWidth + itemSpacing + size.width

            if !elements.isEmpty && proposedWidth > maxWidth {
                break
            }

            if elements.isEmpty && size.width > maxWidth {
                break
            }

            elements.append(Element(index: index, size: size))
            currentWidth = elements.count == 1 ? size.width : currentWidth + itemSpacing + size.width
            currentHeight = max(currentHeight, size.height)
        }

        return Line(elements: elements, width: currentWidth, height: currentHeight)
    }
}
