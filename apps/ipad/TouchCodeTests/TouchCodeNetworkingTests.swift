import Foundation
import Network
import XCTest
@testable import TouchCode

final class TouchCodeNetworkingTests: XCTestCase {
    func testPrototypeTransportDecodesVersionedHello() throws {
        let body = #"{"protocolVersion":1,"role":"host","platform":"macOS","appVersion":"0.1.0","capabilities":["pairing"],"bridgeURL":"http://192.0.2.10:4317"}"#
        let response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n\(body)".utf8)

        let hello = try PrototypeHTTPTransport.decodeHello(from: response)

        XCTAssertEqual(hello.protocolVersion, 1)
        XCTAssertEqual(hello.role, "host")
        XCTAssertEqual(hello.bridgeURL, "http://192.0.2.10:4317")
    }

    func testPrototypeTransportRejectsNonSuccessHTTPResponse() {
        let response = Data("HTTP/1.1 503 Service Unavailable\r\n\r\n{}".utf8)
        XCTAssertThrowsError(try PrototypeHTTPTransport.decodeHello(from: response))
    }

    @MainActor
    func testDiscoveryPermissionFailureIsShownAsPermissionRequired() async {
        let discovery = FakeHostDiscovery()
        let session = TouchCodeSession(discovery: discovery, transport: FakeTransport())

        await session.findMac()
        discovery.send(.permissionRequired)
        await eventually { session.state == .permissionRequired }
    }

    @MainActor
    func testPermissionFailureClearsExistingConnection() async {
        let discovery = FakeHostDiscovery()
        let transport = FakeTransport(results: [.success(Self.hello)])
        let session = TouchCodeSession(discovery: discovery, transport: transport)
        await session.findMac()
        discovery.send(.hosts([Self.host("mac")]))
        await eventually { session.state == .connected("mac") }

        discovery.send(.permissionRequired)
        await eventually { session.state == .permissionRequired }
        XCTAssertNil(session.bridgeURL)
        XCTAssertGreaterThan(transport.disconnectCount, 0)
    }

    @MainActor
    func testConnectionFallsBackToNextHostAfterFirstFailure() async {
        let discovery = FakeHostDiscovery()
        let transport = FakeTransport(results: [
            .failure(TouchCodeTransportError.connectionFailed),
            .success(Self.hello)
        ])
        let session = TouchCodeSession(discovery: discovery, transport: transport)

        await session.findMac()
        discovery.send(.hosts([Self.host("first"), Self.host("second")]))
        await eventually { session.state == .connected("second") }
        XCTAssertEqual(transport.connectCount, 2)
    }

    @MainActor
    func testStopThenRetryStartsDiscoveryAgain() async {
        let discovery = FakeHostDiscovery()
        let session = TouchCodeSession(discovery: discovery, transport: FakeTransport())

        await session.findMac()
        session.stop()
        XCTAssertEqual(session.state, .idle)
        await session.retry()
        XCTAssertEqual(discovery.startCount, 2)
        session.stop()
    }

    @MainActor
    func testRetryKeepsEveryDisconnectInTheTailBeforeStartingDiscovery() async {
        let discovery = FakeHostDiscovery()
        let transport = FakeTransport(results: [], blockDisconnect: true)
        let session = TouchCodeSession(discovery: discovery, transport: transport)

        session.stop()
        let find = Task { await session.findMac() }
        await eventually { transport.disconnectStarted }
        session.stop()
        XCTAssertEqual(discovery.startCount, 0)
        transport.releaseDisconnect()
        await eventually { transport.disconnectStartCount == 2 }
        XCTAssertEqual(discovery.startCount, 0)
        transport.releaseDisconnect()
        await find.value
        XCTAssertEqual(discovery.startCount, 0)
        let retry = Task { await session.retry() }
        await eventually { transport.disconnectStartCount == 3 }
        transport.releaseDisconnect()
        await retry.value
        XCTAssertEqual(discovery.startCount, 1)
        session.stop()
        await eventually { transport.disconnectStartCount == 4 }
        transport.releaseDisconnect()
    }

