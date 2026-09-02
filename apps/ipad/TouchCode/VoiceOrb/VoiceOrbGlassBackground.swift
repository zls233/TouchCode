import SwiftUI

/// Four-layer glass orb: base material, animated gradient, specular highlight, waveform slot.
/// Implements Plan §5.2-5.5. Drift period 8s (within 6-10s spec).
struct VoiceOrbGlassBackground: View {
    var state: VoiceOrbState
    var selection: VoiceOrbSelection
    var reduceMotion: Bool = false
    var reduceTransparency: Bool = false

    @State private var drift: CGFloat = 0

    var body: some View {
        ZStack {
            glassBase
            internalGradient
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
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle().stroke(.white.opacity(reduceTransparency ? 1 : 0.55), lineWidth: 1)
                )
            // Subtle outer glow for liquid-glass depth
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 1)
                .blur(radius: 0.6)
                .scaleEffect(1.02)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }

    @ViewBuilder
    private var internalGradient: some View {
        // Break MeshGradient expression to avoid type-check timeout
        let p00: SIMD2<Float> = [0, 0]
        let p10: SIMD2<Float> = [0.5, 0]
        let p20: SIMD2<Float> = [1, 0]
        let p01: SIMD2<Float> = [0, Float(0.5 + drift * 0.06)]
        let p11: SIMD2<Float> = [Float(0.5 + drift * 0.08), 0.5]
        let p21: SIMD2<Float> = [1, Float(0.5 - drift * 0.05)]
        let p02: SIMD2<Float> = [0, 1]
        let p12: SIMD2<Float> = [Float(0.5), Float(1 - drift * 0.04)]
        let p22: SIMD2<Float> = [1, 1]
        let points: [SIMD2<Float>] = [p00, p10, p20, p01, p11, p21, p02, p12, p22]

        // Base palette: pink/coral -> violet -> cyan/blue
        let cPink = Color(red: 1.0, green: 0.42, blue: 0.52).opacity(0.55)
        let cViolet = Color(red: 0.62, green: 0.45, blue: 0.92).opacity(0.45)
        let cCyan = Color(red: 0.22, green: 0.84, blue: 0.92).opacity(0.50)
        let cBlue = Color(red: 0.28, green: 0.48, blue: 0.98).opacity(0.45)
        let cMix = cPink.mix(with: cCyan, by: 0.5)

        // Opacity/intensity varies by state (Plan §5.4)
        let opacity: Double = {
            switch state {
            case .listening, .transcribing: return 0.72
            case .ready: return 0.38
            case .processing: return 0.75
            case .activating: return 0.58
            default: return 0.62
            }
        }()

        let colors: [Color] = [cPink, cViolet, cViolet, cViolet, cMix, cCyan, cViolet, cCyan, cBlue]

        // Horizontal magnetic bias: submit -> right glow, cancel -> left dim
        let magneticOffset: CGFloat = selection == .submit ? 6 : selection == .cancel ? -4 : 0
        let magneticScale: CGFloat = selection == .submit ? 1.06 : selection == .cancel ? 0.98 : 1

        MeshGradient(width: 3, height: 3, points: points, colors: colors)
            .opacity(opacity)
            .blur(radius: state == .processing ? 0.5 : 0)
            .scaleEffect(magneticScale)
            .offset(x: magneticOffset * 0.12 + drift * 2)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: selection)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.45), value: state)
    }

    private var highlightLayer: some View {
        Circle()
            .fill(
                RadialGradient(colors: [.white.opacity(0.48), .white.opacity(0.12), .clear],
                               center: .topLeading, startRadius: 2, endRadius: 54)
            )
            .blendMode(.plusLighter)
            .opacity(reduceTransparency ? 0 : 0.92)
        // Inner specular stroke
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 0.8)
                    .blur(radius: 0.4)
                    .offset(x: -0.5, y: -0.5)
            )
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
