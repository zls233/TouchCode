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
    private var disconnectTail: Task<Void, Never>?
    private var disconnectSequence = 0
    private var generation = 0
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
        await waitForDisconnectTail()
        generation += 1
        let sessionGeneration = generation
        state = .discovering
        do {
            try await discovery.start()
            guard sessionGeneration == generation else { return }
            discoveryTask = Task { [weak self] in
                guard let self else { return }
                for await event in self.discovery.events {
                    if Task.isCancelled { return }
                    await self.received(event, generation: sessionGeneration)
                }
            }
        } catch {
            if sessionGeneration == generation { state = .permissionRequired }
        }
    }

    func retry() async {
        stop()
        await findMac()
    }

    func stop() {
        generation += 1
        discoveryTask?.cancel()
        discoveryTask = nil
        discovery.stop()
        enqueueDisconnect()
        discoveredHosts = []
        connectingHostID = nil
        selectedHostID = nil
        bridgeURL = nil
        state = .idle
    }

    private func received(_ event: HostDiscoveryEvent, generation: Int) async {
        guard generation == self.generation else { return }
        guard case let .hosts(hosts) = event else {
            self.generation += 1
            selectedHostID = nil
            connectingHostID = nil
            bridgeURL = nil
            enqueueDisconnect()
            state = .permissionRequired
            return
        }
        discoveredHosts = hosts
        if let selectedHostID, !hosts.contains(where: { $0.id == selectedHostID }) {
            self.selectedHostID = nil
            bridgeURL = nil
            state = hosts.isEmpty ? .unavailable : .discovering
            enqueueDisconnect()
        }
        guard selectedHostID == nil, connectingHostID == nil else {
            if hosts.isEmpty, selectedHostID == nil { state = .unavailable }
            return
        }
        await connect(to: hosts, generation: generation)
    }

    private func enqueueDisconnect() {
        let previous = disconnectTail
        disconnectSequence += 1
        disconnectTail = Task { [transport] in
            if let previous { await previous.value }
            await transport.disconnect()
        }
    }

    private func connect(to hosts: [DiscoveredHost], generation: Int) async {
        await waitForDisconnectTail()
        for host in hosts {
            guard generation == self.generation else { return }
            guard discoveredHosts.contains(where: { $0.id == host.id }),
                  selectedHostID == nil else { break }
            connectingHostID = host.id
            state = .connecting(host.name)
            do {
                let hello = try await transport.connect(to: host.endpoint)
                guard generation == self.generation else { return }
                guard let url = TouchCodeAPIClient.validatedBridgeURL(from: hello.bridgeURL) else {
                    throw TouchCodeTransportError.invalidResponse
                }
                bridgeURL = url
                selectedHostID = host.id
                state = .connected(host.name)
                connectingHostID = nil
                return
            } catch {
                connectingHostID = nil
            }
        }
        connectingHostID = nil
        if selectedHostID == nil { state = .unavailable }
    }

    private func waitForDisconnectTail() async {
        while let tail = disconnectTail {
            let sequence = disconnectSequence
            await tail.value
            guard sequence == disconnectSequence else { continue }
            disconnectTail = nil
            return
        }
    }
}
