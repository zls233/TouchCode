import SwiftUI

/// Floating interactive glass object (Plan §23, §4-§7, §16-§18). Orb is fixed at anchor; selection moves highlight, not position.
struct VoiceOrbView: View {
    var state: VoiceOrbState
    var session: VoiceOrbSession?
    /// Container size for clamping anchor to visible area (Plan §28)
    var containerSize: CGSize = .zero
    var onCancel: () -> Void
    var onSubmit: () -> Void
    var onRetry: (() -> Void)? = nil
    var reduceMotion: Bool = false
    var reduceTransparency: Bool = false

    // Plan §5.1: 82pt default
    private let orbDiameter: CGFloat = 82
    // Plan §6: 58-68pt satellites
    private let satelliteDistance: CGFloat = 64

    var body: some View {
        if let session, state.isVisible {
            VStack(spacing: 10) {
                // Plan §7: transcript 44-72pt above orb, centered, 2-3 lines
                VoiceOrbTranscriptView(text: session.transcript, reduceTransparency: reduceTransparency)
                    .opacity(transcriptOpacity)
                    .padding(.bottom, 34) // 44-72pt effective gap (12 VStack + 34)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))

                HStack(alignment: .center, spacing: 0) {
                    VoiceOrbActionButton(kind: .cancel, highlighted: session.selection == .cancel, reduceMotion: reduceMotion, action: onCancel)
                        .opacity(showSatellites ? 1 : 0)
                        .scaleEffect(showSatellites ? 1 : 0.8)
                    ZStack {
                        VoiceOrbGlassBackground(state: state, selection: session.selection, reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                        VoiceOrbWaveformView(audioLevel: session.audioLevel,
                                             isProcessing: state == .processing,
                                             reduceMotion: reduceMotion)
                    }
                    .frame(width: orbDiameter, height: orbDiameter)
                    .scaleEffect(orbScale)
                    .opacity(orbOpacity)
                    .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                    // Processing glow
                    .shadow(color: state == .processing ? .cyan.opacity(0.22) : .clear, radius: state == .processing ? 14 : 0)
                    .animation(orbSpring, value: state)
                    .animation(orbSpring, value: session.selection)
                    .padding(.horizontal, satelliteDistance - 24)
                    VoiceOrbActionButton(kind: .submit, highlighted: session.selection == .submit, reduceMotion: reduceMotion, action: onSubmit)
                        .opacity(showSatellites ? 1 : 0)
                        .scaleEffect(showSatellites ? 1 : 0.8)
                }

                // Plan §16-18: processing / error / success extras
                Group {
                    switch state {
                    case .processing:
                        Text("Working…")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    case .error(let msg):
                        VStack(spacing: 8) {
                            Text(msg)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.red.opacity(0.88), in: Capsule())
                            if let onRetry {
                                HStack(spacing: 10) {
                                    Button("Retry", action: onRetry)
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .tint(.blue)
                                    Button("Cancel", action: onCancel)
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    default:
                        EmptyView()
                    }
                }
                .padding(.top, 6)
            }
            .position(x: clampedX(session.anchor.x), y: clampedY(session.anchor.y))
            .transition(appearTransition)
            .zIndex(10)
            .allowsHitTesting(state != .processing && state != .success)
        }
    }

    // Plan §4: scale 0.72→1, opacity 0→1, blur 10→0, duration 180-240ms + haptic in ViewModel
    private var appearTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.72).combined(with: .opacity)
    }

    private var orbSpring: Animation {
        reduceMotion ? .linear(duration: 0.18) : .spring(response: 0.32, dampingFraction: 0.78)
    }

    private var orbScale: CGFloat {
        switch state {
        case .activating: return 0.96
        case .success: return 1.08
        case .processing: return 0.98
        case .dismissing: return 0.88
        default: return 1
        }
    }
    private var orbOpacity: Double {
        switch state {
        case .dismissing: return 0
        case .success: return 0 // will be faded by transition
        default: return 1
        }
    }
    private var transcriptOpacity: Double {
        switch state {
        case .processing: return 0.55
        case .success: return 0
        case .error: return 1
        default: return 1
        }
    }
    private var showSatellites: Bool {
        switch state {
        case .processing, .success: return false
        default: return true
        }
    }

    // Plan §28: clamp to keep orb+satellites visible; 130 horizontal, 120 vertical from original
    private func clampedX(_ x: CGFloat) -> CGFloat {
        guard containerSize.width > 0 else { return x }
        let margin: CGFloat = 130
        return min(max(x, margin), containerSize.width - margin)
    }
    private func clampedY(_ y: CGFloat) -> CGFloat {
        guard containerSize.height > 0 else { return y }
        let margin: CGFloat = 120
        // Also account for transcript height (~60) above orb
        return min(max(y, margin + 36), containerSize.height - margin)
    }
}
