import Foundation
import SwiftUI

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published var presentationState: ConnectionPresentationState = .starting
    @Published var deviceName: String?
    @Published var projectName: String?
    @Published var projectPath: String?
    @Published var agentName: String = "Codex"
    @Published var agentReady: Bool = true

    private var workspace: WorkspaceStore?

    func bind(workspace: WorkspaceStore) {
        self.workspace = workspace
        // Observe workspace changes via KVO or manual update
        // For Phase 2, we poll via update() called from View's task
    }

    func update(from workspace: WorkspaceStore) {
        // Derive presentation state from workspace's low-level state
        // Order: permission > pairing > connecting > connected > reconnecting > waiting > ready > starting
        if case .checking = workspace.bridgeStatus {
            presentationState = .starting
            return
        }
        // Permission required is derived from workspace's bridgeStatus or demoSession? For now, use a heuristic:
        // If bridge is disconnected and no session, check if we should show permission
        // Since we don't have direct permission signal, we treat disconnected with no session as waiting
        if workspace.demoSession == nil && workspace.bridgeStatus == .disconnected {
            // Check if we have a stored permission flag? For now, show waiting
            presentationState = .waiting
            return
        }
        if let session = workspace.demoSession {
            if session.status != "running" {
                presentationState = .unavailable(reason: "Session is not running.")
                return
            }
            if workspace.ipadConnected {
                let name = session.pairingCode.isEmpty ? "iPad" : "iPad"
                // Use pairingCode as proxy for device name for now
                presentationState = .connected(deviceName: name)
                deviceName = name
            } else {
                presentationState = .waiting
            }
            projectName = (workspace.projectPath as NSString).lastPathComponent
            projectPath = workspace.projectPath
            agentName = workspace.selectedCodingAgent.title
            agentReady = workspace.selectedCodingAgent.isImplemented
            return
        }
        // No session, bridge connected, waiting for iPad
        if case .connected = workspace.bridgeStatus {
            presentationState = .ready
            projectName = (workspace.projectPath as NSString).lastPathComponent
            projectPath = workspace.projectPath
            agentName = workspace.selectedCodingAgent.title
            return
        }
        presentationState = .starting
    }

    var statusRows: [StatusRowModel] {
        var rows: [StatusRowModel] = []
        // Connection row
        switch presentationState {
        case .connected(let name):
            rows.append(StatusRowModel(icon: "checkmark.circle.fill", title: "iPad", detail: name, severity: .active))
        case .connecting(let name), .pairing(let name):
            rows.append(StatusRowModel(icon: "arrow.trianglehead.2.clockwise.rotate.90", title: "iPad", detail: name, severity: .waiting))
        case .reconnecting:
            rows.append(StatusRowModel(icon: "arrow.trianglehead.2.clockwise.rotate.90", title: "iPad", detail: "Reconnecting…", severity: .waiting))
        case .permissionRequired:
            rows.append(StatusRowModel(icon: "lock.trianglebadge.exclamationmark", title: "Local Network", detail: "Permission required", severity: .warning))
        case .unavailable(let reason):
            rows.append(StatusRowModel(icon: "exclamationmark.triangle", title: "Connection", detail: reason, severity: .error))
        default:
            rows.append(StatusRowModel(icon: "ipad", title: "iPad", detail: "Waiting", severity: .waiting))
        }
        // Project row
        if let name = projectName {
            rows.append(StatusRowModel(icon: "folder", title: "Project", detail: name, severity: .normal))
        }
        // Agent row
        rows.append(StatusRowModel(icon: "terminal", title: "Coding Agent", detail: agentName + (agentReady ? " · Ready" : " · Not available"), severity: agentReady ? .normal : .warning))
        return rows
    }
}

struct StatusRowModel: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let severity: Severity

    enum Severity {
        case normal, active, waiting, warning, error, unavailable
    }
}
