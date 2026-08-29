import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    enum BridgeStatus: Equatable {
        case checking
        case connected(version: String)
        case disconnected
    }

    @Published var selection: SidebarDestination? = .overview
    @Published var bridgeStatus: BridgeStatus = .checking
    @Published var selectedCodingAgent: CodingAgentOption = .codex
    @Published var projectPath = "No project selected"
    @Published var ipadConnected = false
    @Published var bridgeEndpoint = "http://127.0.0.1:4317"
    @Published var demoSession: DemoSession?
    @Published var sessionError: String?
    let bridgeProcess = BridgeProcessController()

    func refreshBridgeStatus() async {
        bridgeStatus = .checking
        guard let url = URL(string: bridgeEndpoint) else {
            bridgeStatus = .disconnected
            return
        }
        do {
            let health = try await BridgeClient(endpoint: url).health()
            guard health.role == "bridge" else {
                bridgeStatus = .disconnected
                return
            }
            bridgeStatus = .connected(version: health.version)
        } catch {
            bridgeStatus = .disconnected
        }
    }

    func startDemo() async {
        sessionError = nil
        bridgeProcess.start()
        guard let url = URL(string: bridgeEndpoint) else {
            sessionError = "Invalid bridge endpoint"
            return
        }
        let client = BridgeClient(endpoint: url)
        for attempt in 0..<30 {
            do {
                let health = try await client.health()
                bridgeStatus = .connected(version: health.version)
                let session = try await client.createDemoSession()
                demoSession = session
                projectPath = session.worktreePath
                return
            } catch {
                if attempt == 29 {
                    bridgeStatus = .disconnected
                    sessionError = error.localizedDescription
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}
