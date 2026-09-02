import Foundation
import AppKit

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
    @Published var latestRun: CodingRunSnapshot?
    @Published var sessionError: String?
    @Published var reviewError: String?
    @Published var isReviewing = false
    @Published private(set) var trustedPeers: [TrustedPeer] = []
    @Published private(set) var trustedPeersError: String?
    @Published private(set) var isLoadingTrustedPeers = false
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
        guard let url = URL(string: bridgeEndpoint) else {
            sessionError = "Invalid bridge endpoint"
            return
        }
        let client = BridgeClient(endpoint: url)
        if (try? await client.health()) == nil {
            bridgeProcess.start()
        }
        for attempt in 0..<30 {
            do {
                let health = try await client.health()
                bridgeStatus = .connected(version: health.version)
                let session = try await client.createDemoSession()
                demoSession = session
                latestRun = nil
                projectPath = session.worktreePath ?? "No project selected"
                ipadConnected = session.ipadConnected
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

    func monitorDemoSession() async {
        guard let initialSession = demoSession,
              let endpoint = URL(string: bridgeEndpoint) else { return }
        let client = BridgeClient(endpoint: endpoint)
        let sessionId = initialSession.sessionId

        while !Task.isCancelled, demoSession?.sessionId == sessionId {
            do {
                let session = try await client.demoSession(sessionId)
                demoSession = session
                ipadConnected = session.ipadConnected
                if let runId = session.latestRunId {
                    latestRun = try await client.codingRun(sessionId: sessionId, runId: runId)
                }
                sessionError = nil
            } catch {
                sessionError = error.localizedDescription
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func keepLatestRun() async {
        await decideLatestRun(action: "keep")
    }

    func undoLatestRun() async {
        await decideLatestRun(action: "undo")
    }

    private func decideLatestRun(action: String) async {
        guard let session = demoSession,
              let run = latestRun,
              let endpoint = URL(string: bridgeEndpoint) else { return }
        isReviewing = true
        reviewError = nil
        defer { isReviewing = false }
        do {
            latestRun = try await BridgeClient(endpoint: endpoint).decide(
                sessionId: session.sessionId,
                runId: run.runId,
                action: action
            )
        } catch {
            reviewError = error.localizedDescription
        }
    }

    func chooseProject() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Project"
        panel.message = "Choose the project you want to work on from your iPad."
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
        }
    }

    func loadTrustedPeers() async {
        guard let url = URL(string: bridgeEndpoint) else {
            trustedPeers = []
            trustedPeersError = "The Bridge address is invalid."
            return
        }
        isLoadingTrustedPeers = true
        trustedPeersError = nil
        defer {
            if !Task.isCancelled {
                isLoadingTrustedPeers = false
            }
        }
        do {
            let peers = try await BridgeClient(endpoint: url).trustedPeers()
            guard !Task.isCancelled else { return }
            trustedPeers = peers
        } catch {
            guard !Task.isCancelled else { return }
            trustedPeers = []
            trustedPeersError = "Trusted devices are unavailable. Make sure TouchCode is running, then try again."
        }
    }

    func forgetTrustedPeer(_ peer: TrustedPeer) async -> Bool {
        guard let url = URL(string: bridgeEndpoint) else {
            trustedPeersError = "The Bridge address is invalid."
            return false
        }
        trustedPeersError = nil
        do {
            try await BridgeClient(endpoint: url).forgetTrustedPeer(deviceId: peer.peerDeviceId)
            trustedPeers.removeAll { $0.peerDeviceId == peer.peerDeviceId }
            return true
        } catch {
            trustedPeersError = "TouchCode could not forget this device. Try again."
            return false
        }
    }
}
