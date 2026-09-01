import Foundation

/// Session captures the spatial anchor and live signals for a single Voice Orb activation.
/// Anchor is locked at activation instant and never follows finger movement (Plan §2.1).
struct VoiceOrbSession: Equatable {
    var anchor: CGPoint
    var gestureOffset: CGSize = .zero
    var selection: VoiceOrbSelection = .neutral
    var transcript: String = ""
    var audioLevel: CGFloat = 0
    var smoothedLevel: CGFloat = 0
    var startedAt: Date = Date()

    /// Horizontal displacement from anchor in points.
    var dx: CGFloat { gestureOffset.width }

    mutating func update(offset: CGSize, threshold: CGFloat) {
        gestureOffset = offset
        if offset.width < -threshold {
            selection = .cancel
        } else if offset.width > threshold {
            selection = .submit
        } else {
            selection = .neutral
        }
    }

    mutating func updateAudioLevel(_ raw: CGFloat) {
        // Plan §5.5 damping: smoothed = prev*0.72 + current*0.28
        smoothedLevel = smoothedLevel * 0.72 + raw * 0.28
        audioLevel = smoothedLevel
    }
}
