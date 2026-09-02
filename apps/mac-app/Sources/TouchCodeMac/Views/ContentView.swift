import SwiftUI

struct ContentView: View {
    @ObservedObject var workspace: WorkspaceStore
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $workspace.selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .listStyle(.sidebar)
            .navigationTitle("TouchCode")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch workspace.selection ?? .overview {
            case .overview:
                OverviewView(workspace: workspace)
            case .project:
                ProjectView(workspace: workspace)
            case .codingAgent:
                CodingAgentsView(workspace: workspace)
            case .diagnostics:
                DiagnosticsView(workspace: workspace)
            }
        }
        .task {
            await workspace.refreshBridgeStatus()
        }
        .task(id: workspace.demoSession?.sessionId) {
            await workspace.monitorDemoSession()
        }
        .onAppear {
            if !hasSeenOnboarding && workspace.projectPath == "No project selected" {
                showOnboarding = true
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(workspace: workspace, isPresented: $showOnboarding)
                .onDisappear { hasSeenOnboarding = true }
        }
        .toolbar {
            ToolbarItem {
                Button("Onboarding", systemImage: "questionmark.circle") {
                    showOnboarding = true
                }
                .help("Show onboarding")
            }
        }
    }
}
