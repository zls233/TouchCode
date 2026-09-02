import SwiftUI

@main
struct TouchCodeMacApp: App {
    @StateObject private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup("TouchCode") {
            ContentView(workspace: workspace)
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandMenu("Navigate") {
                ForEach(SidebarDestination.allCases) { destination in
                    Button(destination.title) {
                        workspace.selection = destination
                    }
                    .keyboardShortcut(KeyEquivalent(destination.keyboardShortcut), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView(workspace: workspace)
        }
    }
}
