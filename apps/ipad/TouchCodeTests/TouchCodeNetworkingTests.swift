import Foundation
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
    private(set) var connectCount = 0

    init(results: [Result<TouchCodeHello, Error>] = []) { self.results = results }

    func connect(to endpoint: TouchCodeEndpoint) async throws -> TouchCodeHello {
        connectCount += 1
        guard !results.isEmpty else { throw TouchCodeTransportError.connectionFailed }
        return try results.removeFirst().get()
    }

    func disconnect() async {}
}
