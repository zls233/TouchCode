import SwiftUI

@main
struct TouchCodeMacApp: App {
    @StateObject private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup("TouchCode") {
            ContentView(workspace: workspace)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Bridge Status") {
                    Task { await workspace.refreshBridgeStatus() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(workspace: workspace)
        }
    }
}

