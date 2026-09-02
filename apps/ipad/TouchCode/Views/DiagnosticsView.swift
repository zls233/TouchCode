import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var session: TouchCodeSession
    var gatewayURL: URL?
    var previewURL: String?

    var body: some View {
        List {
            Section("Discovery") {
                LabeledContent("State", value: discoveryState)
                LabeledContent("Hosts", value: "\(session.discoveredHosts.count)")
                ForEach(session.discoveredHosts, id: \.id) { host in
                    LabeledContent(host.name, value: host.id)
                }
            }
            Section("Host") {
                LabeledContent("Selected", value: session.selectedHostIDForDiagnostics ?? "-")
                LabeledContent("Bridge", value: session.bridgeURL?.absoluteString ?? "-")
            }
            Section("Trust") {
                LabeledContent("Last Trusted", value: UserDefaults.standard.string(forKey: "com.touchcode.lastTrustedHostID") ?? "-")
            }
            Section("Transport") {
                LabeledContent("State", value: session.transportStateDescription)
                LabeledContent("Heartbeat", value: session.heartbeatDescription)
            }
            Section("Gateway") {
                LabeledContent("Local", value: gatewayURL?.absoluteString ?? "-")
                LabeledContent("Preview", value: previewURL ?? "-")
            }
            Section("Session") {
                LabeledContent("State", value: "\(session.state)")
                LabeledContent("Generation", value: "\(session.generationForDiagnostics)")
            }
        }
        .navigationTitle("Diagnostics")
    }

    private var discoveryState: String {
        switch session.state {
        case .idle: return "Idle"
        case .discovering: return "Discovering"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .unavailable: return "Unavailable"
        case .permissionRequired: return "Permission Required"
        case .reconnecting: return "Reconnecting"
        }
    }
}