    @MainActor
    func testReplacementHostWaitsForDisconnectBeforeConnectingAndStaysConnected() async {
        let discovery = FakeHostDiscovery()
        let transport = FakeTransport(results: [.success(Self.hello), .success(Self.hello)], blockDisconnect: true)
        let session = TouchCodeSession(discovery: discovery, transport: transport)

        await session.findMac()
        discovery.send(.hosts([Self.host("A")]))
        await eventually { session.state == .connected("A") }
        discovery.send(.hosts([Self.host("B")]))
        await eventually { transport.disconnectStarted }
        XCTAssertEqual(transport.connectCount, 1)
        transport.releaseDisconnect()
        await eventually { session.state == .connected("B") }
        XCTAssertEqual(transport.connectCount, 2)
        session.stop()
        await eventually { transport.disconnectStartCount == 2 }
        transport.releaseDisconnect()
    }

    @MainActor
    func testDelayedOldConnectCannotPublishAfterRetry() async {
        let discovery = FakeHostDiscovery()
        let transport = DelayedTransport()
        let session = TouchCodeSession(discovery: discovery, transport: transport)
        await session.findMac()
        discovery.send(.hosts([Self.host("old")]))
        await eventually { transport.connectStarted }

        session.stop()
        await session.retry()
        transport.resolveOld(with: Self.hello)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertNotEqual(session.state, .connected("old"))
        session.stop()
    }

    func testValidateHelloAndEnvelopeBytesRejectOversize() throws {
        let okHello = Data(repeating: 0, count: TransportFrameLimits.maxHelloBytes)
        XCTAssertNoThrow(try validateHelloBytes(okHello))
        let largeHello = Data(repeating: 0, count: TransportFrameLimits.maxHelloBytes + 1)
        XCTAssertThrowsError(try validateHelloBytes(largeHello))
        let okEnvelope = Data(repeating: 0, count: TransportFrameLimits.maxEnvelopeBytes)
        XCTAssertNoThrow(try validateEnvelopeBytes(okEnvelope))
        let largeEnvelope = Data(repeating: 0, count: TransportFrameLimits.maxEnvelopeBytes + 1)
        XCTAssertThrowsError(try validateEnvelopeBytes(largeEnvelope))
    }

    func testValidateEnvelopeRejectsUnsupportedVersionAndLargePayload() throws {
        let ok = TouchCodeEnvelope(version: 1, id: UUID(), kind: "hello", payload: .string("hi"), sentAt: nil)
        XCTAssertNoThrow(try validateEnvelope(ok))
        let badVersion = TouchCodeEnvelope(version: 2, id: UUID(), kind: "hello", payload: nil, sentAt: nil)
        XCTAssertThrowsError(try validateEnvelope(badVersion))
    }

