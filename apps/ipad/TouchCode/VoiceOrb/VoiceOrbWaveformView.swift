import SwiftUI

/// White rounded short pillars (8~12 bars) driven by smoothed audioLevel.
/// Plan §5.5: 6~10s drift is handled by parent, waveform itself is damped level.
/// Plan §29: 20-30Hz UI updates – parent ViewModel throttles, here we interpolate with 0.14s.
struct VoiceOrbWaveformView: View {
    var audioLevel: CGFloat
    var isProcessing: Bool = false
    var reduceMotion: Bool = false
    private let barCount = 9 // within 8-12 spec

    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        if isProcessing {
            processingDots
        } else {
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3.5, height: barHeight(index: i))
                        .opacity(barOpacity(index: i))
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.14), value: audioLevel)
                }
            }
            .frame(height: 22, alignment: .center)
        }
    }

    private var processingDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: processingDotSize(index: i), height: processingDotSize(index: i))
                    .opacity(0.92)
                    .scaleEffect(reduceMotion ? 1 : 0.85 + pulsePhase * 0.15 * sinFactor(index: i))
                    .animation(reduceMotion ? .none : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsePhase)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                pulsePhase = 1
            }
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        // Plan §5.5: damped level already applied in session (0.72/0.28). Here map to visual.
        let phases: [CGFloat] = [0.42, 0.68, 1.0, 0.86, 0.52, 0.74, 0.95, 0.63, 0.31]
        let phase = phases[index % phases.count]
        // idle when silent: small wobble, not flat
        if audioLevel < 0.02 {
            return index % 2 == 0 ? 5 : 3.5
        }
        let base: CGFloat = 4
        let modulated = base + CGFloat(audioLevel) * 18 * phase
        return max(3, min(22, modulated))
    }

    private func barOpacity(index: Int) -> Double {
        // Slight taper at edges for glass depth
        if index == 0 || index == barCount - 1 { return 0.72 }
        return 0.94
    }

    private func processingDotSize(index: Int) -> CGFloat { 5 }
    private func sinFactor(index: Int) -> CGFloat { CGFloat(sin(Double(index) * 0.9)) * 0.5 + 0.5 }
    private func processingOpacity(index: Int) -> Double { 0.7 }
}
