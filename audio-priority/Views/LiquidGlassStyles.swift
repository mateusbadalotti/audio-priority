import SwiftUI

enum LiquidGlassMetrics {
    static let popoverWidth: CGFloat = 328
    static let outerPadding: CGFloat = 8
    static let sectionSpacing: CGFloat = 10
    static let panelCornerRadius: CGFloat = 16
    static let controlCornerRadius: CGFloat = 12
    static let iconButtonSize: CGFloat = 26
    static let audioIconSize: CGFloat = 22
    static let compactAudioIconSize: CGFloat = 20
}

struct LiquidGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(
        spacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

struct LiquidGlassAudioIcon: View {
    let systemName: String
    var size: CGFloat = LiquidGlassMetrics.audioIconSize
    var symbolSize: CGFloat = 11

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ResponsivePlainButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay(
                shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct LiquidGlassRowBackgroundModifier: ViewModifier {
    let isActive: Bool
    let isProminent: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: LiquidGlassMetrics.controlCornerRadius,
            style: .continuous
        )

        content
            .background(
                rowBackground,
                in: shape
            )
            .overlay(
                shape.strokeBorder(rowBorder, lineWidth: 1)
            )
    }

    private var rowBackground: Color {
        if isProminent {
            return .green.opacity(0.18)
        }
        return .primary.opacity(isActive ? 0.09 : 0.055)
    }

    private var rowBorder: Color {
        isProminent ? .green.opacity(0.28) : .primary.opacity(0.11)
    }
}

private struct LiquidGlassIconButtonStyleModifier: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if isProminent {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .foregroundStyle(.primary)
        } else {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    func liquidGlassPanel(cornerRadius: CGFloat) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassRowBackground(isActive: Bool, isProminent: Bool = false) -> some View {
        modifier(LiquidGlassRowBackgroundModifier(isActive: isActive, isProminent: isProminent))
    }

    func liquidGlassIconButtonStyle(isProminent: Bool = false) -> some View {
        modifier(LiquidGlassIconButtonStyleModifier(isProminent: isProminent))
    }
}
