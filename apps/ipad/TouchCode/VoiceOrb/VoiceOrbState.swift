import Foundation

/// Unified Voice Orb state machine: single source of truth for overlay visibility
/// and speech lifecycle. See Plan §11-12.
enum VoiceOrbState: Equatable {
    case hidden
    case detectingHold
    case activating
    case listening
    case transcribing
    case ready
    case submitting
    case processing
    case success
    case error(String)
    case dismissing

    var isVisible: Bool {
        switch self {
        case .hidden: return false
        default: return true
        }
    }

    var allowsGestureSelection: Bool {
        switch self {
        case .listening, .transcribing, .ready: return true
        default: return false
        }
    }
}

enum VoiceOrbSelection: Equatable {
    case neutral
    case cancel
    case submit
}
