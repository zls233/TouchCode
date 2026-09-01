import SwiftUI

/// Four-layer glass orb: base material, animated gradient, specular highlight, waveform slot.
/// Implements Plan §5.1-5.5.
struct VoiceOrbGlassBackground: View {
    var state: VoiceOrbState
    var selection: VoiceOrbSelection
    var reduceMotion: Bool = false
    var reduceTransparency: Bool = false

    @State private var drift: CGFloat = 0

    var body: some View {
        ZStack {
            glassBase
            animatedGradient
            highlightLayer
        }
        .clipShape(Circle())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: true)) {
                drift = 1
            }
        }
    }

    private var glassBase: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle().stroke(.white.opacity(reduceTransparency ? 1 : 0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private var animatedGradient: some View {
        // Plan §5.4: subtle drift 6-10s, pink/violet/cyan/blue
        // Simplified to Linear gradient to avoid MeshGradient type-check timeout
        let base = LinearGradient(colors: [.pink.opacity(0.45), .purple.opacity(0.45), .cyan.opacity(0.42), .blue.opacity(0.38)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        return Circle()
            .fill(base)
            .opacity(state == .processing ? 0.75 : 0.62)
            .offset(x: drift * 4, y: drift * -2)
            .blur(radius: state == .processing ? 0.5 : 0)
            .scaleEffect(selection == .submit ? 1.06 : selection == .cancel ? 0.98 : 1)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: selection)
    }

    private var highlightLayer: some View {
        Circle()
            .fill(
                RadialGradient(colors: [.white.opacity(0.45), .clear], center: .topLeading, startRadius: 2, endRadius: 52)
            )
            .blendMode(.plusLighter)
            .opacity(reduceTransparency ? 0 : 0.9)
    }
}

private extension Color {
    func mix(with other: Color, by t: Double) -> Color {
        UIColor(self).mix(with: UIColor(other), by: t).map { Color($0) } ?? self
    }
}

private extension UIColor {
    func mix(with other: UIColor, by t: Double) -> UIColor? {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return nil }
        return UIColor(red: r1 + (r2 - r1) * CGFloat(t),
                       green: g1 + (g2 - g1) * CGFloat(t),
                       blue: b1 + (b2 - b1) * CGFloat(t),
                       alpha: a1 + (a2 - a1) * CGFloat(t))
    }
}
