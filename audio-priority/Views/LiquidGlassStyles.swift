import SwiftUI

enum LiquidGlassMetrics {
    static let popoverWidth: CGFloat = 328
    static let outerPadding: CGFloat = 8
    static let sectionSpacing: CGFloat = 8
    static let panelPadding: CGFloat = 10
    static let panelCornerRadius: CGFloat = 16
    static let controlCornerRadius: CGFloat = 8
    static let iconButtonSize: CGFloat = 26
    static let audioIconSize: CGFloat = 18
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
    var symbolSize: CGFloat = 12

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
        content.background(
            rowBackground,
            in: RoundedRectangle(
                cornerRadius: LiquidGlassMetrics.controlCornerRadius,
                style: .continuous
            )
        )
    }

    private var rowBackground: Color {
        if isProminent {
            return .accentColor.opacity(0.16)
        }
        return .primary.opacity(isActive ? 0.07 : 0)
    }
}

extension View {
    func liquidGlassPanel(cornerRadius: CGFloat) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassRowBackground(isActive: Bool, isProminent: Bool = false) -> some View {
        modifier(LiquidGlassRowBackgroundModifier(isActive: isActive, isProminent: isProminent))
    }

    func liquidGlassIconButtonStyle() -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .foregroundStyle(.secondary)
    }
}
