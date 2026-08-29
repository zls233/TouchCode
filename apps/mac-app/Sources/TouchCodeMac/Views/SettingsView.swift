import SwiftUI

struct SettingsView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        Form {
            TextField("Bridge endpoint", text: $workspace.bridgeEndpoint)
                .textFieldStyle(.roundedBorder)
        }
        .padding(20)
        .frame(width: 440)
    }
}

