import SwiftUI

struct ProjectView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        Form {
            Section("Isolated MVP workspace") {
                LabeledContent("Path", value: workspace.projectPath)
                Text("This MVP uses a disposable copy of the bundled React demo. Real project selection is intentionally not advertised yet.")
                    .foregroundStyle(.secondary)
            }
            Section("Safety") {
                Label("Changes run in an isolated Git worktree", systemImage: "checkmark.shield")
                Label("Keep creates a checkpoint inside the demo workspace", systemImage: "arrow.triangle.branch")
            }
            if let run = workspace.latestRun {
                Section("Latest change") {
                    LabeledContent("Status", value: run.message)
                    LabeledContent("Files", value: run.changedFiles.joined(separator: ", "))
                    if run.diff.isEmpty {
                        ContentUnavailableView(
                            "No source diff",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(run.summary.isEmpty ? "The coding run has not produced a source change yet." : run.summary)
                        )
                        .frame(minHeight: 180)
                    } else {
                        ScrollView([.horizontal, .vertical]) {
                            Text(run.diff)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(minHeight: 260, maxHeight: 420)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if run.isReviewable {
                        HStack {
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
                    }
                    if let error = workspace.reviewError {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Project")
    }
}
