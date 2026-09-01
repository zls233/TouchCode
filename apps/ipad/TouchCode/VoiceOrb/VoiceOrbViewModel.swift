import Foundation
import SwiftUI
import Combine

/// Single-state Voice Orb model. WorkspaceView observes this instead of scattered @State flags.
/// Implements Plan §11 state machine and §9 haptics.
@MainActor
final class VoiceOrbViewModel: ObservableObject {
    @Published var state: VoiceOrbState = .hidden
    @Published var session: VoiceOrbSession?
    @Published var debugInfo: String = ""

    private var cancellables = Set<AnyCancellable>()
    private var speech: SpeechInputController?

    // Threshold from Plan §2.2: 44pt
    let selectionThreshold: CGFloat = 44

    func attach(speech: SpeechInputController) {
        self.speech = speech
        speech.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }.store(in: &cancellables)
        // Bridge speech transcript -> session transcript + state
        speech.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.syncTranscript() }
            }.store(in: &cancellables)
    }

    func handleGesture(_ event: VoiceGestureEvent) {
        switch event {
        case .started(let center):
            var s = VoiceOrbSession(anchor: center)
            s.startedAt = Date()
            session = s
            state = .activating
            // Appear animation 180-240ms then listening
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                guard self.state == .activating else { return }
                self.state = .listening
                VoiceOrbHaptics.activated()
                await self.speech?.start()
            }
        case .changed(_, let translation, _):
            guard state.allowsGestureSelection, var sess = session else { return }
            let prev = sess.selection
            let offset = CGSize(width: translation, height: 0)
            sess.update(offset: offset, threshold: selectionThreshold)
            session = sess
            if prev != sess.selection && sess.selection != .neutral {
                VoiceOrbHaptics.selectionChanged()
            }
        case .ended(_, let decision):
            guard let sess = session else { return }
            // Map VoiceGestureDecision (neutral/cancel/send) to selection
            let sel: VoiceOrbSelection = decision == .cancel ? .cancel : decision == .send ? .submit : sess.selection
            var updated = sess
            updated.selection = sel
            session = updated
            switch sel {
            case .cancel:
                state = .dismissing
                Task { await speech?.cancel(); finalizeHidden() }
            case .submit:
                state = .submitting
                Task { await speech?.stopAndFinalize(); /* caller triggers AI submission */ }
            case .neutral:
                state = .ready
                Task { await speech?.stopAndFinalize() }
                // keep session for tap-to-confirm
            }
        case .cancelled:
            state = .dismissing
            Task { await speech?.cancel(); finalizeHidden() }
        }
    }

    func cancelTapped() {
        state = .dismissing
        Task { await speech?.cancel(); finalizeHidden() }
    }

    func submitTapped() async -> String? {
        await speech?.stopAndFinalize()
        if let t = session?.transcript.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            state = .submitting
            return t
        }
        // Fallback to speech controller transcript
        let combined = [speech?.transcript ?? "", speech?.volatileTranscript ?? ""].filter{!$0.isEmpty}.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !combined.isEmpty {
            state = .submitting
            return combined
        }
        state = .ready
        return nil
    }

    func enterProcessing() { state = .processing }
    func enterSuccess() {
        state = .success
        VoiceOrbHaptics.success()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            finalizeHidden()
        }
    }
    func enterError(_ msg: String) {
        state = .error(msg)
        VoiceOrbHaptics.error()
    }

    func dismiss() { finalizeHidden() }

    private func finalizeHidden() {
        state = .hidden
        session = nil
    }

    private func syncTranscript() {
        guard var sess = session, state == .listening || state == .transcribing || state == .ready else { return }
        let combined = [speech?.transcript ?? "", speech?.volatileTranscript ?? ""].filter{!$0.isEmpty}.joined(separator: " ")
        sess.transcript = combined
        // audioLevel with damping
        let raw = CGFloat(speech?.audioLevel ?? 0)
        sess.updateAudioLevel(raw)
        session = sess
        if !combined.isEmpty && state == .listening { state = .transcribing }
    }

    // Debug overlay string Plan §30
    var debugOverlay: String {
        let dx = session?.dx ?? 0
        let sel: String
        switch session?.selection {
        case .cancel: sel = "cancel"
        case .submit: sel = "submit"
        default: sel = "neutral"
        }
        return "Voice State: \(String(describing: state))\ndx: \(Int(dx))\nSelection: \(sel)\nAudio: \(String(format: "%.2f", session?.audioLevel ?? 0))\n"
    }
}
