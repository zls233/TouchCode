import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var workspace: WorkspaceStore
    @Binding var isPresented: Bool
    @State private var step = 0

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $step) {
                welcomeStep.tag(0)
                projectStep.tag(1)
                agentStep.tag(2)
                ipadStep.tag(3)
            }
            .tabViewStyle(.automatic)
            .frame(minHeight: 320)

            HStack {
                Button("Skip") { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.bordered)
                }
                Button(step == 3 ? "Done" : "Next") {
                    if step == 3 {
                        isPresented = false
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 480)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { isPresented = false }
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Welcome to TouchCode")
                .font(.title2.weight(.semibold))
            Text("TouchCode connects your iPad to the coding tools on this Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Your iPad stays the primary place for Pencil, preview and intent. This Mac provides project, connection and agent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var projectStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Choose a Project")
                .font(.title2.weight(.semibold))
            Text("TouchCode works with a local project on this Mac.")
                .foregroundStyle(.secondary)
            if workspace.projectPath == "No project selected" || workspace.projectPath.isEmpty {
                Button("Choose Project…") {
                    Task { await workspace.chooseProject() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                LabeledContent("Selected", value: (workspace.projectPath as NSString).lastPathComponent)
                Text(workspace.projectPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
    }

    private var agentStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Coding Agent")
                .font(.title2.weight(.semibold))
            if workspace.selectedCodingAgent.isImplemented && workspace.bridgeStatus != .disconnected {
                Label("Codex is ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Detected automatically · Project access available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Codex not available", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("TouchCode needs Codex on this Mac to perform code changes.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Set Up Codex") {
                    if let url = URL(string: "https://github.com/openai/codex") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var ipadStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "ipad.and.iphone")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Ready for your iPad")
                .font(.title2.weight(.semibold))
            Text("Open TouchCode on your iPad to connect. Keep both devices on the same local network.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if workspace.ipadConnected, let session = workspace.demoSession {
                Label("Connected to iPad", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Pairing code: \(session.pairingCode)")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            Text("Local Network permission will be requested when needed to find your Mac automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
