import SwiftUI

/// Layout radii aligned with the current macOS window language.
enum RfredMetrics {
    /// Concentric window corners used by macOS 26+ (Liquid Glass era).
    static let windowRadius: CGFloat = 26
    static let controlRadius: CGFloat = 10
    static let highlightRadius: CGFloat = 10
    static let cardRadius: CGFloat = 12
    static let fieldRadius: CGFloat = 12
}

/// Glass surface helpers. On macOS 26+ these use the system Liquid Glass
/// effect; macOS 14–25 fall back to the previous material or flat look.
extension View {
    @ViewBuilder
    func rfredGlass(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(
                Glass.regular.tint(tint).interactive(interactive),
                in: shape
            )
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.45), lineWidth: 0.8))
        }
    }

    /// Launcher chrome: glass on macOS 26+ when the theme asks for it,
    /// otherwise the theme's existing material or flat fill.
    @ViewBuilder
    func rfredLauncherSurface(theme: LauncherTheme) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius, style: .continuous)
        if #available(macOS 26.0, *), theme.usesGlass {
            self
                .background(theme.background.opacity(0.42), in: shape)
                .glassEffect(.regular.tint(theme.background.opacity(0.32)), in: shape)
                .overlay(shape.strokeBorder(theme.border, lineWidth: 0.6))
                .shadow(color: .black.opacity(0.22), radius: 32, y: 14)
        } else {
            self
                .background {
                    shape
                        .fill(theme.background)
                        .background {
                            if theme.blur > 0 || theme.material != nil {
                                shape.fill(theme.material ?? .ultraThinMaterial)
                            }
                        }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(theme.border, lineWidth: 0.7))
                .shadow(color: .black.opacity(0.26), radius: 24, y: 12)
        }
    }

    /// Soft window fill used by Preferences. Glass-era systems get a faint
    /// aurora so sidebar and toolbar glass have something to refract.
    @ViewBuilder
    func rfredWindowFill() -> some View {
        if #available(macOS 26.0, *) {
            self.background { AuroraBackdrop() }
        } else {
            self.background(RfredColor.canvas)
        }
    }
}

extension View {
    /// Tinted glass column for the two-level sidebars.
    @ViewBuilder
    func rfredSidebar(tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            self.background {
                Rectangle()
                    .fill(tint.opacity(0.34))
                    .glassEffect(.regular.tint(tint.opacity(0.72)), in: Rectangle())
            }
        } else {
            self.background(tint)
        }
    }

    /// System-like sidebar for the preferences rail and lists.
    @ViewBuilder
    func rfredSystemSidebar() -> some View {
        if #available(macOS 26.0, *) {
            self.background {
                Rectangle()
                    .fill(RfredColor.prefsRail.opacity(0.55))
                    .glassEffect(.regular.tint(RfredColor.prefsRail.opacity(0.8)), in: Rectangle())
            }
        } else {
            self.background(RfredColor.prefsRail)
        }
    }
}

/// Applies the system glass button style where available.
struct GlassButtons: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content
        }
    }
}

/// A soft, low-contrast aurora used behind the preferences content so the
/// glass surfaces have something to refract. Deliberately subtle.
struct AuroraBackdrop: View {
    var body: some View {
        ZStack {
            RfredColor.canvas
            RadialGradient(
                colors: [Color(hex: 0x8E2BB8).opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 30,
                endRadius: 760
            )
            RadialGradient(
                colors: [Color(hex: 0x2E6BFF).opacity(0.09), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 820
            )
            RadialGradient(
                colors: [Color(hex: 0x00B8A9).opacity(0.07), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 620
            )
        }
        .allowsHitTesting(false)
    }
}
