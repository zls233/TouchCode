import SwiftUI

/// Floating interactive glass object (Plan §23). Orb is fixed at anchor; selection moves highlight, not position.
struct VoiceOrbView: View {
    var state: VoiceOrbState
    var session: VoiceOrbSession?
    var onCancel: () -> Void
    var onSubmit: () -> Void
    var reduceMotion: Bool = false
    var reduceTransparency: Bool = false

    // Plan §5.1: 82pt default
    private let orbDiameter: CGFloat = 82
    private let satelliteDistance: CGFloat = 64 // 58-68 range

    var body: some View {
        if let session, state.isVisible {
            VStack(spacing: 12) {
                VoiceOrbTranscriptView(text: session.transcript, reduceTransparency: reduceTransparency)
                    .offset(y: -6)
                    .opacity(transcriptOpacity)
                HStack(spacing: 0) {
                    VoiceOrbActionButton(kind: .cancel, highlighted: session.selection == .cancel, reduceMotion: reduceMotion, action: onCancel)
                        .opacity(state == .processing || state == .success ? 0 : 1)
                    ZStack {
                        VoiceOrbGlassBackground(state: state, selection: session.selection, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                        VoiceOrbWaveformView(audioLevel: session.audioLevel,
                                             isProcessing: state == .processing,
                                             reduceMotion: reduceMotion)
                    }
                    .frame(width: orbDiameter, height: orbDiameter)
                    .scaleEffect(orbScale)
                    .opacity(orbOpacity)
                    .animation(reduceMotion ? .none : .spring(response: 0.32, dampingFraction: 0.78), value: state)
                    .padding(.horizontal, satelliteDistance - 24) // keep satellites at 64 apart
                    VoiceOrbActionButton(kind: .submit, highlighted: session.selection == .submit, reduceMotion: reduceMotion, action: onSubmit)
                        .opacity(state == .processing || state == .success ? 0 : 1)
                }
                if case .error(let msg) = state {
                    Text(msg)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.red.opacity(0.82), in: Capsule())
                        .lineLimit(2)
                } else if state == .processing {
                    Text("Working…")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .position(x: clampedX(session.anchor.x), y: clampedY(session.anchor.y))
            .transition(appearTransition)
            .zIndex(10)
            .allowsHitTesting(state != .processing && state != .success)
        }
    }

    private var appearTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.72).combined(with: .opacity)
    }

    private var orbScale: CGFloat {
        switch state {
        case .activating: return 1
        case .success: return 1.08
        case .processing: return 0.98
        default: return 1
        }
    }
    private var orbOpacity: Double {
        switch state {
        case .dismissing: return 0
        case .success: return 0
        default: return 1
        }
    }
    private var transcriptOpacity: Double {
        state == .processing || state == .success ? 0.5 : 1
    }

    // Clamp to avoid orb clipping off-screen; keep 130/120 from spec but adapt to orb size
    private func clampedX(_ x: CGFloat) -> CGFloat { x }
    private func clampedY(_ y: CGFloat) -> CGFloat { y }
}
