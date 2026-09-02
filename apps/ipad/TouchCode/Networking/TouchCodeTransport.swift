import Foundation
import Network

enum TransportFrameLimits {
    static let maxHelloBytes = 64 * 1024
    static let maxEnvelopeBytes = 1 * 1024 * 1024
    static let maxPayloadBytes = 1 * 1024 * 1024
    static let heartbeatInterval: TimeInterval = 30
    static let heartbeatTimeout: TimeInterval = 90
    static let initialReconnectDelay: TimeInterval = 0.5
    static let maxReconnectDelay: TimeInterval = 30
}

enum TransportFrameError: Error, Equatable {
    case helloTooLarge
    case envelopeTooLarge
    case payloadTooLarge
    case unsupportedProtocol
    case invalidEnvelope
}

struct TouchCodeEnvelope: Codable, Equatable {
    let version: Int
    let id: UUID
    let kind: String
    let payload: JSONValue?
    let sentAt: Int?
    enum CodingKeys: String, CodingKey { case version, id, kind, payload, sentAt }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "unsupported JSON"))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

func validateHelloBytes(_ data: Data) throws {
    guard data.count <= TransportFrameLimits.maxHelloBytes else { throw TransportFrameError.helloTooLarge }
}
func validateEnvelopeBytes(_ data: Data) throws {
    guard data.count <= TransportFrameLimits.maxEnvelopeBytes else { throw TransportFrameError.envelopeTooLarge }
}
func validateEnvelope(_ envelope: TouchCodeEnvelope) throws {
    guard envelope.version == 1 else { throw TransportFrameError.unsupportedProtocol }
    if let payload = envelope.payload {
        let encoded = try JSONEncoder().encode(payload)
        guard encoded.count <= TransportFrameLimits.maxPayloadBytes else { throw TransportFrameError.payloadTooLarge }
    }
}
func nextReconnectDelay(attempt: Int) -> TimeInterval {
    precondition(attempt >= 0, "attempt must be non-negative")
    let delay = TransportFrameLimits.initialReconnectDelay * pow(2.0, Double(attempt))
    return min(delay, TransportFrameLimits.maxReconnectDelay)
}

protocol HeartbeatMonitoring {
    var ticks: AsyncStream<Void> { get }
    func start()
    func stop()
    func receivedPong()
    func heartbeatTimedOut() -> Bool
}
final class HeartbeatMonitor: HeartbeatMonitoring {
    let ticks: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var timer: Timer?
    private var lastPong: Date = Date()
    private let interval: TimeInterval
    private let timeout: TimeInterval
    private let now: () -> Date
    init(interval: TimeInterval = TransportFrameLimits.heartbeatInterval,
         timeout: TimeInterval = TransportFrameLimits.heartbeatTimeout,
         now: @escaping () -> Date = Date.init) {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        ticks = pair.stream
        continuation = pair.continuation
        self.interval = interval
        self.timeout = timeout
        self.now = now
    }
    func start() {
        lastPong = now()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.continuation.yield(()) }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil }
    func receivedPong() { lastPong = now() }
    func heartbeatTimedOut() -> Bool { now().timeIntervalSince(lastPong) > timeout }
}
final class FakeHeartbeatMonitor: HeartbeatMonitoring {
    let ticks: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var timedOut = false
    init() {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        ticks = pair.stream
        continuation = pair.continuation
    }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func receivedPong() { timedOut = false }
    func heartbeatTimedOut() -> Bool { timedOut }
    func triggerTick() { continuation.yield(()) }
    func setTimedOut(_ value: Bool) { timedOut = value }
}
final class ReconnectStrategy {
    private var attempt = 0
    private let nextDelay: (Int) -> TimeInterval
    private let sleep: (TimeInterval) async -> Void
    init(nextDelay: @escaping (Int) -> TimeInterval = nextReconnectDelay,
         sleep: @escaping (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.nextDelay = nextDelay
        self.sleep = sleep
    }
    func reset() { attempt = 0 }
    func waitForNextAttempt() async {
        let delay = nextDelay(attempt)
        attempt += 1
        await sleep(delay)
    }
    var currentAttempt: Int { attempt }
}

enum TransportState: Equatable {
    case idle
    case connecting
    case ready
    case failed
    case reconnecting
}

struct TouchCodeHello: Decodable, Equatable {
    let protocolVersion: Int
    let role: String
    let platform: String
    let appVersion: String
    let capabilities: [String]
    let bridgeURL: String
}

protocol TouchCodeTransport: AnyObject {
    var states: AsyncStream<TransportState> { get }
    func connect(to endpoint: TouchCodeEndpoint) async throws -> TouchCodeHello
    func disconnect() async
}

enum TouchCodeTransportError: Error {
    case connectionFailed
    case invalidResponse
    case unsupportedProtocol
    case responseTooLarge
}

/// Phase-0 transport: resolve the Bonjour endpoint with Network.framework and
/// negotiate the versioned hello over the existing Bridge HTTP connection.
/// It is intentionally replaceable; QUIC + TLS belongs to the secure transport phase.
final class PrototypeHTTPTransport: TouchCodeTransport, @unchecked Sendable {
    let states: AsyncStream<TransportState>
    private let continuation: AsyncStream<TransportState>.Continuation
    private let queue = DispatchQueue(label: "com.touchcode.ipad.prototype-transport")
    private var activeConnection: NWConnection?

