import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Bridge", value: bridgeStatusText)
                LabeledContent("iPad", value: workspace.ipadConnected ? "Connected" : "Not connected")
                LabeledContent("Endpoint", value: workspace.bridgeEndpoint)
            }
            Section("Discovery") {
                LabeledContent("Status", value: "Bonjour _touchcode._tcp")
                Text("Local Network permission and discovered devices are managed via the Overview connection flow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Bridge") {
                LabeledContent("Status", value: bridgeStatusText)
                if let session = workspace.demoSession {
                    LabeledContent("Session", value: session.sessionId.prefix(8).description)
                    LabeledContent("Preview", value: session.previewURL)
                } else {
                    ContentUnavailableView("No active session", systemImage: "dot.radiowaves.left.and.right", description: Text("Start a session from Overview."))
                }
            }
            Section("Project") {
                LabeledContent("Path", value: workspace.projectPath)
                LabeledContent("Git", value: "Available on device")
            }
            Section("Coding Agent") {
                LabeledContent("Selected", value: workspace.selectedCodingAgent.title)
                LabeledContent("Status", value: workspace.selectedCodingAgent.isImplemented ? "Ready" : "Not available")
            }
            Section("Recent Errors") {
                if let error = workspace.sessionError ?? workspace.reviewError {
                    Text(error)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.red)
                } else {
                    Text("No recent errors.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItemGroup {
                Button("Copy Diagnostics") {
                    let text = diagnosticsText
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Reconnect") {
                    Task { await workspace.refreshBridgeStatus() }
                }
                .help("Refresh bridge connection")
                Button("Restart Bridge") {
                    workspace.bridgeProcess.start()
                    Task { await workspace.refreshBridgeStatus() }
                }
                .help("Restart local bridge process")
            }
        }
    }

    private var bridgeStatusText: String {
        switch workspace.bridgeStatus {
        case .checking: "Checking…"
        case .connected(let version): "Connected · \(version)"
        case .disconnected: "Not running"
        }
    }

    private var diagnosticsText: String {
        """
        Bridge: \(bridgeStatusText)
        iPad: \(workspace.ipadConnected ? "Connected" : "Not connected")
        Endpoint: \(workspace.bridgeEndpoint)
        Project: \(workspace.projectPath)
        Agent: \(workspace.selectedCodingAgent.title)
        Session: \(workspace.demoSession?.sessionId ?? "-")
        Error: \(workspace.sessionError ?? workspace.reviewError ?? "-")
        """
    }
}
