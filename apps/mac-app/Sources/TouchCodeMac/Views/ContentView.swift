import SwiftUI

struct ContentView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $workspace.selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .listStyle(.sidebar)
            .navigationTitle("TouchCode")
        } detail: {
            switch workspace.selection ?? .overview {
            case .overview:
                OverviewView(workspace: workspace)
            case .project:
                ProjectView(workspace: workspace)
            case .codingAgents:
                CodingAgentsView(workspace: workspace)
            }
        }
        .task {
            await workspace.refreshBridgeStatus()
        }
    }
}

