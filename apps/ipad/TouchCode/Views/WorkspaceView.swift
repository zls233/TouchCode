import PencilKit
import SwiftUI
import UIKit

struct WorkspaceView: View {
    let session: PairedWorkspaceSession
    let bridgeURL: URL
    let onDisconnect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var glassNamespace
    @StateObject private var preview = PreviewController()
    @State private var drawing = PKDrawing()
    @State private var composerPresented = false
    @State private var settingsPresented = false
    @State private var instruction = ""
    @State private var runStatus = ""
    @State private var isRunning = false
    @State private var inputMode = "text"
    @State private var workspaceState: WorkspaceState = .browsing
    @State private var previewRevisionBeforeSubmit = 0
    @State private var expectedPreviewRevision: Int?
    @State private var appliedRunID: String?
    @State private var submittedDraftRevision: Int?
    @State private var edgeAuraVisible = false
    @State private var annotationDraft = AnnotationDraft()
    @State private var connectionState: BridgeConnectionState = .connected
    @StateObject private var speechInput = SpeechInputController()
    @StateObject private var voiceOrb = VoiceOrbViewModel()
    @FocusState private var composerFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewURL = URL(string: session.previewURL) {
                    PreviewWebView(url: previewURL, controller: preview, drawing: $drawing,
                                   drawingEnabled: !isRunning && preview.viewportReady,
                                   onViewportChange: handleViewportWillChange,
                                   onStrokeEnded: persistCurrentDrawing,
                                   onVoiceGesture: handleVoiceGesture)
                        .ignoresSafeArea()
                }

                VoiceOrbView(state: voiceOrb.state, session: voiceOrb.session,
                             containerSize: geometry.size,
                             onCancel: { Task { await cancelVoice() } },
                             onSubmit: { Task { await sendVoice() } },
                             onRetry: { Task { await retryVoice() } },
                             reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
                    .allowsHitTesting(voiceOrb.state.isVisible)
                // Debug overlay Plan §30 (debug builds)
                #if DEBUG
                if voiceOrb.state.isVisible {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voiceOrb.debugOverlay).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .position(x: 120, y: 100)
                    .allowsHitTesting(false)
                }
                #endif

