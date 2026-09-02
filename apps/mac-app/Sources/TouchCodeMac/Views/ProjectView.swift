import SwiftUI
import AppKit

struct ProjectView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        Form {
            if workspace.projectPath == "No project selected" || workspace.projectPath.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Project Selected",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Choose the project you want to work on from your iPad.")
                    )
                    Button("Choose Project…") {
                        Task { await workspace.chooseProject() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Section {
                    Text("TouchCode works with a local project on this Mac.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Project") {
                    LabeledContent("Name", value: (workspace.projectPath as NSString).lastPathComponent)
                    LabeledContent("Location", value: workspace.projectPath)
                        .textSelection(.enabled)
                    LabeledContent("Git", value: "main · Clean")
                    LabeledContent("Workspace", value: "Ready")
                }
                Section {
                    Button("Reveal in Finder") {
                        if let url = URL(string: "file://\(workspace.projectPath)") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else {
                            NSWorkspace.shared.selectFile(workspace.projectPath, inFileViewerRootedAtPath: "")
                        }
                    }
                    Button("Change Project…") {
                        Task { await workspace.chooseProject() }
                    }
                }
                Section("Safety") {
                    Label("Isolated changes — Agent changes run separately from your primary working state.", systemImage: "checkmark.shield")
                    Label("Review before keeping — You can review generated changes before applying them.", systemImage: "eye")
                    Label("Checkpoints — TouchCode can preserve recoverable states during a session.", systemImage: "arrow.triangle.branch")
                }
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
