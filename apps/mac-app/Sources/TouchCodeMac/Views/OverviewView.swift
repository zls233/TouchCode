import SwiftUI

struct OverviewView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bridge your iPad to your coding agent")
                    .font(.largeTitle.weight(.semibold))
                Text("TouchCode transports visual context and user intent. Codex or another selected coding agent performs the code change.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                StatusCard(
                    title: "Mac Bridge",
                    value: bridgeStatusText,
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
                )
                StatusCard(
                    title: "iPad",
                    value: workspace.ipadConnected ? "Connected" : "Waiting",
                    systemImage: "ipad"
                )
                StatusCard(
                    title: "Coding Agent",
                    value: workspace.selectedCodingAgent.title,
                    systemImage: "terminal"
                )
            }

            GroupBox("Current project") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "folder")
                        Text(workspace.projectPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(workspace.demoSession?.status == "running" ? "Demo Running" : "Start MVP Demo") {
                            Task { await workspace.startDemo() }
                        }
                        .disabled(workspace.demoSession?.status == "running")
                    }
                    if let session = workspace.demoSession {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("iPad pairing code")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(session.pairingCode)
                                    .font(.system(.title, design: .rounded, weight: .bold))
                                    .monospacedDigit()
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Bridge address")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(session.bridgeURL)
                                    .textSelection(.enabled)
                            }
                        }
                        LabeledContent("Preview", value: session.previewURL)
                    }
                    if let error = workspace.sessionError {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                .padding(6)
            }

            if let run = workspace.latestRun {
                GroupBox("Latest coding run") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(run.message, systemImage: runIcon(run))
                            Spacer()
                            Text(run.stage.capitalized)
                                .foregroundStyle(.secondary)
                        }
                        if !run.summary.isEmpty {
                            Text(run.summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        if !run.changedFiles.isEmpty {
                            Text("Changed: \(run.changedFiles.joined(separator: ", "))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if run.isReviewable {
                            HStack {
                                Button("Review Diff") { workspace.selection = .project }
                                Spacer()
                                Button("Undo", role: .destructive) {
                                    Task { await workspace.undoLatestRun() }
                                }
                                Button("Keep Changes") {
                                    Task { await workspace.keepLatestRun() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .disabled(workspace.isReviewing)
                        } else if let decisionLabel = run.decisionLabel {
                            Label(
                                decisionLabel,
                                systemImage: run.decisionIcon
                            )
                            .foregroundStyle(run.decision == "approved" ? .green : .orange)
                        }
                        if let error = workspace.reviewError {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                    .padding(6)
                }
            }

            Spacer()
        }
        .padding(28)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await workspace.refreshBridgeStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private func runIcon(_ run: CodingRunSnapshot) -> String {
        if run.status == "failed" { return "exclamationmark.triangle.fill" }
        if run.isActive { return "hourglass" }
        return "checkmark.circle.fill"
    }

    private var bridgeStatusText: String {
        switch workspace.bridgeStatus {
        case .checking: "Checking…"
        case .connected(let version): "Connected · \(version)"
        case .disconnected: "Not running"
        }
    }
}

private struct StatusCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(value).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .frame(maxWidth: .infinity)
        }
    }
}