    init() {
        let pair = AsyncStream<TransportState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        states = pair.stream
        continuation = pair.continuation
        continuation.yield(.idle)
    }

    func connect(to endpoint: TouchCodeEndpoint) async throws -> TouchCodeHello {
        await disconnect()
        continuation.yield(.connecting)
        let connection = NWConnection(to: endpoint.networkEndpoint, using: .tcp)
        activeConnection = connection
        do {
            let data = try await receiveHello(over: connection)
            let hello = try Self.decodeHello(from: data)
            guard hello.protocolVersion == 1, hello.role == "host" else {
                throw TouchCodeTransportError.unsupportedProtocol
            }
            continuation.yield(.ready)
            return hello
        } catch {
            continuation.yield(.failed)
            connection.cancel()
            if activeConnection === connection { activeConnection = nil }
            throw error
        }
    }

    func disconnect() async {
        activeConnection?.cancel()
        activeConnection = nil
        continuation.yield(.idle)
    }

    private func receiveHello(over connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var response = Data()
            var finished = false

            func finish(_ result: Result<Data, Error>) {
                guard !finished else { return }
                finished = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                switch result {
                case .success(let data):
                    do {
                        try validateHelloBytes(data)
                        continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            var receiveNext: (() -> Void)!
            receiveNext = {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, complete, error in
                    if let data { response.append(data) }
                    if response.count > TransportFrameLimits.maxHelloBytes {
                        finish(.failure(TouchCodeTransportError.responseTooLarge))
                    } else if let error {
                        finish(.failure(error))
                    } else if complete {
                        finish(.success(response))
                    } else {
                        receiveNext()
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = Data("GET /v1/hello HTTP/1.1\r\nHost: touchcode.local\r\nAccept: application/json\r\nConnection: close\r\n\r\n".utf8)
                    connection.send(content: request, completion: .contentProcessed { error in
                        if let error { finish(.failure(error)) }
                        else { receiveNext() }
                    })
                case .failed(let error):
                    finish(.failure(error))
                case .cancelled:
                    finish(.failure(TouchCodeTransportError.connectionFailed))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    static func decodeHello(from response: Data) throws -> TouchCodeHello {
        guard let separator = response.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: response[..<separator.lowerBound], encoding: .utf8),
              header.hasPrefix("HTTP/1.1 200") || header.hasPrefix("HTTP/1.0 200") else {
            throw TouchCodeTransportError.invalidResponse
        }
        let body = response[separator.upperBound...]
        return try JSONDecoder().decode(TouchCodeHello.self, from: body)
    }
}
