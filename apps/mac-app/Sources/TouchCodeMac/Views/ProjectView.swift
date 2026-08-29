import SwiftUI

struct ProjectView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        Form {
            Section("Authorized project") {
                LabeledContent("Path", value: workspace.projectPath)
                Button("Choose React/Vite Project…") {
                    // Folder authorization will be connected to NSOpenPanel in the next slice.
                }
            }
            Section("Safety") {
                Label("Changes run in an isolated Git worktree", systemImage: "checkmark.shield")
                Label("The original project changes only after Keep", systemImage: "arrow.triangle.branch")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Project")
    }
}

