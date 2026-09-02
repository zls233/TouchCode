import Foundation

/// Connects Voice transcript + Pencil annotations + viewport context into a single AI update request.
/// Plan §15: VoiceOrb -> InteractionCoordinator -> AIUpdateRequest -> Bridge/Codex
struct AIUpdateRequest {
    let transcript: String
    let annotations: [AnnotationCapture]
    let viewportContext: ReadyViewportFrame?
    let pageURL: String

    var instruction: String { transcript }
    var visualCapture: VisualCapture { VisualCapture(captures: annotations) }
}

@MainActor
final class VoiceInteractionCoordinator: ObservableObject {
    let voiceModel: VoiceOrbViewModel
    private let preview: PreviewController
    private var draft: AnnotationDraft

    init(voiceModel: VoiceOrbViewModel, preview: PreviewController, draft: AnnotationDraft) {
        self.voiceModel = voiceModel
        self.preview = preview
        self.draft = draft
    }

    func updateDraft(_ newDraft: AnnotationDraft) { draft = newDraft }

    func buildRequest(transcript: String) -> AIUpdateRequest? {
        guard let frame = preview.readyFrame else { return nil }
        var captures = draft.captures
        if captures.isEmpty {
            // Voice-only update: attach clean viewport capture (Plan §14)
            captures = [preview.cleanCapture(frame: frame)]
        }
        return AIUpdateRequest(transcript: transcript, annotations: captures, viewportContext: frame, pageURL: frame.url)
    }
}
