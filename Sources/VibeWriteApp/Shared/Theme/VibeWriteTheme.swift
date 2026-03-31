import SwiftUI
import AppKit

extension Color {
    static let vibeAccent = Color(red: 0.13, green: 0.45, blue: 0.95)
    static let vibeAccentSoft = Color(red: 0.18, green: 0.73, blue: 0.66)
    static let vibeInk = Color(red: 0.10, green: 0.13, blue: 0.18)
}

struct AppBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.vibeAccent.opacity(0.08),
                    Color.clear,
                    Color.vibeAccentSoft.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.vibeAccent.opacity(0.10))
                .blur(radius: 120)
                .offset(x: 420, y: -300)

            Circle()
                .fill(Color.vibeAccentSoft.opacity(0.08))
                .blur(radius: 140)
                .offset(x: -420, y: 260)
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
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 10)
            }
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .default))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(.secondary)
        }
    }
}

struct AccentPill: View {
    let title: String
    var icon: String?
    var tint: Color = .vibeAccent
    var accessibilityIdentifier: String? = nil

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let icon {
                Image(systemName: icon)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .default))
        .foregroundStyle(tint)
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.10))
        }
        .accessibilityIdentifierIfPresent(accessibilityIdentifier)
    }
}

struct ActionChip: View {
    let title: String
    let tint: Color
    let accessibilityIdentifier: String?
    let action: () -> Void

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
                .foregroundStyle(tint)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background {
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.10))
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifierIfPresent(accessibilityIdentifier)
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
