import SwiftUI

struct SettingsView: View {
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        TabView {
            TrustedDevicesSettingsView(workspace: workspace)
                .tabItem { Label("Connection", systemImage: "ipad.and.iphone") }

            Form {
                Section("Bridge") {
                    TextField("Endpoint", text: $workspace.bridgeEndpoint)
                        .textFieldStyle(.roundedBorder)
                    Text("Only change this when troubleshooting a custom local Bridge setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .frame(width: 520, height: 360)
        .scenePadding()
    }
}

private struct TrustedDevicesSettingsView: View {
    @ObservedObject var workspace: WorkspaceStore
    @State private var peerToForget: TrustedPeer?
    @State private var isForgetting = false

    var body: some View {
        Form {
            Section {
                if workspace.isLoadingTrustedPeers && workspace.trustedPeers.isEmpty {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading trusted devices…")
                            .foregroundStyle(.secondary)
                    }
                } else if workspace.trustedPeers.isEmpty && workspace.trustedPeersError == nil {
                    ContentUnavailableView(
                        "No Trusted Devices",
                        systemImage: "ipad.slash",
                        description: Text("Paired iPads will appear here.")
                    )
                } else {
                    ForEach(workspace.trustedPeers) { peer in
                        HStack(spacing: 12) {
                            Image(systemName: "ipad")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.displayName)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .help(peer.displayName)
                                Text("Last connected \(lastSeenText(for: peer))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Forget…", role: .destructive) {
                                peerToForget = peer
                            }
                            .disabled(isForgetting || workspace.isLoadingTrustedPeers)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let error = workspace.trustedPeersError {
                    HStack {
                        Text(error)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Try Again") {
                            Task { await workspace.loadTrustedPeers() }
                        }
                    }
                }
            } header: {
                Text("Trusted Devices")
            } footer: {
                Text("Forgotten devices must be paired again before they can connect.")
            }
        }
        .formStyle(.grouped)
        .task(id: workspace.bridgeEndpoint) {
            await workspace.loadTrustedPeers()
        }
        .alert(
            "Forget \(peerToForget?.displayName ?? "this device")?",
            isPresented: Binding(
                get: { peerToForget != nil },
                set: { if !$0 { peerToForget = nil } }
            ),
            presenting: peerToForget
        ) { peer in
            Button("Cancel", role: .cancel) {}
            Button("Forget Device", role: .destructive) {
                isForgetting = true
                Task {
                    _ = await workspace.forgetTrustedPeer(peer)
                    isForgetting = false
                    peerToForget = nil
                }
            }
        } message: { peer in
            Text("\(peer.displayName) will need to pair with this Mac again.")
        }
    }

    private func lastSeenText(for peer: TrustedPeer) -> String {
        Date(timeIntervalSince1970: TimeInterval(peer.lastSeenAt) / 1_000)
            .formatted(.relative(presentation: .named))
    }
}
