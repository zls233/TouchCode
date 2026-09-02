import SwiftUI

@main
struct TouchCodeMacApp: App {
    @StateObject private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup("TouchCode") {
            ContentView(workspace: workspace)
                .frame(minWidth: 900, minHeight: 560)
        }

        Settings {
            SettingsView(workspace: workspace)
        }
    }
}

