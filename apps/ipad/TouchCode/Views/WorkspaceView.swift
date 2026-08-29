import PencilKit
import SwiftUI

struct WorkspaceView: View {
    let session: DemoSession
    let bridgeURL: URL
    @StateObject private var preview = PreviewController()
    @State private var drawing = PKDrawing()
    @State private var annotationEnabled = true
    @State private var composerPresented = false
    @State private var instruction = ""
    @State private var runStatus = ""
    @State private var isRunning = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let previewURL = URL(string: session.previewURL) {
                    PreviewWebView(url: previewURL, controller: preview)
                        .ignoresSafeArea()
                }

                PencilOverlay(drawing: $drawing, isEnabled: annotationEnabled && !isRunning)
                    .ignoresSafeArea()
                    .allowsHitTesting(annotationEnabled && !isRunning)

                if !drawing.strokes.isEmpty && !composerPresented {
                    annotationPromptButton(in: geometry.size)
                }

                VStack(spacing: 12) {
                    Spacer()
                    if !runStatus.isEmpty { statusToast }
                    if composerPresented { commandComposer }
                    controlDock
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
        }
    }

    private func annotationPromptButton(in size: CGSize) -> some View {
        Button {
            composerPresented = true
            composerFocused = true
        } label: {
            Group {
                if isRunning {
                    ProgressView()
                } else {
                    Image(systemName: "text.bubble.fill")
                }
            }
            .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
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
            Button {
                composerPresented = false
                composerFocused = false
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
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }

    private var controlDock: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                Button {
                    annotationEnabled.toggle()
                    composerPresented = false
                } label: {
                    Image(systemName: annotationEnabled ? "pencil.tip.crop.circle.fill" : "hand.draw.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .accessibilityLabel(annotationEnabled ? "Drawing mode" : "Browsing mode")

                Button {
                    drawing = PKDrawing()
                    composerPresented = false
                    runStatus = ""
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(drawing.strokes.isEmpty || isRunning)
                .accessibilityLabel("Clear annotation")
            }
            .padding(6)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        }
    }

    private var statusToast: some View {
        Text(runStatus)
            .font(.footnote)
            .lineLimit(3)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func promptPosition(in size: CGSize) -> CGPoint {
        let bounds = drawing.bounds
        return CGPoint(
            x: min(max(bounds.midX, 34), size.width - 34),
            y: min(max(bounds.maxY + 30, 54), size.height - 120)
        )
    }

    private func submit() async {
        let request = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !drawing.strokes.isEmpty else { return }
        isRunning = true
        composerFocused = false
        runStatus = "Sending the marked screenshot to Codex…"
        defer { isRunning = false }

        do {
            let capture = try await preview.captureAnnotatedContext(drawing: drawing)
            let result = try await TouchCodeAPIClient(bridgeURL: bridgeURL).runVisual(
                session: session,
                capture: capture,
                instruction: request
            )
            if result.status == "succeeded" {
                runStatus = "Updated. The live page will refresh automatically."
                instruction = ""
                drawing = PKDrawing()
                composerPresented = false
            } else {
                runStatus = "Codex failed: \(result.summary)"
            }
        } catch {
            runStatus = error.localizedDescription
        }
    }
}
