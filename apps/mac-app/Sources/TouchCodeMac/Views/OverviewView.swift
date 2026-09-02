import SwiftUI
import AppKit

struct OverviewView: View {
    @ObservedObject var workspace: WorkspaceStore
    @StateObject private var viewModel = OverviewViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.presentationState.title)
                        .font(.title2.weight(.semibold))
                    Text(viewModel.presentationState.message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.statusRows) { row in
                    StatusRow(model: row)
                }

                if let actionTitle = viewModel.presentationState.primaryActionTitle {
                    Button(actionTitle) {
                        Task { await handlePrimaryAction() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                GroupBox("Current project") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "folder")
                            Text(workspace.projectPath)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button(workspace.demoSession?.status == "running" ? "Session Running" : "Start Session") {
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
            .task { viewModel.update(from: workspace) }
            .onChange(of: workspace.bridgeStatus) { _, _ in viewModel.update(from: workspace) }
            .onChange(of: workspace.demoSession?.sessionId) { _, _ in viewModel.update(from: workspace) }
            .onChange(of: workspace.ipadConnected) { _, _ in viewModel.update(from: workspace) }
            .onChange(of: workspace.projectPath) { _, _ in viewModel.update(from: workspace) }
            .onChange(of: workspace.selectedCodingAgent) { _, _ in viewModel.update(from: workspace) }
        }
    }

    private func handlePrimaryAction() async {
        switch viewModel.presentationState {
        case .permissionRequired:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                NSWorkspace.shared.open(url)
            }
        case .waiting, .unavailable:
            await workspace.refreshBridgeStatus()
        default:
            break
        }
    }

    private func runIcon(_ run: CodingRunSnapshot) -> String {
        if run.status == "failed" { return "exclamationmark.triangle.fill" }
        if run.isActive { return "hourglass" }
        return "checkmark.circle.fill"
    }
}
