import AppKit
import SwiftUI

enum VibeAppearanceMode: String, CaseIterable, Codable {
    case day
    case night

    var colorScheme: ColorScheme {
        switch self {
        case .day:
            return .light
        case .night:
            return .dark
        }
    }

    var toggleSymbolName: String {
        switch self {
        case .day:
            return "moon.stars"
        case .night:
            return "sun.max"
        }
    }

    var toggleTitle: String {
        switch self {
        case .day:
            return "切换夜间模式"
        case .night:
            return "切换日间模式"
        }
    }
}

enum VibeThemePalette {
    // Central accent tokens. Tune these values to shift the whole theme family.
    static let accent = Color(red: 0.93, green: 0.82, blue: 0.46)
    static let accentStrong = Color(red: 0.96, green: 0.84, blue: 0.38)
    static let accentMuted = Color(red: 0.77, green: 0.69, blue: 0.42)
    static let accentWarm = Color(red: 0.98, green: 0.76, blue: 0.30)

    static let accentNSColor = NSColor(calibratedRed: 0.94, green: 0.82, blue: 0.40, alpha: 1)
}

enum VibeCapsuleTone {
    case fixed
    case interactive
}

private func vibeDynamicNSColor(day: NSColor, night: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            return night
        default:
            return day
        }
    }
}

private func vibeDynamicColor(day: NSColor, night: NSColor) -> Color {
    Color(nsColor: vibeDynamicNSColor(day: day, night: night))
}

extension Color {
    static let vibeAccent = VibeThemePalette.accentStrong
    static let vibeAccentSoft = VibeThemePalette.accentMuted
    static let vibeAccentWarm = VibeThemePalette.accentWarm
    static let vibeBackdrop = vibeDynamicColor(
        day: NSColor(calibratedRed: 0.980, green: 0.968, blue: 0.930, alpha: 1),
        night: NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.965, alpha: 1)
    )
    static let vibeBackdropGlow = vibeDynamicColor(
        day: NSColor(calibratedRed: 1.000, green: 0.992, blue: 0.955, alpha: 1),
        night: NSColor(calibratedRed: 0.995, green: 0.987, blue: 0.945, alpha: 1)
    )
    static let vibePaper = Color(nsColor: .textBackgroundColor)
    static let vibeRail = Color(nsColor: .controlBackgroundColor)
    static let vibeStroke = Color(nsColor: .separatorColor)
    static let vibeInk = Color(red: 0.10, green: 0.12, blue: 0.16)
    static let vibeInkSoft = Color(red: 0.31, green: 0.34, blue: 0.40)
    static let vibeInkMuted = Color(red: 0.46, green: 0.49, blue: 0.55)

    static let vibeCanvas = vibeDynamicColor(
        day: NSColor(calibratedRed: 0.966, green: 0.949, blue: 0.905, alpha: 1),
        night: NSColor(calibratedRed: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
    )
    static let vibeCanvasRaised = vibeDynamicColor(
        day: NSColor(calibratedRed: 0.987, green: 0.972, blue: 0.935, alpha: 1),
        night: NSColor(calibratedRed: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
    )
    static let vibeCanvasLift = vibeDynamicColor(
        day: NSColor(calibratedRed: 0.954, green: 0.929, blue: 0.870, alpha: 1),
        night: NSColor(calibratedRed: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1)
    )
    static let vibeCanvasStroke = vibeDynamicColor(
        day: NSColor(calibratedRed: 0.860, green: 0.820, blue: 0.735, alpha: 1),
        night: NSColor(calibratedRed: 72 / 255, green: 72 / 255, blue: 74 / 255, alpha: 1)
    )
    static let vibeCanvasInk = vibeDynamicColor(
        day: NSColor(calibratedRed: 0.235, green: 0.205, blue: 0.150, alpha: 1),
        night: NSColor(calibratedRed: 0.958, green: 0.962, blue: 0.976, alpha: 1)
    )
    static let vibeCanvasInkSoft = vibeDynamicColor(
        day: NSColor(calibratedRed: 0.440, green: 0.390, blue: 0.310, alpha: 1),
        night: NSColor(calibratedRed: 0.76, green: 0.78, blue: 0.82, alpha: 1)
    )
    static let vibeCanvasInkMuted = vibeDynamicColor(
        day: NSColor(calibratedRed: 0.570, green: 0.520, blue: 0.440, alpha: 1),
        night: NSColor(calibratedRed: 0.54, green: 0.56, blue: 0.61, alpha: 1)
    )
    static let vibeCanvasAccent = VibeThemePalette.accent

    static func vibeCapsuleForeground(_ tone: VibeCapsuleTone, colorScheme: ColorScheme) -> Color {
        switch tone {
        case .fixed:
            return colorScheme == .light
                ? Color(red: 0.56, green: 0.43, blue: 0.20)
                : Color(red: 0.79, green: 0.70, blue: 0.48)
        case .interactive:
            return colorScheme == .light
                ? Color(red: 0.69, green: 0.54, blue: 0.26)
                : Color(red: 0.96, green: 0.84, blue: 0.50)
        }
    }

    static func vibeCapsuleBackground(
        _ tone: VibeCapsuleTone,
        tint: Color = .vibeAccent,
        colorScheme: ColorScheme
    ) -> Color {
        switch tone {
        case .fixed:
            return colorScheme == .light ? tint.opacity(0.20) : tint.opacity(0.14)
        case .interactive:
            return colorScheme == .light ? tint.opacity(0.26) : tint.opacity(0.19)
        }
    }

    static func vibeCapsuleStroke(_ tone: VibeCapsuleTone, colorScheme: ColorScheme) -> Color {
        switch tone {
        case .fixed:
            return colorScheme == .light
                ? Color.vibeCanvasStroke.opacity(0.22)
                : Color.vibeCanvasStroke.opacity(0.12)
        case .interactive:
            return colorScheme == .light
                ? Color.vibeCanvasStroke.opacity(0.26)
                : Color.vibeCanvasStroke.opacity(0.18)
        }
    }
}

extension NSColor {
    static let vibeAccent = vibeDynamicNSColor(
        day: NSColor(calibratedRed: 0.86, green: 0.70, blue: 0.28, alpha: 1),
        night: VibeThemePalette.accentNSColor
    )
    static let vibeCanvasInk = vibeDynamicNSColor(
        day: NSColor(calibratedRed: 0.235, green: 0.205, blue: 0.150, alpha: 1),
        night: NSColor(calibratedRed: 0.84, green: 0.85, blue: 0.88, alpha: 1)
    )
}

struct AppBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.vibeBackdrop,
                    Color(red: 0.968, green: 0.973, blue: 0.984)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.vibeBackdropGlow.opacity(0.85),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 620
            )

            RadialGradient(
                colors: [
                    Color.vibeAccent.opacity(0.065),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 760
            )
        }
        .ignoresSafeArea()
    }
}

