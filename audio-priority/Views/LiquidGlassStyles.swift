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
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}

struct LiquidGlassAudioIcon: View {
    let systemName: String
    var tint: Color = .secondary
    var size: CGFloat = LiquidGlassMetrics.audioIconSize
    var symbolSize: CGFloat = 11

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(.primary.opacity(0.72))
            .frame(width: size, height: size)
            .glassEffect(
                .regular.tint(tint.opacity(0.14)),
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}

private struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .glassEffect(.regular, in: shape)
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
                isActive && !isProminent ? Color.primary.opacity(0.04) : Color.clear,
                in: shape
            )
            .glassEffect(
                rowGlass,
                in: shape
            )
    }

    private var rowGlass: Glass {
        if isProminent {
            return .regular.tint(.green.opacity(0.1))
        }
        return .clear
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
