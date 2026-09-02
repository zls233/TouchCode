import SwiftUI
import AppKit

struct CodingAgentsView: View {
    @ObservedObject var workspace: WorkspaceStore
    @State private var showDetails = false

    var body: some View {
        Form {
            Section("Coding Agent") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundStyle(.tint)
                        Text("Codex")
                            .font(.headline)
                        Spacer()
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(statusColor)
                    }
                    if isReady {
                        LabeledContent("Executable", value: "Detected automatically")
                        LabeledContent("Project Access", value: "Available")
                    }
                }
            }

            if !isReady {
                Section {
                    ContentUnavailableView(
                        "Codex Not Available",
                        systemImage: "exclamationmark.triangle",
                        description: Text("TouchCode needs Codex on this Mac to perform code changes.")
                    )
                    Button("Set Up Codex") {
                        if let url = URL(string: "https://github.com/openai/codex") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section {
                DisclosureGroup("Show Details", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Status", value: statusText)
                        LabeledContent("Bridge", value: bridgeText)
                        if showDetails {
                            Text("TouchCode manages the connection, project context and permissions. The selected coding agent performs code changes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Coding Agent")
    }

    private var isReady: Bool {
        workspace.selectedCodingAgent.isImplemented && workspace.bridgeStatus != .disconnected
    }

    private var statusText: String {
        if !workspace.selectedCodingAgent.isImplemented { return "Not available" }
        switch workspace.bridgeStatus {
        case .connected: return "Ready"
        case .checking: return "Checking…"
        case .disconnected: return "Not available"
        }
    }

    private var statusColor: Color {
        isReady ? .green : .orange
    }

    private var bridgeText: String {
        switch workspace.bridgeStatus {
        case .checking: "Checking…"
        case .connected(let version): "Connected · \(version)"
        case .disconnected: "Not running"
        }
    }
}

