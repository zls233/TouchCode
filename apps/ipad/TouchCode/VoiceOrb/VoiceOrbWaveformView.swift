import SwiftUI

/// White rounded short pillars (8~12 bars) driven by smoothed audioLevel.
/// Updates at 20-30 Hz; parent throttles via animation, not per audio sample (Plan §5.5, §29).
struct VoiceOrbWaveformView: View {
    var audioLevel: CGFloat
    var isProcessing: Bool = false
    var reduceMotion: Bool = false
    private let barCount = 9

    var body: some View {
        if isProcessing {
            processingDots
        } else {
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 3.5, height: barHeight(index: i))
                        .opacity(0.92)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.14), value: audioLevel)
                }
            }
        }
    }

    private var processingDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 5, height: 5)
                    .opacity(processingOpacity(index: i))
            }
        }
    }

    private func barHeight(index: Int) -> CGFloat {
        // Base heights + audio modulation per bar with phase offset
        let base: CGFloat = 4
        let phases: [CGFloat] = [0.4, 0.7, 1.0, 0.85, 0.55, 0.75, 0.95, 0.65, 0.3]
        let phase = phases[index % phases.count]
        // audioLevel 0..1 maps to 4..22
        let modulated = base + CGFloat(audioLevel) * 18 * phase
        // Add subtle idle wobble when silent
        let idle: CGFloat = audioLevel < 0.02 ? (index % 2 == 0 ? 5 : 3) : modulated
        return max(3, min(22, audioLevel < 0.02 ? idle : modulated))
    }

    private func processingOpacity(index: Int) -> Double { 0.7 }

}
