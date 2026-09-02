import Foundation

enum ConnectionPresentationState: Equatable {
    case starting
    case ready
    case permissionRequired
    case waiting
    case pairing(deviceName: String)
    case connecting(deviceName: String)
    case connected(deviceName: String)
    case reconnecting(deviceName: String?)
    case unavailable(reason: String)

    var title: String {
        switch self {
        case .starting: "Starting TouchCode…"
        case .ready: "Ready for your iPad"
        case .permissionRequired: "Local Network Access Required"
        case .waiting: "Waiting for your iPad…"
        case .pairing(let name): "Pairing with \(name)"
        case .connecting(let name): "Connecting to \(name)…"
        case .connected(let name): "Connected to \(name)"
        case .reconnecting: "Reconnecting…"
        case .unavailable: "Connection lost"
        }
    }

    var message: String {
        switch self {
        case .starting: "TouchCode is starting."
        case .ready: "Open TouchCode on your iPad to connect."
        case .permissionRequired: "TouchCode uses your local network to connect directly to your iPad."
        case .waiting: "Keep TouchCode running and make sure both devices are nearby."
        case .pairing: "Confirm the pairing code on both devices."
        case .connecting: "Establishing a secure connection."
        case .connected: "Connected securely."
        case .reconnecting: "TouchCode will reconnect automatically when the iPad becomes available."
        case .unavailable(let reason): reason
        }
    }

    var primaryActionTitle: String? {
        switch self {
        case .ready: nil
        case .permissionRequired: "Open System Settings"
        case .waiting, .unavailable: "Try Again"
        case .connected: nil
        case .reconnecting: nil
        case .starting, .pairing, .connecting: nil
        }
    }

    var isWaiting: Bool {
        switch self {
        case .waiting, .connecting, .reconnecting, .starting, .pairing: true
        default: false
        }
    }
}
