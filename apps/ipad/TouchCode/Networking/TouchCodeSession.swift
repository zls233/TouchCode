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
        case reconnecting
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var discoveredHosts: [DiscoveredHost] = []
    @Published private(set) var bridgeURL: URL?

    private let discovery: HostDiscovery
    private let transport: TouchCodeTransport
    private let heartbeatMonitor: HeartbeatMonitoring
    private let reconnectStrategy: ReconnectStrategy
    private let lastTrustedStore: LastTrustedStore
    private var discoveryTask: Task<Void, Never>?
    private var transportStateTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var disconnectTail: Task<Void, Never>?
    private var disconnectSequence = 0
    private var generation = 0
    private var connectingHostID: String?
    private var selectedHostID: String?
    @Published private(set) var transportStateDescription: String = "idle"
    @Published private(set) var heartbeatDescription: String = "idle"
    var generationForDiagnostics: Int { generation }
    var selectedHostIDForDiagnostics: String? { selectedHostID }

    init(
        discovery: HostDiscovery? = nil,
        transport: TouchCodeTransport? = nil,
        heartbeatMonitor: HeartbeatMonitoring? = nil,
        reconnectStrategy: ReconnectStrategy? = nil,
        lastTrustedStore: LastTrustedStore? = nil
    ) {
        self.discovery = discovery ?? BonjourHostDiscovery()
        self.transport = transport ?? PrototypeHTTPTransport()
        self.heartbeatMonitor = heartbeatMonitor ?? HeartbeatMonitor()
        self.reconnectStrategy = reconnectStrategy ?? ReconnectStrategy()
        self.lastTrustedStore = lastTrustedStore ?? LastTrustedStore()
    }

    func findMac() async {
        guard discoveryTask == nil else { return }
        let requestGeneration = generation
        await waitForDisconnectTail()
        guard requestGeneration == generation else { return }
        generation += 1
        let sessionGeneration = generation
        state = .discovering
        do {
            try await discovery.start()
            guard sessionGeneration == generation else { return }
            observeTransport(generation: sessionGeneration)
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
        transportStateTask?.cancel()
        transportStateTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        discovery.stop()
        heartbeatMonitor.stop()
        reconnectStrategy.reset()
        enqueueDisconnect()
        discoveredHosts = []
        connectingHostID = nil
        selectedHostID = nil
        bridgeURL = nil
        state = .idle
        transportStateDescription = "idle"
        heartbeatDescription = "idle"
    }

    func handleForeground() {
        guard case .unavailable = state else {
            if heartbeatMonitor.heartbeatTimedOut() {
                scheduleAutoReconnect()
            }
            return
        }
        scheduleAutoReconnect()
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
        let ordered = orderedHosts(from: hosts)
        for host in ordered {
            guard generation == self.generation else { return }
            guard discoveredHosts.contains(where: { $0.id == host.id }),
                  selectedHostID == nil else { break }
            connectingHostID = host.id
            state = .connecting(host.name)
            transportStateDescription = "connecting"
            do {
                let hello = try await transport.connect(to: host.endpoint)
                guard generation == self.generation else { return }
                guard let url = TouchCodeAPIClient.validatedBridgeURL(from: hello.bridgeURL) else {
                    throw TouchCodeTransportError.invalidResponse
                }
                try validateHelloBytes(Data(hello.bridgeURL.utf8))
                bridgeURL = url
                selectedHostID = host.id
                lastTrustedStore.save(hostID: host.id)
                state = .connected(host.name)
                transportStateDescription = "connected"
                heartbeatDescription = "ready"
                connectingHostID = nil
                reconnectStrategy.reset()
                startHeartbeat(generation: generation)
                return
            } catch {
                connectingHostID = nil
                transportStateDescription = "failed"
            }
        }
        connectingHostID = nil
        if selectedHostID == nil {
            state = .unavailable
            transportStateDescription = "unavailable"
            scheduleAutoReconnect()
        }
    }

    private func orderedHosts(from hosts: [DiscoveredHost]) -> [DiscoveredHost] {
        // Priority: last trusted > others sorted by name
        guard let last = lastTrustedStore.load(),
              let trusted = hosts.first(where: { $0.id == last }) else {
            return hosts
        }
        var rest = hosts.filter { $0.id != last }
        // Keep original order for rest (already sorted by name in discovery)
        return [trusted] + rest
    }

    private func observeTransport(generation: Int) {
        transportStateTask?.cancel()
        transportStateTask = Task { [weak self] in
            guard let self else { return }
            for await tState in self.transport.states {
                guard generation == self.generation else { return }
                await MainActor.run { self.transportStateDescription = "\(tState)" }
                if tState == .failed {
                    await self.scheduleAutoReconnect()
                }
            }
        }
    }

    private func startHeartbeat(generation: Int) {
        heartbeatTask?.cancel()
        heartbeatMonitor.start()
        heartbeatDescription = "running"
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.heartbeatMonitor.ticks {
                guard generation == self.generation else { return }
                if self.heartbeatMonitor.heartbeatTimedOut() {
                    await MainActor.run { self.heartbeatDescription = "timeout" }
                    await self.scheduleAutoReconnect()
                    return
                }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        heartbeatMonitor.stop()
        heartbeatDescription = "stopped"
    }

    private func scheduleAutoReconnect() {
        guard reconnectTask == nil else { return }
        stopHeartbeat()
        enqueueDisconnect()
        let baseGeneration = generation
        state = .reconnecting
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            await self.reconnectStrategy.waitForNextAttempt()
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard baseGeneration == self.generation else { return }
                self.reconnectTask = nil
                self.discoveryTask?.cancel()
                self.discoveryTask = nil
                self.discovery.stop()
                self.generation += 1
                let nextGen = self.generation
                self.state = .discovering
                Task { await self.restartDiscovery(generation: nextGen) }
            }
        }
    }

    private func restartDiscovery(generation: Int) async {
        do {
            try await discovery.start()
            guard generation == self.generation else { return }
            observeTransport(generation: generation)
            discoveryTask = Task { [weak self] in
                guard let self else { return }
                for await event in self.discovery.events {
                    if Task.isCancelled { return }
                    await self.received(event, generation: generation)
                }
            }
        } catch {
            if generation == self.generation { state = .permissionRequired }
        }
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
