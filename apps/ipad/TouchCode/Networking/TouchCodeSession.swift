import Foundation

@MainActor
final class TouchCodeSession: ObservableObject {
    enum State: Equatable {
        case idle
        case discovering
        case connecting(String)
        case connected(String)
        case unavailable
        case permissionRequired
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var discoveredHosts: [DiscoveredHost] = []
    @Published private(set) var bridgeURL: URL?

    private let discovery: HostDiscovery
    private let transport: TouchCodeTransport
    private var discoveryTask: Task<Void, Never>?
    private var connectingHostID: String?
    private var selectedHostID: String?

    init(
        discovery: HostDiscovery? = nil,
        transport: TouchCodeTransport? = nil
    ) {
        self.discovery = discovery ?? BonjourHostDiscovery()
        self.transport = transport ?? PrototypeHTTPTransport()
    }

    func findMac() async {
        guard discoveryTask == nil else { return }
        state = .discovering
        do {
            try await discovery.start()
            discoveryTask = Task { [weak self] in
                guard let self else { return }
                for await hosts in self.discovery.hosts {
                    if Task.isCancelled { return }
                    await self.received(hosts)
                }
            }
        } catch {
            state = .permissionRequired
        }
    }

    func retry() async {
        stop()
        await findMac()
    }

    func stop() {
        discoveryTask?.cancel()
        discoveryTask = nil
        discovery.stop()
        Task { await transport.disconnect() }
        discoveredHosts = []
        connectingHostID = nil
        selectedHostID = nil
        bridgeURL = nil
        state = .idle
    }

    private func received(_ hosts: [DiscoveredHost]) async {
        discoveredHosts = hosts
        if let selectedHostID, !hosts.contains(where: { $0.id == selectedHostID }) {
            self.selectedHostID = nil
            bridgeURL = nil
            state = hosts.isEmpty ? .unavailable : .discovering
            await transport.disconnect()
        }
        guard selectedHostID == nil,
              connectingHostID == nil,
              let host = hosts.first else {
            if hosts.isEmpty, selectedHostID == nil { state = .unavailable }
            return
        }
        await connect(to: host)
    }

    private func connect(to host: DiscoveredHost) async {
        connectingHostID = host.id
        state = .connecting(host.name)
        defer { connectingHostID = nil }
        do {
            let hello = try await transport.connect(to: host.endpoint)
            guard let url = TouchCodeAPIClient.validatedBridgeURL(from: hello.bridgeURL) else {
                throw TouchCodeTransportError.invalidResponse
            }
            bridgeURL = url
            selectedHostID = host.id
            state = .connected(host.name)
        } catch {
            if discoveredHosts.contains(where: { $0.id == host.id }) {
                state = .unavailable
            }
        }
    }
}
