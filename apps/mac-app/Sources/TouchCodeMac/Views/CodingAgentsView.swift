import SwiftUI

struct CodingAgentsView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        Form {
            Section("Selected coding agent") {
                Picker("Provider", selection: $workspace.selectedCodingAgent) {
                    ForEach(CodingAgentOption.allCases) { agent in
                        HStack {
                            Text(agent.title)
                            if !agent.isImplemented { Text("Coming later") }
                        }
                        .tag(agent)
                        .disabled(!agent.isImplemented)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Section("Responsibility boundary") {
                Text("TouchCode Mac connects devices, packages context, applies permissions and presents diffs. The selected coding agent reads and changes code.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Coding Agents")
    }
}