                if edgeAuraVisible {
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            AngularGradient(colors: [.blue, .cyan, .purple, .pink, .orange, .blue], center: .center),
                            lineWidth: 8
                        )
                        .blur(radius: reduceMotion ? 0 : 8)
                        .padding(3)
                        .allowsHitTesting(false)
                        .transition(reduceMotion ? .identity : .opacity)
                }

                if !drawing.strokes.isEmpty && !composerPresented {
                    annotationPromptButton(in: geometry.size)
                }

                VStack(spacing: 12) {
                    Spacer()
                    if connectionState != .connected { connectionBanner }
                    if !runStatus.isEmpty { statusToast }
                    if composerPresented { commandComposer }
                    controlDock
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .onDisappear {
            speechInput.stop()
        }
        .task { await speechInput.prepareModel() }
        .task { voiceOrb.attach(speech: speechInput) }
        .task { await monitorSession() }
        .statusBarHidden(true)
        .sheet(isPresented: $settingsPresented) { settingsSheet }
        .onChange(of: preview.previewRevision) { _, revision in
            if workspaceState == .awaitingPreview,
                appliedRunID != nil,
                revision > previewRevisionBeforeSubmit,
                isExpectedPreviewRevisionSatisfied(localRevision: revision) {
                 clearAppliedDraft()
                 // Plan §17: success animation after preview confirms
                 if voiceOrb.state == .processing || voiceOrb.state == .submitting {
                     voiceOrb.enterSuccess()
                 }
            }
        }
        .onChange(of: preview.viewportReady) { _, ready in
            guard ready, let frame = preview.readyFrame else { return }
            drawing = annotationDraft.drawing(for: frame.viewportKey) ?? PKDrawing()
        }
    }

    private func annotationPromptButton(in size: CGSize) -> some View {
        Button {
            composerPresented = true
            workspaceState = .composing
            composerFocused = true
        } label: {
            Group {
                if isRunning {
                    ProgressView()
                } else {
                    Image(systemName: "text.bubble.fill")
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: Circle())
        .glassEffectID("prompt", in: glassNamespace)
        .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
        .position(promptPosition(in: size))
        .accessibilityLabel("Describe this change")
    }

    private var commandComposer: some View {
        HStack(spacing: 10) {
            Image(systemName: "scribble.variable")
                .foregroundStyle(.red)
            TextField("What should change here?", text: $instruction, axis: .vertical)
                .focused($composerFocused)
                .lineLimit(1...3)
                .submitLabel(.send)
                .onSubmit { Task { await submit() } }
                .onChange(of: instruction) { _, newValue in
                    if !speechInput.isRecording && newValue != speechInput.transcript {
                        inputMode = "text"
                    }
                }
            Button {
                Task { await speechInput.toggle() }
            } label: {
                Image(systemName: speechInput.isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.title3)
                    .foregroundStyle(speechInput.isRecording ? .red : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speechInput.isRecording ? "Stop voice input" : "Start voice input")
            .disabled(isRunning)
            Button {
                composerPresented = false
                composerFocused = false
                workspaceState = drawing.strokes.isEmpty ? .browsing : .drafting
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button {
                Task { await submit() }
            } label: {
                if isRunning {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .fontWeight(.bold)
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: 680)
        .background(reduceTransparency ? Color(.systemBackground) : Color.clear, in: Capsule())
        .background(.regularMaterial.opacity(reduceTransparency ? 0 : 1), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(reduceTransparency ? 1 : 0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .onChange(of: speechInput.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            instruction = transcript
            inputMode = "voice"
        }
        .onChange(of: speechInput.errorMessage) { _, message in
            if let message { runStatus = message }
        }
    }

    private var controlDock: some View {
        HStack {
            Spacer()
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    if !drawing.strokes.isEmpty || !annotationDraft.captures.isEmpty {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isRunning {
                                ProgressView().frame(width: 28, height: 28)
                            } else {
                                Label("Update", systemImage: "paperplane.fill")
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .frame(height: 48)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, isRunning ? 10 : 8)
                        .glassEffect(.regular.tint(.blue).interactive(), in: Capsule())
                        .glassEffectID("update", in: glassNamespace)
                        .disabled(isRunning)
                        .accessibilityLabel("Update webpage")
                    }

                    Button {
                        settingsPresented = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .glassEffectID("settings", in: glassNamespace)
                    .disabled(isRunning)
                    .accessibilityLabel("TouchCode settings")
                }
            }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Status", value: connectionLabel)
                    LabeledContent("Session", value: String(session.sessionId.prefix(8)))
                    Button("Reload preview", systemImage: "arrow.clockwise") { preview.reload() }
                }
                Section("Annotations") {
                    LabeledContent("Captured viewports", value: "\(annotationDraft.captures.count) / 8")
                    Button("Clear annotations", systemImage: "trash", role: .destructive) {
                        drawing = PKDrawing()
                        annotationDraft.removeAll()
                        runStatus = ""
                        workspaceState = .browsing
                    }
                    .disabled(drawing.strokes.isEmpty && annotationDraft.captures.isEmpty)
                }
                Section("Voice") {
                    LabeledContent("Language", value: Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier)
                    LabeledContent("On-device model", value: speechModelLabel)
                    Button("Voice instruction", systemImage: "mic.fill") {
                        settingsPresented = false
                        workspaceState = .recording
                        voiceOrb.handleGesture(.started(CGPoint(x: 520, y: 420)))
                    }
                }
                Section {
                    Button("Disconnect", role: .destructive) { onDisconnect() }
                }
            }
            .navigationTitle("TouchCode")
        }
    }

    private var connectionLabel: String {
        switch connectionState {
        case .connected: "Connected"
        case .unreachable: "Bridge unreachable"
        case .stopped: "Session stopped"
        case .credentialsRejected: "Credentials rejected"
        }
    }

    private var connectionBanner: some View {
        Text(connectionLabel)
            .font(.footnote.weight(.medium))
            .foregroundStyle(connectionState == .stopped ? .orange : .secondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
    }

    private func monitorSession() async {
        var delay: UInt64 = 5_000_000_000
        while !Task.isCancelled {
            do {
                let current = try await TouchCodeAPIClient(bridgeURL: bridgeURL).heartbeat(session: session)
                connectionState = current.status == "stopped" ? .stopped : .connected
                delay = 5_000_000_000
            } catch let error as BridgeError {
                if case .requestFailed(_, let statusCode) = error, statusCode == 410 {
                    connectionState = .stopped
                    break
                }
                if case .requestFailed(_, let statusCode) = error, statusCode == 401 || statusCode == 403 {
                    connectionState = .credentialsRejected
                    break
                }
                connectionState = .unreachable
                delay = min(delay * 2, 30_000_000_000)
            } catch {
                connectionState = .unreachable
                delay = min(delay * 2, 30_000_000_000)
            }
            try? await Task.sleep(nanoseconds: delay)
        }
    }

    private var speechModelLabel: String {
        switch speechInput.modelStatus {
        case .idle: "Not prepared"
        case .preparing: "Preparing…"
        case .ready: "Ready"
        case .unavailable: "Unavailable"
        case .failed(let message): "Failed: \(message)"
        }
    }

    private var statusToast: some View {
        Text(runStatus)
            .font(.footnote)
            .lineLimit(3)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 620)
            .background(reduceTransparency ? Color(.systemBackground) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
            .background(.regularMaterial.opacity(reduceTransparency ? 0 : 1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func promptPosition(in size: CGSize) -> CGPoint {
        let bounds = drawing.bounds
        return CGPoint(
            x: min(max(bounds.midX, 34), size.width - 34),
            y: min(max(bounds.maxY + 30, 54), size.height - 120)
        )
    }

    private func submit() async {
        guard connectionState == .connected else {
            runStatus = connectionLabel
            return
        }
        let request = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !drawing.strokes.isEmpty || !annotationDraft.captures.isEmpty || (!request.isEmpty && inputMode == "voice") else { return }
        isRunning = true
        if reduceMotion {
            edgeAuraVisible = true
        } else {
            withAnimation(.easeOut(duration: 0.2)) { edgeAuraVisible = true }
        }
        workspaceState = .submitting
        voiceOrb.enterProcessing()
        previewRevisionBeforeSubmit = preview.previewRevision
        composerFocused = false
        runStatus = "Sending the marked screenshot to Codex…"
        defer { isRunning = false }

        do {
            persistCurrentDrawing()
            if annotationDraft.captures.isEmpty, inputMode == "voice", let frame = preview.readyFrame {
                _ = annotationDraft.append(preview.cleanCapture(frame: frame), drawing: PKDrawing())
            }
            guard !annotationDraft.captures.isEmpty else { throw DraftError.viewportNotReady }
            let combinedCapture = VisualCapture(captures: annotationDraft.compressedCaptures())
            submittedDraftRevision = annotationDraft.revision
            let result = try await TouchCodeAPIClient(bridgeURL: bridgeURL).runVisual(
                session: session,
                capture: combinedCapture,
                instruction: request,
                inputMode: request.isEmpty ? "annotation" : inputMode
            )
            // A 202 only means the Bridge accepted the draft. Draft state stays
            // intact until the event stream reports an applied outcome and the
            // preview emits a newer HMR revision.
            let terminal = try await TouchCodeAPIClient(bridgeURL: bridgeURL).awaitTerminalRun(
                session: session,
                runId: result.runId
            )
            switch terminal.outcome {
            case "applied":
                appliedRunID = terminal.runId
                expectedPreviewRevision = terminal.previewRevision.flatMap { Int($0) }
                workspaceState = .awaitingPreview
                runStatus = "Code updated. Waiting for the live preview…"
                if preview.previewRevision > previewRevisionBeforeSubmit,
                   isExpectedPreviewRevisionSatisfied(localRevision: preview.previewRevision) {
                    clearAppliedDraft()
                    voiceOrb.enterSuccess()
                }
            case "needs_clarification":
                let question = terminal.clarificationQuestion ?? terminal.summary
                workspaceState = .needsClarification(question)
                runStatus = question
                voiceOrb.enterError(question)
            case "no_change":
                workspaceState = .failed(terminal.summary)
                runStatus = terminal.summary
                voiceOrb.enterError(terminal.summary)
            default:
                workspaceState = .failed(terminal.summary)
                runStatus = "Codex failed: \(terminal.summary)"
                voiceOrb.enterError(terminal.summary)
            }
        } catch {
            if case BridgeError.requestFailed(_, let statusCode) = error, statusCode == 410 {
                connectionState = .stopped
                runStatus = "The TouchCode session stopped. Your annotations were kept."
                workspaceState = .failed(runStatus)
                voiceOrb.enterError(runStatus)
                return
            }
            runStatus = error.localizedDescription
            workspaceState = .failed(error.localizedDescription)
            voiceOrb.enterError(error.localizedDescription)
        }
    }

    private func clearAppliedDraft() {
        guard submittedDraftRevision == annotationDraft.revision else {
            appliedRunID = nil
            expectedPreviewRevision = nil
            submittedDraftRevision = nil
            workspaceState = .drafting
            runStatus = "The submitted change is live. New annotations were kept."
            if voiceOrb.state == .processing { voiceOrb.enterSuccess() }
            return
        }
        instruction = ""
        drawing = PKDrawing()
        annotationDraft.removeAll()
        composerPresented = false
        appliedRunID = nil
        expectedPreviewRevision = nil
        submittedDraftRevision = nil
        workspaceState = .browsing
        runStatus = "Updated in the live preview."
        // Success haptic + fade handled by voiceOrb; ensure processing -> success if not already
        if voiceOrb.state == .processing || voiceOrb.state == .submitting {
            voiceOrb.enterSuccess()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if reduceMotion {
                edgeAuraVisible = false
            } else {
                withAnimation(.easeIn(duration: 0.2)) { edgeAuraVisible = false }
            }
        }
    }

    private func isExpectedPreviewRevisionSatisfied(localRevision: Int) -> Bool {
        guard let expected = expectedPreviewRevision else {
            // Backwards compatibility: older Bridge still returns UUID string which Int(_) == nil.
            // Fall back to the previous "any HMR after submit" heuristic.
            return true
        }
        return localRevision >= expected && localRevision > previewRevisionBeforeSubmit
    }

    private func persistCurrentDrawing() {
        guard !drawing.strokes.isEmpty, let frame = preview.readyFrame else { return }
        do {
            let capture = try preview.annotatedCapture(drawing: drawing, frame: frame)
            if !annotationDraft.append(capture, drawing: drawing) {
                runStatus = "最多只能标注 8 个视口，请先提交或清除草稿。"
                workspaceState = .failed(runStatus)
            } else {
                workspaceState = .drafting
            }
        } catch {
            runStatus = error.localizedDescription
            workspaceState = .failed(error.localizedDescription)
        }
    }

    private func handleViewportWillChange() {
        persistCurrentDrawing()
        drawing = PKDrawing()
    }

    private var combinedSpeechTranscript: String {
        [speechInput.transcript, speechInput.volatileTranscript]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func handleVoiceGesture(_ event: VoiceGestureEvent) {
        // Anchor-locked orb per Plan §2.1; selection only via dx (Plan §2.2).
        voiceOrb.handleGesture(event)
        switch event {
        case .started:
            workspaceState = .recording
        case .changed:
            break // haptic already handled in ViewModel on selection change
        case .ended(_, let decision):
            if decision == .cancel {
                Task { await cancelVoice() }
            } else if decision == .send {
                Task { await sendVoice() }
            } else {
                // Neutral release -> ready state (Plan §10C)
                Task {
                    // ViewModel already stopped recording and set .ready
                    workspaceState = .voiceConfirmation
                    runStatus = "Tap ↑ to send or × to cancel."
                }
            }
        case .cancelled:
            Task { await cancelVoice() }
        }
    }

    private func cancelVoice() async {
        voiceOrb.cancelTapped()
        await speechInput.cancel()
        workspaceState = drawing.strokes.isEmpty ? .browsing : .drafting
    }

    private func sendVoice() async {
        let combined = combinedSpeechTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prefer ViewModel session transcript but fallback to combined
        let text: String
        if let t = await voiceOrb.submitTapped(), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = t
        } else {
            await speechInput.stopAndFinalize()
            text = combined
        }
        guard !text.isEmpty else {
            runStatus = "No speech was detected. Your annotations were kept."
            workspaceState = .voiceConfirmation
            voiceOrb.enterError("No speech was detected.")
            return
        }
        instruction = text
        inputMode = "voice"
        await submit()
    }

    private func retryVoice() async {
        // Error state keeps transcript, allow resubmit
        let t = voiceOrb.session?.transcript ?? combinedSpeechTranscript
        let text = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            voiceOrb.retry()
            return
        }
        voiceOrb.retry()
        instruction = text
        inputMode = "voice"
        await submit()
    }

}

private enum DraftError: LocalizedError {
    case viewportNotReady
    var errorDescription: String? { "The preview is still stabilizing. Your annotations were kept; try again." }
}