struct ProjectBackdrop: View {
    var body: some View {
        ZStack {
            // 与正文区同一中性底色，仅用极弱明暗差避免发蓝、发灰紫
            LinearGradient(
                colors: [
                    vibeDynamicColor(
                        day: NSColor(calibratedRed: 0.978, green: 0.960, blue: 0.920, alpha: 1),
                        night: NSColor(calibratedRed: 30 / 255, green: 30 / 255, blue: 32 / 255, alpha: 1)
                    ),
                    Color.vibeCanvas,
                    vibeDynamicColor(
                        day: NSColor(calibratedRed: 0.958, green: 0.940, blue: 0.892, alpha: 1),
                        night: NSColor(calibratedRed: 26 / 255, green: 26 / 255, blue: 28 / 255, alpha: 1)
                    )
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.vibeAccent.opacity(0.08),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

struct VibeSurface<Content: View>: View {
    private let content: Content
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 26, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        content
            .padding(22)
                .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.vibePaper)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.24),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.softLight)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.vibeStroke.opacity(0.38), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 7)
            }
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 23, weight: .semibold, design: .default))
                .foregroundStyle(Color.vibeInk)

            Text(subtitle)
                .font(.system(size: 13.5, weight: .medium, design: .default))
                .foregroundStyle(Color.vibeInkSoft)
        }
    }
}

struct AccentPill: View {
    let title: String
    var icon: String?
    var tint: Color = .vibeAccent
    var accessibilityIdentifier: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let icon {
                Image(systemName: icon)
            }
        }
        .font(.system(size: 12.2, weight: .semibold, design: .default))
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
        .accessibilityIdentifierIfPresent(accessibilityIdentifier)
    }

    private var foregroundColor: Color {
        Color.vibeCapsuleForeground(.fixed, colorScheme: colorScheme)
    }

    private var backgroundColor: Color {
        Color.vibeCapsuleBackground(.fixed, tint: tint, colorScheme: colorScheme)
    }

    private var strokeColor: Color {
        Color.vibeCapsuleStroke(.fixed, colorScheme: colorScheme)
    }
}

struct ActionChip: View {
    let title: String
    let tint: Color
    let accessibilityIdentifier: String?
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, tint: Color = .vibeAccent, accessibilityIdentifier: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

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
        .accessibilityIdentifierIfPresent(accessibilityIdentifier)
    }

    private var foregroundColor: Color {
        Color.vibeCapsuleForeground(.interactive, colorScheme: colorScheme)
    }

    private var backgroundColor: Color {
        Color.vibeCapsuleBackground(.interactive, tint: tint, colorScheme: colorScheme)
    }

    private var strokeColor: Color {
        Color.vibeCapsuleStroke(.interactive, colorScheme: colorScheme)
    }
}

private struct OptionalAccessibilityIdentifierModifier: ViewModifier {
    let accessibilityIdentifier: String?

    func body(content: Content) -> some View {
        if let accessibilityIdentifier {
            content.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            content
        }
    }
}

private extension View {
    func accessibilityIdentifierIfPresent(_ accessibilityIdentifier: String?) -> some View {
        modifier(OptionalAccessibilityIdentifierModifier(accessibilityIdentifier: accessibilityIdentifier))
    }
}
