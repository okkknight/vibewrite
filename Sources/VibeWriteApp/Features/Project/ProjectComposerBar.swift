import SwiftUI

struct ProjectComposerBar: View {
    @Binding var messageDraft: String
    let appearanceMode: VibeAppearanceMode
    let primaryActionTitle: String
    let messageFieldPlaceholder: String
    let showsAssistantSuggestions: Bool
    let assistantNextFocus: String?
    let assistantSuggestionChips: [String]
    let isComposerLocked: Bool
    let isRequestInFlight: Bool
    let isPrimaryActionInFlight: Bool
    let isSuggestionGenerationInFlight: Bool
    let messageFieldFocused: FocusState<Bool>.Binding
    let isMessageFieldHighlighted: Bool
    let accessibilityIdentifier: String
    let messageInputIdentifier: String
    let sendButtonIdentifier: String
    let onSubmit: () -> Void
    let onAssistantSuggestionTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsAssistantSuggestions {
                TwoRowFlowLayout(itemSpacing: 8, rowSpacing: 8) {
                    AccentPill(
                        title: primaryActionTitle,
                        icon: actionIcon,
                        tint: .vibeCanvasAccent
                    )

                    if shouldShowSuggestionLoadingPill {
                        suggestionLoadingPill
                    }

                    ForEach(normalizedAssistantSuggestionChips, id: \.self) { chip in
                        AssistantSuggestionChip(title: chip) {
                            onAssistantSuggestionTap(chip)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    AccentPill(
                        title: primaryActionTitle,
                        icon: actionIcon,
                        tint: .vibeCanvasAccent
                    )

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .center, spacing: 12) {
                TextField(composerPlaceholderText, text: $messageDraft)
                    .focused(messageFieldFocused)
                    .onSubmit(onSubmit)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 12)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.vibeCanvasLift.opacity(backgroundOpacity))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.vibeCanvasStroke.opacity(strokeOpacity), lineWidth: 1)
                            )
                            .shadow(color: highlightShadowColor, radius: highlightShadowRadius, x: 0, y: 0)
                    }
                    .foregroundStyle(isPrimaryActionInFlight ? Color.vibeCanvasInkMuted : Color.vibeCanvasInk)
                    .disabled(isComposerLocked)
                    .overlay(alignment: .topLeading) {
                        if isPrimaryActionInFlight {
                            ComposerThinkingGlow()
                                .frame(width: 320, height: 42, alignment: .leading)
                                .offset(x: 2, y: -16)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("协作输入框")
                    .accessibilityIdentifier(messageInputIdentifier)

                Button(action: onSubmit) {
                    SubmitGlyph(isThinking: isPrimaryActionInFlight)
                        .background {
                            Circle()
                                .fill(Color.vibeCanvasLift.opacity(isRequestInFlight || isComposerLocked ? 0.72 : 0.96))
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.vibeCanvasStroke.opacity(isRequestInFlight || isComposerLocked ? 0.35 : 0.58), lineWidth: 1)
                                )
                        }
                        .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(isRequestInFlight || isComposerLocked)
                .opacity(isRequestInFlight || isComposerLocked ? 0.65 : 1)
                .accessibilityIdentifier(sendButtonIdentifier)
                .accessibilityLabel(primaryActionTitle)
            }
            .accessibilityElement(children: .contain)
        }
        .padding(14)
        .accessibilityElement(children: .contain)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.vibeCanvasRaised.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.035),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                        .blendMode(.softLight)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.vibeCanvasStroke.opacity(0.78), lineWidth: 1)
                )
                .shadow(color: composerShadowColor, radius: composerShadowRadius, x: 0, y: composerShadowYOffset)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var backgroundOpacity: Double {
        if isPrimaryActionInFlight {
            return 0.66
        }

        return isMessageFieldHighlighted ? 0.90 : 0.82
    }

    private var gradientOpacity: Double {
        if isPrimaryActionInFlight {
            return 0.008
        }

        return isMessageFieldHighlighted ? 0.022 : 0.014
    }

    private var strokeOpacity: Double {
        if isPrimaryActionInFlight {
            return 0.48
        }

        return isMessageFieldHighlighted ? 0.86 : 0.68
    }

    private var highlightShadowColor: Color {
        isMessageFieldHighlighted && !isPrimaryActionInFlight ? Color.vibeCanvasAccent.opacity(0.18) : .clear
    }

    private var highlightShadowRadius: CGFloat {
        isMessageFieldHighlighted && !isPrimaryActionInFlight ? 10 : 0
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

    private var normalizedAssistantNextFocus: String? {
        let trimmed = assistantNextFocus?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private var normalizedAssistantSuggestionChips: [String] {
        var seen = Set<String>()
        return assistantSuggestionChips
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private var shouldShowSuggestionLoadingPill: Bool {
        normalizedAssistantSuggestionChips.isEmpty && isSuggestionGenerationInFlight
    }

    private var composerPlaceholderText: String {
        guard showsAssistantSuggestions, let normalizedAssistantNextFocus else {
            return messageFieldPlaceholder
        }

        return normalizedAssistantNextFocus
    }

    private var actionIcon: String {
        switch primaryActionTitle {
        case "生成开场":
            return "sparkles"
        case "继续写":
            return "arrow.forward"
        case "修改这段":
            return "pencil"
        case "编辑这段":
            return "pencil"
        default:
            return "text.cursor"
        }
    }

    private var suggestionLoadingPill: some View {
        HStack(spacing: 6) {
            Text("建议生成中")
                .font(.system(size: 11.8, weight: .semibold, design: .default))
                .foregroundStyle(Color.vibeCanvasInkSoft)
                .lineLimit(1)

            Circle()
                .fill(Color.vibeCanvasAccent.opacity(0.32))
                .frame(width: 5.5, height: 5.5)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background {
            Capsule(style: .continuous)
                .fill(Color.vibeCanvasLift.opacity(0.56))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.vibeCanvasStroke.opacity(0.30), lineWidth: 1)
                )
        }
        .accessibilityLabel("建议生成中")
        .accessibilityHidden(false)
    }
}

private struct SubmitGlyph: View {
    let isThinking: Bool

    var body: some View {
        Group {
            if isThinking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(Color.vibeCanvasInk)
                    .frame(width: 34, height: 34)
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13.5, weight: .semibold, design: .default))
                    .foregroundStyle(Color.vibeCanvasInk)
                    .frame(width: 34, height: 34)
            }
        }
    }
}

private struct ComposerThinkingGlow: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.55 + 0.45 * sin(t * 1.0)
            let shimmer = 0.55 + 0.45 * sin(t * 0.62 + 1.15)
            let opacity = 0.34 + 0.22 * pulse

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24 * pulse),
                                Color.vibeCanvasAccent.opacity(0.18 * shimmer),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 18)
                    .offset(y: -10)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42 * pulse),
                                Color.vibeCanvasAccent.opacity(0.28 * shimmer),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
                    .blur(radius: 5)
            }
            .opacity(opacity)
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
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

private struct TwoRowFlowLayout: Layout {
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
