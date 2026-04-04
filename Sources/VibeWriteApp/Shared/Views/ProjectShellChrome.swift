import AppKit
import SwiftUI

enum ProjectSidebarPresentation {
    case column
    case drawer
}

struct ProjectSidebarShell<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let isExpanded: Bool
    let presentation: ProjectSidebarPresentation
    let accessibilityIdentifier: String
    let action: () -> Void
    private let content: Content

    init(
        title: String,
        subtitle: String,
        icon: String,
        isExpanded: Bool,
        presentation: ProjectSidebarPresentation = .drawer,
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isExpanded = isExpanded
        self.presentation = presentation
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
        self.action = action
    }

    var body: some View {
        Group {
            if isExpanded {
                sidebarBody
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var sidebarBody: some View {
        switch presentation {
        case .drawer:
            drawerBody
        case .column:
            columnBody
        }
    }

    private var drawerBody: some View {
        sidebarChrome(
            background: drawerBackground,
            contentPadding: 12
        )
    }

    private var columnBody: some View {
        sidebarChrome(
            background: columnBackground,
            contentPadding: 14
        )
    }

    private func sidebarChrome<Background: View>(
        background: Background,
        contentPadding: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: action) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 12.5, weight: .semibold, design: .default))
                        .foregroundStyle(Color.vibeCanvasInk)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 14.2, weight: .semibold, design: .default))
                            .foregroundStyle(Color.vibeCanvasInk)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundStyle(Color.vibeCanvasInkSoft)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 10)

                    Image(systemName: "chevron.left.2")
                        .font(.system(size: 9, weight: .semibold, design: .default))
                        .foregroundStyle(Color.vibeCanvasInkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityLabel(title)
            .accessibilityValue("收起")
            .padding(.horizontal, contentPadding)
            .padding(.vertical, 10)

            Divider()
                .opacity(presentation == .drawer ? 0.14 : 0.12)
                .padding(.leading, contentPadding)

            ScrollView(showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 11)
                    .padding(.bottom, 12)
                    .padding(.horizontal, contentPadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(background)
    }

    private var drawerBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.vibeCanvasRaised.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.03),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.softLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.vibeCanvasStroke.opacity(0.48), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 8)
    }

    private var columnBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.vibeCanvasRaised.opacity(0.98))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.028),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.softLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.vibeCanvasStroke.opacity(0.48), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 8)
    }
}

struct ProjectSidebarToggleButton: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let accessibilityIdentifier: String?
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        isOn: Bool,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .semibold, design: .default))
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isOn ? Color.vibeCanvasAccent.opacity(0.26) : Color.clear)
                }
                .foregroundStyle(isOn ? Color.vibeCanvasInk : Color.vibeCanvasInkSoft)
        }
        .buttonStyle(.plain)
        // 去掉系统默认的焦点环（浅/白色描边），否则会像还有一圈边框
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .modifier(OptionalAccessibilityIdentifierModifier(accessibilityIdentifier: accessibilityIdentifier))
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