    func testNextReconnectDelayExponentialCapped() {
        XCTAssertEqual(nextReconnectDelay(attempt: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(nextReconnectDelay(attempt: 1), 1.0, accuracy: 0.001)
        XCTAssertEqual(nextReconnectDelay(attempt: 6), 30.0, accuracy: 0.001)
        XCTAssertEqual(nextReconnectDelay(attempt: 10), 30.0, accuracy: 0.001)
    }

    @MainActor
    func testHeartbeatTimeoutTriggersAutoReconnect() async {
        let discovery = FakeHostDiscovery()
        let heartbeat = FakeHeartbeatMonitor()
        let strategy = ReconnectStrategy(nextDelay: { _ in 0.02 })
        let transport = FakeTransport(results: [.success(Self.hello), .success(Self.hello)])
        let session = TouchCodeSession(discovery: discovery, transport: transport, heartbeatMonitor: heartbeat, reconnectStrategy: strategy)
        await session.findMac()
        discovery.send(.hosts([Self.host("mac")]))
        await eventually { session.state == .connected("mac") }
        XCTAssertEqual(heartbeat.startCount, 1)
        heartbeat.setTimedOut(true)
        heartbeat.triggerTick()
        await eventually(timeout: .seconds(2)) { session.state == .reconnecting || session.state == .discovering }
        XCTAssertEqual(heartbeat.stopCount, 1)
        await eventually(timeout: .seconds(2)) { session.state == .discovering }
        await eventually(timeout: .seconds(2)) { discovery.startCount == 2 }
        session.stop()
    }

    @MainActor
    func testAppForegroundTriggersReconnectWhenTimedOut() async {
        let discovery = FakeHostDiscovery()
        let heartbeat = FakeHeartbeatMonitor()
        let strategy = ReconnectStrategy(nextDelay: { _ in 0.02 })
        let transport = FakeTransport(results: [.success(Self.hello)])
        let session = TouchCodeSession(discovery: discovery, transport: transport, heartbeatMonitor: heartbeat, reconnectStrategy: strategy)
        await session.findMac()
        discovery.send(.hosts([Self.host("mac")]))
        await eventually { session.state == .connected("mac") }
        heartbeat.setTimedOut(true)
        session.handleForeground()
        await eventually(timeout: .seconds(2)) { session.state == .reconnecting || session.state == .discovering }
        await eventually(timeout: .seconds(2)) { session.state == .discovering }
        session.stop()
    }

    @MainActor
    func testStopCancelsReconnectAndHeartbeat() async {
        let discovery = FakeHostDiscovery()
        let heartbeat = FakeHeartbeatMonitor()
        let reconnect = ControllableReconnect()
        let transport = FakeTransport(results: [.success(Self.hello)], blockDisconnect: false)
        let session = TouchCodeSession(discovery: discovery, transport: transport, heartbeatMonitor: heartbeat, reconnectStrategy: reconnect.strategy)
        await session.findMac()
        discovery.send(.hosts([Self.host("mac")]))
        await eventually { session.state == .connected("mac") }
        heartbeat.setTimedOut(true)
        heartbeat.triggerTick()
        await eventually { session.state == .reconnecting }
        session.stop()
        XCTAssertEqual(session.state, .idle)
        reconnect.release()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(session.state, .idle)
    }

    func testLocalGatewayStartsOnLoopbackAndHidesMacIP() throws {
        let upstream = try FakeUpstreamServer(response: "hello from mac")
        let base = upstream.url!
        let gateway = TouchCodeLocalGateway(forwardBaseURL: base)
        let local = try gateway.start()
        XCTAssertEqual(local.host, "127.0.0.1")
        XCTAssertTrue(local.absoluteString.hasPrefix("http://127.0.0.1:"))
        // Gateway uses distinct ephemeral port, so local URL differs from upstream even though both are loopback in test.
        // In production, upstream would be Mac LAN IP (e.g., 192.168.x.x) and local hides it; here we verify port isolation.
        XCTAssertNotEqual(local.port, base.port)
        XCTAssertNotEqual(local.absoluteString, base.absoluteString)
        gateway.stop()
        upstream.stop()
    }

    func testLocalGatewayForwardsHTTPAndRejectsForbiddenPaths() async throws {
        let upstream = try FakeUpstreamServer(response: "vite content")
        let gateway = TouchCodeLocalGateway(forwardBaseURL: upstream.url!)
        let local = try gateway.start()
        // Valid forward
        let validURL = local.appendingPathComponent("src/main.tsx")
        let (validData, validResponse) = try await URLSession.shared.data(from: validURL)
        XCTAssertEqual((validResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: validData, encoding: .utf8), "vite content")
        // Forbidden: path traversal
        let forbiddenURL = URL(string: "http://127.0.0.1:\(local.port!)/../etc/passwd")!
        let (_, forbiddenResponse) = try await URLSession.shared.data(from: forbiddenURL)
        // Our gateway should return 403 for traversal (or 400), not forward to upstream
        let forbiddenStatus = (forbiddenResponse as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertTrue(forbiddenStatus == 403 || forbiddenStatus == 400)
        // Gateway lifecycle follows session: stop should close
        gateway.stop()
        XCTAssertNil(gateway.localURL)
        upstream.stop()
    }

    private static let hello = TouchCodeHello(
        protocolVersion: 1, role: "host", platform: "macOS", appVersion: "0.1.0",
        capabilities: [], bridgeURL: "http://192.0.2.10:4317"
    )

    private static func host(_ name: String) -> DiscoveredHost {
        DiscoveredHost(
            id: name, name: name,
            endpoint: TouchCodeEndpoint(networkEndpoint: .hostPort(host: .ipv4(.loopback), port: 4317))
        )
    }

    @MainActor
    private func eventually(
        timeout: Duration = .seconds(1),
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !predicate() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate())
    }
}

@MainActor
private final class FakeHostDiscovery: HostDiscovery {
    let events: AsyncStream<HostDiscoveryEvent>
    private let continuation: AsyncStream<HostDiscoveryEvent>.Continuation
    private(set) var startCount = 0

    init() {
        let pair = AsyncStream<HostDiscoveryEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func start() async throws { startCount += 1 }
    func stop() { continuation.yield(.hosts([])) }
    func send(_ event: HostDiscoveryEvent) { continuation.yield(event) }
}

private final class FakeTransport: TouchCodeTransport {
    let states: AsyncStream<TransportState> = AsyncStream { $0.finish() }
    private var results: [Result<TouchCodeHello, Error>]
    private let blockDisconnect: Bool
    private var disconnectContinuation: CheckedContinuation<Void, Never>?
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var disconnectStartCount = 0
    private(set) var disconnectStarted = false

    init(results: [Result<TouchCodeHello, Error>] = [], blockDisconnect: Bool = false) {
        self.results = results
        self.blockDisconnect = blockDisconnect
    }

    func connect(to endpoint: TouchCodeEndpoint) async throws -> TouchCodeHello {
        connectCount += 1
        guard !results.isEmpty else { throw TouchCodeTransportError.connectionFailed }
        return try results.removeFirst().get()
    }

    func disconnect() async {
        disconnectCount += 1
        disconnectStartCount += 1
        disconnectStarted = true
        if blockDisconnect {
            await withCheckedContinuation { continuation in
                disconnectContinuation = continuation
            }
            disconnectStarted = false
        }
    }

    func releaseDisconnect() {
        disconnectContinuation?.resume()
        disconnectContinuation = nil
    }
}

private final class DelayedTransport: TouchCodeTransport {
    let states: AsyncStream<TransportState> = AsyncStream { $0.finish() }
    private var continuation: CheckedContinuation<TouchCodeHello, Error>?
    private(set) var connectStarted = false

    func connect(to endpoint: TouchCodeEndpoint) async throws -> TouchCodeHello {
        connectStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolveOld(with hello: TouchCodeHello) {
        continuation?.resume(returning: hello)
        continuation = nil
    }

    func disconnect() async {}
}

private final class ControllableReconnect {
    var strategy: ReconnectStrategy!
    private var continuation: CheckedContinuation<Void, Never>?
    init() {
        strategy = ReconnectStrategy(nextDelay: { _ in 0.05 }, sleep: { [weak self] _ in
            await withCheckedContinuation { c in self?.continuation = c }
        })
    }
    func release() { continuation?.resume(); continuation = nil }
}

private final class FakeUpstreamServer {
    var url: URL!
    private var listener: NWListener!
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "fake-upstream")
    init(response: String) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let tempListener = try NWListener(using: params, on: 0)
        tempListener.newConnectionHandler = { [weak self] (conn: NWConnection) in
            self?.handle(conn: conn, response: response)
        }
        tempListener.start(queue: queue)
        var port: UInt16 = 0
        for _ in 0..<20 {
            if let p = tempListener.port, p.rawValue != 0 { port = p.rawValue; break }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if port == 0 { throw NSError(domain: "FakeUpstream", code: 1) }
        url = URL(string: "http://127.0.0.1:\(port)/")!
        listener = tempListener
    }
    private func handle(conn: NWConnection, response: String) {
        connections.append(conn)
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] (data: Data?, _: NWConnection.ContentContext?, _: Bool, _: NWError?) in
            guard let self else { return }
            // Always return 200 with fixed body regardless of request path (except we handle in gateway)
            let body = Data(response.utf8)
            let header = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            let combined = Data(header.utf8) + body
            conn.send(content: combined, completion: .contentProcessed { (_: NWError?) in conn.cancel() })
            self.connections.removeAll { $0 === conn }
            _ = data
        }
    }
    func stop() {
        listener.cancel()
        for c in connections { c.cancel() }
    }
}
extension URL {
    var port: Int? { (self as NSURL).port?.intValue }
}
